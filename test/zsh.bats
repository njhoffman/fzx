#!/usr/bin/env bats
# shell/fzx.zsh: formatting of selections and key bindings, in a clean zsh (no user config)

load test_helper

ZSH_INT="$(readlink -f "$BATS_TEST_DIRNAME/../shell/fzx.zsh")"

setup() {
  command -v zsh > /dev/null || skip "zsh not installed"
  setup_fzx
}

# zsh -f with the integration loaded inside an interactive-like zle-less shell; widgets are defined
# with zle -N, which needs zle, so load it in an interactive shell
zsh_run() {
  zsh -f -i -c "source '$ZSH_INT'; $1" 2> /dev/null
}

@test "fzx-format: paths under PWD become relative, others stay, all shell-quoted" {
  mkdir -p "$BATS_TEST_TMPDIR/w"
  cd "$BATS_TEST_TMPDIR/w"
  run zsh_run "printf '%s\n' '$PWD/a.txt' '$PWD/my notes.md' '/etc/passwd' '$PWD' '' \"it's\" | fzx-format"
  [ "$output" = "a.txt 'my notes.md' /etc/passwd . it\\'s" ]
}

@test "fzx-format: a symlinked working directory still gives relative paths" {
  mkdir -p "$BATS_TEST_TMPDIR/real/sub"
  ln -s "$BATS_TEST_TMPDIR/real" "$BATS_TEST_TMPDIR/link"
  cd "$BATS_TEST_TMPDIR/link"
  local real
  real="$(readlink -f "$BATS_TEST_TMPDIR/real")"
  run zsh_run "cd '$BATS_TEST_TMPDIR/link'; printf '%s\n' '$real/sub/x' '$BATS_TEST_TMPDIR/link/y' '$real' | fzx-format"
  [ "$output" = "sub/x y ." ]
}

@test "fzx-format: pids and hashes pass through" {
  run zsh_run "printf '%s\n' 123 456 | fzx-format"
  [ "$output" = "123 456" ]
}

@test "widgets are bound in vi insert, vi command and emacs maps" {
  run zsh_run 'for m in viins vicmd emacs; do bindkey -M $m "^[f"; done; for k in "^[d" "^[g" "^[p" "^[m"; do bindkey -M viins $k; done'
  [ "${lines[0]}" = '"^[f" fzx-files-widget' ]
  [ "${lines[1]}" = '"^[f" fzx-files-widget' ]
  [ "${lines[2]}" = '"^[f" fzx-files-widget' ]
  [[ "$output" == *'"^[d" fzx-dirs-widget'* && "$output" == *'"^[g" fzx-git-widget'* ]]
  [[ "$output" == *'"^[p" fzx-ps-widget'* && "$output" == *'"^[m" fzx-menu-widget'* ]]
  run zsh_run 'bindkey -M viins "^[s"'
  [ "$output" = '"^[s" fzx-shell-widget' ]
}

@test "keys can be changed or unbound before sourcing; FZX_ZSH_NO_BIND binds nothing" {
  run zsh -f -i -c "typeset -A FZX_ZSH_KEYS; FZX_ZSH_KEYS[files]='^Xf'; FZX_ZSH_KEYS[ps]=''; source '$ZSH_INT'; bindkey -M viins '^Xf'; bindkey -M viins '^[p'; bindkey -M viins '^[d'" 2> /dev/null
  [ "${lines[0]}" = '"^Xf" fzx-files-widget' ]
  [[ "${lines[1]}" != *fzx-ps-widget* ]]
  [ "${lines[2]}" = '"^[d" fzx-dirs-widget' ]
  run zsh -f -i -c "FZX_ZSH_NO_BIND=1 source '$ZSH_INT'; bindkey -M viins '^[f'; zle -l | grep -c '^fzx-'" 2> /dev/null
  [[ "${lines[0]}" != *fzx-files-widget* ]]
  # fzx-go-widget too (its key is fzx's own, for the M-o popup's go)
  [ "${lines[1]}" = 13 ]
}

@test "go: FZX_ZSH_GO_KEY runs fzx-go-widget in every map, and in tmux the pane's @fzx_zsh holds it in hex" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "tmux $*" >> "%s/tmux.log"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  run zsh_run "PATH='$BATS_TEST_TMPDIR/bin':\$PATH; for m in viins vicmd emacs; do bindkey -M \$m \$'\\e[9271~'; done"
  [ "${lines[0]}" = '"^[[9271~" fzx-go-widget' ]
  [ "${lines[2]}" = '"^[[9271~" fzx-go-widget' ]
  run zsh -f -i -c "PATH='$BATS_TEST_TMPDIR/bin':\$PATH; TMUX=x TMUX_PANE=%9; source '$ZSH_INT'; sleep 0.3" 2> /dev/null
  [ "$(cat "$BATS_TEST_TMPDIR/tmux.log")" = "tmux set-option -p -t %9 @fzx_zsh 1b 5b 39 32 37 31 7e" ]
  run zsh -f -i -c "FZX_ZSH_NO_GO=1; source '$ZSH_INT'; bindkey -M viins \$'\\e[9271~'; whence -w fzx" 2> /dev/null
  [[ "${lines[0]}" != *fzx-go-widget* ]]
  [[ "${lines[1]}" != *function* ]]
}

