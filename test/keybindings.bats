#!/usr/bin/env bats
# the keybindings module: the zsh dump (in a clean zsh), rows from a fixture dump, the zsh -ic fallback
# (a private ZDOTDIR), fzf rows from FZF_DEFAULT_OPTS, previews

load test_helper

KB="$(readlink -f "$BATS_TEST_DIRNAME/../modules/keybindings")"

setup() {
  command -v zsh > /dev/null || skip "zsh not installed"
  setup_fzx
  export NO_COLOR=1 FZF_DEFAULT_OPTS_FILE=/dev/null FZF_DEFAULT_OPTS=''
  DUMP="$FZX_STATE_DIR/keybindings/zsh.tsv"
  mkdir -p "${DUMP%/*}" "$FZX_CACHE_DIR/keybindings" "$BATS_TEST_TMPDIR/fn"
  # zle's docs, as parsed from zshzle(1) (newer than the man page, so used as they are)
  printf 'beginning-of-line\tMove to the beginning of the line.\tMove to the beginning of the line. If already there, the previous one.\nedit-command-line\tEdit the command line.\tEdit the command line using your visual editor.\n' \
    > "$FZX_CACHE_DIR/keybindings/zle.tsv"
  printf '#!/bin/zsh\n# section rule below\n# -- widgets --\n# open the line in the editor, fancily\nmy-edit() {\n  :\n}\n' > "$BATS_TEST_TMPDIR/fn/widgets.zsh"
}

# a fixture dump, as fzx-keys-dump writes it
fixture_dump() {
  {
    printf 'bind\temacs\t"^@"-"^I" self-insert\n'
    printf 'bind\temacs\t"^A" beginning-of-line\n'
    printf 'bind\temacs\t"^X^E" my-edit\n'
    printf 'bind\temacs\t"^[f" forward-word\n'
    printf 'bind\temacs\t"^[[A" up-line-or-history\n'
    printf 'bind\temacs\t"^[[200~" bracketed-paste\n'
    printf 'bind\temacs\t"^Xg" "git status^M"\n'
    printf 'bind\tviins\t"^A" vi-beginning-of-line\n'
    printf 'bind\tvicmd\t"0" undefined-key\n'
    printf 'user\tmy-edit\tmy-edit\t%s\n' "$BATS_TEST_TMPDIR/fn/widgets.zsh"
  } > "$DUMP"
}

src() { FZX_MODE="$1" "$KB/source.sh"; }
prev() { "$KB/preview.sh" "$@" | sed 's/\x1b\[[0-9;]*m//g'; }
plain() { printf '%s\n' "${lines[@]}" | cut -f2 | sed 's/  */ /g'; }

@test "dump.zsh: every keymap but .safe and main, user widgets with their file; the file version" {
  run zsh -f -i -c "source '$KB/dump.zsh'; my-w() { :; }; zle -N my-w; bindkey -M viins '^Xq' my-w; fzx-keys-dump" 2> /dev/null
  [[ "$output" == *$'bind\tviins\t"^Xq" my-w'* ]]
  [[ "$output" != *$'bind\t.safe\t'* && "$output" != *$'bind\tmain\t'* ]]
  [[ "$output" == *$'user\tmy-w\tmy-w\t'* ]]
  zsh -f -i -c "source '$KB/dump.zsh'; fzx-keys-dump-file" 2> /dev/null
  grep -q $'^bind\temacs\t"^A" beginning-of-line$' "$DUMP"
}

