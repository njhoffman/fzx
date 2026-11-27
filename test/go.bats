#!/usr/bin/env bats
# lib/go.sh: the go built-in (enter on a screen of paths): what each target is, and where it goes

load test_helper

setup() {
  setup_fzx
  W="$BATS_TEST_TMPDIR/w"
  mkdir -p "$W/dir" "$BATS_TEST_TMPDIR/bin"
  printf 'one\ntwo\nthree\n' > "$W/notes.txt"
  printf 'x\n' > "$W/b.txt"
  printf '\0\1\2' > "$W/image.bin"
  : > "$W/empty"
  printf 'x\n' > "$W/a:1"
  GO_LOG="$BATS_TEST_TMPDIR/go.log"
  export GO_LOG
  # the editor, xdg-open and tmux record what they were asked
  printf '#!/bin/sh\necho "edit $*" >> "$GO_LOG"\n' > "$BATS_TEST_TMPDIR/bin/fake-editor"
  printf '#!/bin/sh\necho "open $*" >> "$GO_LOG"\n' > "$BATS_TEST_TMPDIR/bin/xdg-open"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" << 'EOF'
#!/bin/sh
echo "tmux $*" >> "$GO_LOG"
[ "$1" = display-message ] && printf '%s\n' "$TMUX_INFO"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" VISUAL=fake-editor EDITOR=fake-editor
  export FZX_TTY="$BATS_TEST_TMPDIR/tty"
  : > "$FZX_TTY"
  unset FZX_ORIGIN_PANE FZX_GO_FILE
  cd "$W"
}

# go_log: what was recorded, once the detached xdg-open (setsid -f) has written
go_log() {
  local i
  for ((i = 0; i < 50; i++)); do
    [[ -z "${1:-}" ]] || grep -q "$1" "$GO_LOG" 2> /dev/null && break
    sleep 0.05
  done
  cat "$GO_LOG" 2> /dev/null
}