@test "go: fzx-go-widget sets the typed line aside and runs the pane's @fzx_go" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  {
    printf '#!/bin/sh\necho "tmux $*" >> "%s/tmux.log"\n' "$BATS_TEST_TMPDIR"
    printf '[ "$1" = show-options ] && echo "builtin cd -- /tmp && nvim +3 -- /tmp/x"\nexit 0\n'
  } > "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  run zsh_run "PATH='$BATS_TEST_TMPDIR/bin':\$PATH; TMUX_PANE=%9; zle() { print -r -- \"zle \$*\"; }; fzx-go-widget; print -r -- \"BUFFER=\$BUFFER\""
  [ "${lines[0]}" = "zle push-line" ]
  [ "${lines[1]}" = "zle accept-line" ]
  [ "${lines[2]}" = "BUFFER=builtin cd -- /tmp && nvim +3 -- /tmp/x" ]
  grep -q "set-option -pu -t %9 @fzx_go" "$BATS_TEST_TMPDIR/tmux.log"
}

@test "go: the fzx function cds where fzx's go leaves (FZX_GO_FILE), at a terminal only" {
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/there"
  printf '#!/usr/bin/env bash\n[ -n "$FZX_GO_FILE" ] && echo "%s/there" > "$FZX_GO_FILE"\necho "ran $*"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/fakefzx"
  chmod +x "$BATS_TEST_TMPDIR/bin/fakefzx"
  local pre="FZX_ZSH_BIN='$BATS_TEST_TMPDIR/bin/fakefzx'; source '$ZSH_INT'"
  run script -qec "zsh -f -i -c \"$pre; fzx -m dirs; print -r -- pwd=\\\$PWD\"" /dev/null
  [[ "$output" == *"ran -m dirs"* ]]
  [[ "$output" == *"pwd=$BATS_TEST_TMPDIR/there"* ]]
  # in a command substitution nothing is written for it: fzx prints as before
  run zsh -f -i -c "$pre; x=\$(fzx -m dirs); print -r -- \"\$x pwd=\$PWD\"" 2> /dev/null
  [ "$output" = "ran -m dirs pwd=$PWD" ]
}

@test "claude widget: unbound by default, cds into the project the claude module prints" {
  run zsh_run 'zle -l | grep -c "^fzx-claude-widget"'
  [ "$output" = 1 ]
  run zsh_run 'fzx-cd-widget-run() { print -r -- "args: $*"; }; fzx-claude-widget'
  [ "$output" = "args: -m claude" ]
}

@test "snippets widget: unbound by default, inserts the text fzx prints as it is" {
  run zsh_run 'zle -l | grep -c "^fzx-snippets-widget"'
  [ "$output" = 1 ]
  # a terminal for the widget's /dev/tty (script gives the command a pty)
  printf '%s\n' "source '$ZSH_INT'" 'zle() { :; }' 'fzx-run() { print -rn -- "ls -la | grep x"; }' \
    'LBUFFER="x "; fzx-snippets-widget; print -r -- "[$LBUFFER]"' > "$BATS_TEST_TMPDIR/w.zsh"
  run script -qec "zsh -f -i '$BATS_TEST_TMPDIR/w.zsh'" /dev/null
  [[ "$output" == *"[x ls -la | grep x]"* ]]
}

@test "menu-popup: unbound by default, bound when given a key; runs fzx --popup" {
  run zsh_run 'bindkey -M viins "^G"; zle -l | grep -c "^fzx-menu-popup-widget"'
  [[ "${lines[0]}" != *fzx-menu-popup-widget* ]]
  [ "${lines[1]}" = 1 ]
  run zsh -f -i -c "typeset -A FZX_ZSH_KEYS; FZX_ZSH_KEYS[menu-popup]='^G'; source '$ZSH_INT'; for m in viins vicmd emacs; do bindkey -M \$m '^G'; done" 2> /dev/null
  [ "${lines[0]}" = '"^G" fzx-menu-popup-widget' ]
  [ "${lines[2]}" = '"^G" fzx-menu-popup-widget' ]
  run zsh_run 'fzx-insert() { print -r -- "args: $*"; }; fzx-menu-popup-widget'
  [ "$output" = "args: --popup" ]
}

@test "fzf with no options at a terminal opens the files module; anything else is the real fzf" {
  stub_fzf
  printf '#!/usr/bin/env bash\necho "fzx $*"\n' > "$BATS_TEST_TMPDIR/bin/fakefzx"
  chmod +x "$BATS_TEST_TMPDIR/bin/fakefzx"
  local pre="FZX_ZSH_BIN='$BATS_TEST_TMPDIR/bin/fakefzx'; source '$ZSH_INT'"
  # a terminal on stdin (script gives the command a pty)
  run script -qec "zsh -f -i -c \"$pre; fzf\"" /dev/null
  [[ "$output" == *"fzx -m files"* ]]
  STUB_FZF_OUT=real run zsh -f -i -c "$pre; fzf --height 3 < /dev/null" 2> /dev/null
  [ "$output" = real ]
  STUB_FZF_OUT=real run zsh -f -i -c "$pre; echo a | fzf" 2> /dev/null
  [ "$output" = real ]
  run script -qec "zsh -f -i -c \"FZX_ZSH_NO_FZF=1; $pre; whence -w fzf\"" /dev/null
  [[ "$output" == *"fzf: command"* ]]
}