@test "zsh rows: friendly keys, zle and user descriptions, strings; ranges and skipped widgets left out" {
  fixture_dump
  run src zsh
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 7 ]
  [[ "${lines[0]}" == 'bindkey -M emacs "^A" beginning-of-line'$'\t'*$'\tbeginning-of-line' ]]
  run plain_out
  [[ "$output" == *"emacs ctrl-a beginning-of-line Move to the beginning of the line."* ]]
  [[ "$output" == *"emacs ctrl-x ctrl-e my-edit open the line in the editor, fancily"* ]]
  [[ "$output" == *"emacs alt-f forward-word"* && "$output" == *"emacs up up-line-or-history"* ]]
  [[ "$output" == *"emacs paste bracketed-paste"* ]]
  [[ "$output" == *'emacs ctrl-x g send "git status^M" types the string'* ]]
  [[ "$output" != *self-insert* && "$output" != *undefined-key* ]]
}

plain_out() { FZX_MODE=zsh "$KB/source.sh" | cut -f2 | sed 's/  */ /g'; }

@test "zsh: a stale or missing dump is read again from an interactive zsh (ZDOTDIR), and kept" {
  mkdir -p "$BATS_TEST_TMPDIR/zdot"
  printf 'echo noise from startup\nmy-z() { :; }\nzle -N my-z\nbindkey -M emacs "^Xz" my-z\n' > "$BATS_TEST_TMPDIR/zdot/.zshrc"
  ZDOTDIR="$BATS_TEST_TMPDIR/zdot" run src zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *'bindkey -M emacs "^Xz" my-z'* && "$output" != *noise* ]]
  grep -q '"^Xz" my-z' "$DUMP"
  # stale: older than the ttl
  fixture_dump
  touch -d '2 days ago' "$DUMP"
  ZDOTDIR="$BATS_TEST_TMPDIR/zdot" run src zsh
  [[ "$output" == *'"^Xz" my-z'* && "$output" != *my-edit* ]]
}

@test "fzf rows: yours first, then the defaults you leave alone" {
  FZF_DEFAULT_OPTS='--bind ctrl-b:half-page-up --bind "alt-z:execute(echo {})"' run src fzf
  [[ "${lines[0]}" == ctrl-b$'\t'*yours*half-page-up$'\tyours' ]]
  [[ "${lines[1]}" == alt-z$'\t'*'execute(echo {})'$'\tyours' ]]
  [ "$(printf '%s\n' "${lines[@]}" | grep -c $'^ctrl-b\t')" -eq 1 ]
  [[ "$output" == *$'\nalt-f\t'*'forward-word'$'\tfzf'* ]]
}

@test "previews: zsh widget, its keys and the key in each keymap; fzf action and what it replaces" {
  fixture_dump
  run prev 'bindkey -M emacs "^A" beginning-of-line' x beginning-of-line
  [[ "${lines[0]}" == *beginning-of-line* && "$output" == *"If already there, the previous one."* ]]
  [[ "$output" == *$'bound to\n  emacs    ctrl-a'* ]]
  [[ "$output" == *"the same key in each keymap"*"viins    ctrl-a"*"vi-beginning-of-line"* ]]
  run prev 'bindkey -M emacs "^X^E" my-edit' x my-edit
  [[ "$output" == *"user widget  my-edit  in $BATS_TEST_TMPDIR/fn/widgets.zsh"* ]]
  FZF_DEFAULT_OPTS='--bind ctrl-b:half-page-up+offset-middle' FZX_MODE=fzf run prev ctrl-b x yours
  [[ "$output" == *$'half-page-up\n  +offset-middle'* && "$output" == *"over fzf  backward-char"* ]]
}

@test "fzx.zsh: sources the dump and refreshes it; FZX_ZSH_NO_KEYS_DUMP turns it off" {
  local zsh_int
  zsh_int="$(readlink -f "$BATS_TEST_DIRNAME/../shell/fzx.zsh")"
  zsh -f -i -c "source '$zsh_int'; fzx-keys-refresh; sleep 1" 2> /dev/null
  [ -s "$DUMP" ]
  rm -f "$DUMP"
  FZX_ZSH_NO_KEYS_DUMP=1 zsh -f -i -c "source '$zsh_int'; fzx-keys-refresh; sleep 1" 2> /dev/null
  [ ! -e "$DUMP" ]
}
