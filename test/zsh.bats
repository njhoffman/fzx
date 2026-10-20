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
}

@test "keys can be changed or unbound before sourcing; FZX_ZSH_NO_BIND binds nothing" {
  run zsh -f -i -c "typeset -A FZX_ZSH_KEYS; FZX_ZSH_KEYS[files]='^Xf'; FZX_ZSH_KEYS[ps]=''; source '$ZSH_INT'; bindkey -M viins '^Xf'; bindkey -M viins '^[p'; bindkey -M viins '^[d'" 2> /dev/null
  [ "${lines[0]}" = '"^Xf" fzx-files-widget' ]
  [[ "${lines[1]}" != *fzx-ps-widget* ]]
  [ "${lines[2]}" = '"^[d" fzx-dirs-widget' ]
  run zsh -f -i -c "FZX_ZSH_NO_BIND=1 source '$ZSH_INT'; bindkey -M viins '^[f'; zle -l | grep -c '^fzx-'" 2> /dev/null
  [[ "${lines[0]}" != *fzx-files-widget* ]]
  [ "${lines[1]}" = 5 ]
}
