#!/usr/bin/env bats
# the dirs module: every directory under ~ (all; its fd walk is in test/jump.bats) and bookmarks

load test_helper

DIRS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/dirs")"

setup() {
  setup_fzx
  T="$BATS_TEST_TMPDIR/d"
  mkdir -p "$T/alpha" "$T/beta/deep"
}

bookmarks() {
  mkdir -p "$FZX_CONFIG_DIR/modules/dirs"
  echo "FZX_DIRS_BOOKMARKS=([b]='$T/beta' [a]='$T/alpha' [gone]='$T/gone')" > "$FZX_CONFIG_DIR/modules/dirs/config.sh"
}

@test "bookmarks come from config by name, ~ expanded, missing ones dropped; words filter them" {
  bookmarks
  FZX_MODE=bookmarks run bash -c "'$DIRS/source.sh' | sed 's/\x1b\[[0-9;]*m//g'"
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "$T/alpha"$'\t'*"a  "*"alpha" ]]
  [[ "${lines[1]}" == "$T/beta"$'\t'*"b  "* ]]
  FZX_MODE=bookmarks run bash -c "'$DIRS/source.sh' bet | cut -f1"
  [ "$output" = "$T/beta" ]
  # the sorted column underlined: the name (default), or the path
  FZX_MODE=bookmarks FZX_SORT=name run bash -c "'$DIRS/source.sh' | sed '1!d' | cut -f2"
  [[ "$output" == *$'\e[4ma\e[0m'* ]]
  FZX_MODE=bookmarks FZX_SORT=path run bash -c "'$DIRS/source.sh' | sed '1!d' | cut -f2"
  [[ "$output" != *$'\e[4ma\e[0m'* && "$output" == *$'\e[4m'*alpha* ]]
}

@test "modes: all is the default, bookmarks only when configured; frecent modes are gone" {
  stub_fzf
  run "$FZX" -m dirs
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = all ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *bookmarks* && " ${FZF_ARGS[*]} " != *frecent* ]]
  bookmarks
  run "$FZX" -m dirs:bookmarks
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = bookmarks ]
  FZX_MODE=frecent run "$DIRS/source.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"frecent directories are in the recent module"* ]]
}

@test "bookmarks with words: a single match without the picker; all takes them as the query" {
  bookmarks
  stub_fzf
  run "$FZX" -m dirs:bookmarks alpha
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --select-1 --exit-0 "* ]]
  run "$FZX" -m dirs:all alpha
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --query=alpha "* && " ${FZF_ARGS[*]} " != *" --select-1 "* ]]
}

@test "preview: the recent module's (git line, path header, listing); ctrl-o opens the files module" {
  git -C "$T/alpha" init -q -b trunk 2> /dev/null
  run bash -c "'$DIRS/preview.sh' '$T/alpha' 2> /dev/null | sed 's/\x1b\[[0-9;]*m//g'"
  [ "${lines[0]}" = "git trunk  0 changes" ]
  stub_fzf
  run "$FZX" -m dirs
  [ "$(fzf_bind ctrl-o)" = "ctrl-o:transform:$FZX _cb nav goto files {1}" ]
}