@test "targets: text files edit (path:line gives the line), directories cd, anything else opens" {
  load_libs log go
  local _kinds=() _paths=() _lines=()
  fzx::go_targets notes.txt:2 dir image.bin empty "a:1" b.txt:3:7 https://example.org/x
  [ "${_kinds[*]}" = "edit cd open edit edit edit open" ]
  [ "${_paths[0]}" = "$W/notes.txt" ]
  [ "${_lines[0]}" = 2 ]
  [ "${_paths[1]}" = "$W/dir" ]
  # a colon in a file name: the whole name is the path
  [ "${_paths[4]}" = "$W/a:1" ]
  [ -z "${_lines[4]}" ]
  [ "${_lines[5]}" = 3 ]
  [ "${_paths[6]}" = https://example.org/x ]
}

@test "targets: a missing path is skipped with a message; ~ is the home directory" {
  load_libs log go
  local _kinds=() _paths=() _lines=()
  run fzx::go_targets nope.txt
  [[ "$output" == *"no such file or directory: nope.txt"* ]]
  HOME="$W" fzx::go_targets "~/dir"
  [ "${_kinds[*]}" = cd ]
  [ "${_paths[0]}" = "$W/dir" ]
}

@test "targets: the module's go_targets hook maps the selection (todos items)" {
  load_libs log go
  printf -- '- [ ] (p1) [x] first\n- [ ] (p2) [x] second\n' > "$W/TODO.md"
  local _kinds=() _paths=() _lines=()
  FZX_MODULE=todos FZX_MODULE_DIR="$FZX_REPO/modules/todos" fzx::go_targets "$W/TODO.md"$'\x1f'2$'\x1f'second
  [ "${_kinds[*]}" = edit ]
  [ "${_paths[0]}" = "$W/TODO.md" ]
  [ "${_lines[0]}" = 2 ]
}

@test "standalone: the editor runs on the terminal with every file, at the first one's line" {
  run "$FZX" builtin go notes.txt:2 b.txt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(go_log)" = "edit +2 -- $W/notes.txt $W/b.txt" ]
}

@test "standalone: anything else is xdg-open'd at once" {
  run "$FZX" builtin go image.bin
  [ "$status" -eq 0 ]
  [ "$(go_log open)" = "open $W/image.bin" ]
}

@test "standalone: a directory is printed, or written to FZX_GO_FILE (the zsh fzx function cds there)" {
  run "$FZX" builtin go dir
  [ "$output" = "$W/dir" ]
  FZX_GO_FILE="$BATS_TEST_TMPDIR/gofile" run "$FZX" builtin go dir other-missing
  [[ "$output" != "$W/dir" ]]
  [ "$(cat "$BATS_TEST_TMPDIR/gofile")" = "$W/dir" ]
}

@test "origin pane at a zsh with the widget: the command line goes to the pane and the key is sent" {
  TMUX=x FZX_ORIGIN_PANE=%7 TMUX_INFO=$'zsh\t1b 5b 7e' run "$FZX" builtin go dir notes.txt:3
  [ "$status" -eq 0 ]
  run go_log
  [ "${lines[0]}" = "tmux display-message -p -t %7 #{pane_current_command}	#{@fzx_zsh}" ]
  [ "${lines[1]}" = "tmux set-option -p -t %7 @fzx_go builtin cd -- $W/dir && fake-editor +3 -- $W/notes.txt" ]
  [ "${lines[2]}" = "tmux send-keys -t %7 -H 1b 5b 7e" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "origin pane running something else, or a zsh without the widget: a new window after it" {
  TMUX=x FZX_ORIGIN_PANE=%7 TMUX_INFO=$'claude\t1b 5b 7e' run "$FZX" builtin go notes.txt:3
  [ "$(go_log | tail -1)" = "tmux new-window -a -t %7 -c $W fake-editor +3 -- $W/notes.txt" ]
  : > "$GO_LOG"
  TMUX=x FZX_ORIGIN_PANE=%7 TMUX_INFO=$'zsh\t' run "$FZX" builtin go dir
  [ "$(go_log | tail -1)" = "tmux new-window -a -t %7 -c $W/dir" ]
}

@test "session: the owner carries out go once fzf is gone; fzx prints nothing" {
  stub_fzf
  STUB_FZF_RUN="'$FZX' _cb action go notes.txt:2" run "$FZX" -m files "$W"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(go_log)" = "edit +2 -- $W/notes.txt" ]
  [ -z "$(session_dirs)" ]
}

@test "session: a directory goes to FZX_GO_FILE, else it is fzx's output" {
  stub_fzf
  STUB_FZF_RUN="'$FZX' _cb action go dir" run "$FZX" -m files "$W"
  [ "$output" = "$W/dir" ]
  FZX_GO_FILE="$BATS_TEST_TMPDIR/gofile" STUB_FZF_RUN="'$FZX' _cb action go dir" run "$FZX" -m files "$W"
  [ -z "$output" ]
  [ "$(cat "$BATS_TEST_TMPDIR/gofile")" = "$W/dir" ]
}

@test "session: an aborted fzf leaves go alone" {
  stub_fzf
  STUB_FZF_RC=130 STUB_FZF_RUN="'$FZX' _cb action go notes.txt" run "$FZX" -m files "$W"
  [ "$status" -eq 130 ]
  [ ! -s "$GO_LOG" ]
}

@test "enter is go in files, recent, dirs, repos and todos; a picker (FZX_PRINT=1) keeps it printing" {
  stub_fzf
  local m
  for m in files files:grep files:dirs recent dirs repos todos; do
    run "$FZX" -m "$m" --dry-run
    [[ "$output" == *"'enter:become($FZX _cb action go "* ]] || { echo "$m: no go on enter"; false; }
  done
  run "$FZX" -m files:grep --dry-run
  [[ "$output" == *"'enter:become($FZX _cb action go {1}:{2})'"* ]]
  FZX_PRINT=1 run "$FZX" -m files --dry-run
  [[ "$output" != *"'enter:"* ]]
}
