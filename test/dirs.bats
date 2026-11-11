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
  FZX_MODE=bookmarks run bash -c "'$DIRS/source.sh' | sed 's/\x1b\[[0-9;:]*m//g'"
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

@test "bookmarks: a header row (FZX_SORTED_SHOW=header) over the name and path, the sorted one marked" {
  bookmarks
  FZX_MODE=bookmarks FZX_SORT=path FZX_SORTED_SHOW=header FZX_SORT_HEADER=1 FZX_SORTED_ARROWS='^ v' run "$DIRS/source.sh"
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == $'\t   NAME  \e[1;38;2;0;215;255mPATH^\e[0m' && "${lines[1]}" != *$'\e[4m'* ]]
  header_aligned 1 "${lines[0]}" PATH "${lines[1]}" /
}

@test "marking: alt-m names a directory, alt-x removes it; the file wins over config, whose own stay" {
  local tty="$BATS_TEST_TMPDIR/tty" file="$FZX_STATE_DIR/dirs/bookmarks"
  export FZX_TTY="$tty" FZX_MODE=bookmarks
  bookmarks
  # the answer typed over the default name; a blank one marks nothing
  printf 'work\n' > "$tty"
  run "$DIRS/actions.sh" mark "$T/beta/deep"
  [ "$status" -eq 0 ]
  [ "$(< "$file")" = "work"$'\t'"$T/beta/deep" ]
  run bash -c "'$DIRS/source.sh' | cut -f1"
  [ "$output" = "$T/alpha"$'\n'"$T/beta"$'\n'"$T/beta/deep" ]
  # the same name moves it, and overrides config's
  printf 'work\n' > "$tty"
  "$DIRS/actions.sh" mark "$T/alpha" > /dev/null
  [ "$(< "$file")" = "work"$'\t'"$T/alpha" ]
  printf 'a\n' > "$tty"
  "$DIRS/actions.sh" mark "$T/beta/deep" > /dev/null
  run bash -c "'$DIRS/source.sh' | cut -f1 | grep -c '^$T/beta/deep\$'"
  [ "$output" = 1 ]
  # unmark: the file's go, by directory; config's stay and say so; a not-a-directory is refused
  run "$DIRS/actions.sh" unmark "$T/beta/deep"
  [ "$status" -eq 0 ]
  [ "$(< "$file")" = "work"$'\t'"$T/alpha" ]
  # alpha is config's too: the file's goes, config's stays and says so
  run "$DIRS/actions.sh" unmark "$T/alpha"
  [ "$status" -eq 1 ]
  [ ! -s "$file" ]
  [[ "$output" == *"a is in FZX_DIRS_BOOKMARKS"* ]]
  run "$DIRS/actions.sh" mark "$T/gone"
  [ "$status" -eq 1 ]
}

@test "marking: a marked directory shows in the menu; the session's old list is dropped" {
  local tty="$BATS_TEST_TMPDIR/tty"
  export FZX_TTY="$tty"
  load_libs log config menu
  fzx::menu_entries dirs "$DIRS"
  run dirs::applicable dirs:bookmarks
  [ "$status" -eq 1 ]
  printf 'here\n' > "$tty"
  "$DIRS/actions.sh" mark "$T/alpha" > /dev/null
  dirs::applicable dirs:bookmarks
  [ "$(dirs::summary dirs:bookmarks)" = "1 bookmark" ]
  local s="$BATS_TEST_TMPDIR/s"
  mkdir -p "$s/data"
  : > "$s/data/bookmarks@name"
  : > "$s/data/all"
  printf 'x\n' > "$tty"
  FZX_SESSION_DIR="$s" "$DIRS/actions.sh" mark "$T/beta" > /dev/null
  [ ! -f "$s/data/bookmarks@name" ] && [ -f "$s/data/all" ]
}

@test "modes: all is the default, bookmarks always there; frecent modes are gone" {
  stub_fzf
  run "$FZX" -m dirs
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = all ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *bookmarks* && " ${FZF_ARGS[*]} " != *frecent* ]]
  [[ "$(fzf_bind alt-m)" == *"_cb action mark {+1}"* ]]
  [[ "$(fzf_bind alt-x)" == *"unmark {+1}"* ]]
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
  run bash -c "'$DIRS/preview.sh' '$T/alpha' 2> /dev/null | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "${lines[0]}" = "git trunk  0 changes" ]
  stub_fzf
  run "$FZX" -m dirs
  [ "$(fzf_bind ctrl-o)" = "ctrl-o:transform:$FZX _cb nav goto files {1}" ]
}
