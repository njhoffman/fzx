#!/usr/bin/env bats
# menu summaries of the modules whose lists depend on where fzx runs: a private tmux server, fixture
# TODO.md files, dumps and directories; never the user's own

load test_helper

setup() {
  setup_fzx
  load_libs log config menu
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

teardown() {
  [[ -n "${TEST_TMUX_SOCKET:-}" ]] && tmux kill-server 2> /dev/null || :
}

# summary <module> <target> [args...]: the module's summary, its config and manifest loaded as the menu does
summary() {
  fzx::menu_entries "$1" "$FZX_REPO/modules/$1"
  "$1::summary" "${@:2}"
}

# a private tmux server behind a tmux on PATH
private_tmux() {
  export TEST_TMUX_BIN="$(command -v tmux)" TEST_TMUX_SOCKET="$BATS_TEST_TMPDIR/tmux.sock"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" << 'STUB'
#!/usr/bin/env bash
exec "$TEST_TMUX_BIN" -S "$TEST_TMUX_SOCKET" "$@"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
}

@test "tmux: sessions, windows across sessions, panes across windows, buffers, key tables" {
  private_tmux
  run summary tmux tmux
  [ "$output" = "no server running" ]
  tmux -f /dev/null new-session -d -s one -x 80 -y 20 'sleep 60'
  tmux new-window -d -t one 'sleep 60'
  tmux new-session -d -s two -x 80 -y 20 'sleep 60'
  tmux split-window -d -t two 'sleep 60'
  tmux set-buffer -b fzx-test hello
  run summary tmux tmux
  [ "$output" = "2 sessions, 0 attached" ]
  run summary tmux tmux:windows
  [ "$output" = "3 windows across 2 sessions" ]
  run summary tmux tmux:panes
  [ "$output" = "4 panes across 3 windows" ]
  run summary tmux tmux:buffers
  [ "$output" = "1 buffers" ]
  run summary tmux tmux:keys
  [[ "$output" =~ ^[0-9]+\ bindings\ in\ [0-9]+\ tables$ ]]
  # the reference entries describe tmux itself, not the server
  run summary tmux tmux:options
  [ -z "$output" ]
}

@test "todos: open, urgent and overdue items here, and across every file in all" {
  mkdir -p "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo"
  git init -q .
  printf '%s\n' '# Todo' '' '## 1. Work' '' '- [ ] **One.** (p1) [bug] first' '- [ ] **Two.** (p2) [feature] (due 2001-01-01) late' \
    '- [x] **Done.** (p1) [bug] finished' '- [ ] **Three.** (p3) [docs] later' > TODO.md
  run summary todos todos
  [ "$output" = "3 open, 1 urgent, 1 overdue" ]
  # all: FZX_TODOS_FILES only, not the user's ghq repositories
  printf '#!/usr/bin/env bash\n' > "$BATS_TEST_TMPDIR/bin/ghq"
  chmod +x "$BATS_TEST_TMPDIR/bin/ghq"
  mkdir -p "$BATS_TEST_TMPDIR/other"
  printf '%s\n' '## 1. More' '' '- [ ] **Four.** (p1) [bug] x' > "$BATS_TEST_TMPDIR/other/TODO.md"
  mkdir -p "$FZX_CONFIG_DIR"
  printf 'FZX_TODOS_ROOTS=()\nFZX_TODOS_FILES=(%q %q)\n' "$BATS_TEST_TMPDIR/repo/TODO.md" "$BATS_TEST_TMPDIR/other/TODO.md" \
    > "$FZX_CONFIG_DIR/config.sh"
  run summary todos todos:all
  [ "$output" = "4 open in 2 files, 2 urgent, 1 overdue" ]
  # applicable as the module finds its file: from a subdirectory too
  mkdir sub && cd sub
  fzx::menu_entries todos "$FZX_REPO/modules/todos"
  # run: sourcing source.sh ends on its false standalone guard, which errexit would stop at
  run todos::applicable todos
  [ "$status" -eq 0 ]
  cd "$BATS_TEST_TMPDIR"
  run todos::applicable todos
  [ "$status" -ne 0 ]
}

@test "dirs: the bookmark count, nothing for the walk of ~" {
  mkdir -p "$FZX_CONFIG_DIR"
  printf 'FZX_DIRS_BOOKMARKS=([a]=/tmp [b]=/usr)\n' > "$FZX_CONFIG_DIR/config.sh"
  run summary dirs dirs:bookmarks
  [ "$output" = "2 bookmarks" ]
  run summary dirs dirs
  [ -z "$output" ]
}

@test "keybindings: zsh from the saved dump only, never a new shell" {
  cat > "$BATS_TEST_TMPDIR/bin/zsh" << 'STUB'
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/zsh-ran"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/zsh"
  run summary keybindings keybindings
  [ "$status" -eq 0 ] && [ -z "$output" ]
  [ ! -e "$BATS_TEST_TMPDIR/zsh-ran" ]
  mkdir -p "$FZX_STATE_DIR/keybindings"
  printf 'bind\temacs\t"^A" beginning-of-line\nbind\temacs\t"^E" end-of-line\nbind\tviins\t"^R" x\nuser\tx\tx\t/f\n' \
    > "$FZX_STATE_DIR/keybindings/zsh.tsv"
  run summary keybindings keybindings
  [ "$output" = "3 bindings in 2 keymaps" ]
}

@test "files: grep counts the files ripgrep would search, and their size" {
  command -v rg > /dev/null || skip "ripgrep not installed"
  mkdir -p "$BATS_TEST_TMPDIR/tree/.git" "$BATS_TEST_TMPDIR/tree/__pycache__"
  cd "$BATS_TEST_TMPDIR/tree"
  head -c 2048 /dev/zero > a.txt
  printf 'x\n' > .hidden
  printf 'x\n' > .git/config
  printf 'x\n' > __pycache__/c.pyc
  run summary files files:grep
  [ "$output" = "2 files, 2.0K" ]
}

@test "man: tldr pages counted by name, common and the configured platforms" {
  local pages="$BATS_TEST_TMPDIR/tldr/pages.en"
  mkdir -p "$pages/common" "$pages/linux" "$pages/osx"
  touch "$pages/common/tar.md" "$pages/linux/tar.md" "$pages/linux/apt.md" "$pages/osx/brew.md"
  FZX_MAN_TLDR_PAGES="$BATS_TEST_TMPDIR/tldr" run summary man man:tldr
  [ "$output" = "2 pages" ]
}
