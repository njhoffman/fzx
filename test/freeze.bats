#!/usr/bin/env bats
# --freeze-left: the option, and the display field split where the frozen part ends (fzx::freeze_rows)

load test_helper

setup() {
  setup_fzx
  export FZX_FREEZE_LEFT=1 FZX_REPO
  M="$BATS_TEST_TMPDIR/mods/wide"
  mkdir -p "$M"
  cat > "$M/module.sh" << 'EOF2'
#!/usr/bin/env bash
FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
source "$FZX_MODULE_DIR/source.sh"
wide::opts() { FZX_OPTS+=(--delimiter=$'\t' --with-nth=2 --accept-nth=1); }
fzx::module_main "$@"
EOF2
  cat > "$M/source.sh" << 'EOF2'
#!/usr/bin/env bash
wide::source() { printf 'a\tname    the rest\textra\n'; printf 'b\tother   more of it\textra\n'; }
[[ "${BASH_SOURCE[0]}" == "$0" ]] && wide::source
EOF2
  chmod +x "$M/module.sh" "$M/source.sh"
  export FZX_MODULE_PATH="$BATS_TEST_TMPDIR/mods:$FZX_MODULE_PATH"
}

# rows <spec> <k>: stdin through fzx::freeze_rows
rows() {
  load_libs log session callback 2> /dev/null || :
  FZX_SESSION_DIR="$BATS_TEST_TMPDIR/s"
  mkdir -p "$FZX_SESSION_DIR/meta"
  printf '%s' "$2" > "$FZX_SESSION_DIR/meta/freeze"
  declare -gA FZX_FREEZE_COLS=()
  FZX_MODE=m FZX_FREEZE_COL="$1" fzx::freeze_rows
}

@test "the cut: at the first gap, the second, a word, a column; the rest goes last, no other field moves" {
  [ "$(rows gap 2 <<< $'i\tname    the rest\tx')" = $'i\tname   \tx\tthe rest' ]
  [ "$(rows gap2 2 <<< $'i\tG  nf-x    tail\tx')" = $'i\tG  nf-x   \tx\ttail' ]
  [ "$(rows word 2 <<< $'i\ticon dir/name\tx')" = $'i\ticon\tx\tdir/name' ]
  [ "$(rows 5 2 <<< $'i\t0123 5 7 9')" = $'i\t0123 5\t7 9' ]
  # a name past the column: the next space
  [ "$(rows 2 2 <<< $'i\tlongname rest')" = $'i\tlongname\trest' ]
  # nowhere to cut, or told not to: all of it stays, with an empty last field
  [ "$(rows gap 2 <<< $'i\tname rest')" = $'i\tname rest\t' ]
  [ "$(rows none 2 <<< $'i\ta  b')" = $'i\ta  b\t' ]
}

@test "the cut: colors are not columns and stay with their text; leading spaces are not a gap" {
  [ "$(rows gap 2 <<< $'i\t\e[32mname\e[0m    rest')" = $'i\t\e[32mname\e[0m   \trest' ]
  [ "$(rows 4 2 <<< $'i\t\e[1m\e[32mab\e[0m\e[2mcd\e[0m ef')" = $'i\t\e[1m\e[32mab\e[0m\e[2mcd\e[0m\tef' ]
  [ "$(rows gap 2 <<< $'i\t   12  path')" = $'i\t   12 \tpath' ]
}

@test "the cut: a row short of the field, an empty header id, unicode before a column" {
  [ "$(rows gap 3 <<< 'only')" = $'only\t\t\t' ]
  [ "$(rows gap 2 <<< $'\tNAME    VALUE')" = $'\tNAME   \tVALUE' ]
  [ "$(rows 3 2 <<< $'i\t\xe2\x97\x8f ab cd')" = $'i\t\xe2\x97\x8f ab\tcd' ]
  # with no split recorded, rows pass as they are
  [ "$(rows gap "" <<< $'i\ta  b')" = $'i\ta  b' ]
}

@test "options: the default freezes one field; the display is split under a session; 0 leaves all alone" {
  stub_fzf
  run "$FZX" -m wide
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --with-nth=2,-1 "* && " ${FZF_ARGS[*]} " == *" --freeze-left=1 "* && " ${FZF_ARGS[*]} " == *" --tabstop=1 "* ]]
  FZX_FREEZE_LEFT=2 run "$FZX" -m wide
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --freeze-left=2 "* ]]
  FZX_FREEZE_LEFT=0 run "$FZX" -m wide
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --with-nth=2 "* && " ${FZF_ARGS[*]} " != *" --freeze-left="* ]]
  # a module's own number stays
  sed -i 's/--accept-nth=1)/--accept-nth=1 --freeze-left=3)/' "$M/module.sh"
  run "$FZX" -m wide
  read_fzf_args
  [ "$(printf '%s\n' "${FZF_ARGS[@]}" | grep -c -- '^--freeze-left=')" -eq 1 ]
  [[ " ${FZF_ARGS[*]} " == *" --freeze-left=3 "* ]]
}

@test "options: the menu searches both parts; ps and history keep their fields; run directly nothing splits" {
  stub_fzf
  run "$FZX"
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --with-nth=2,-1,3 "* && " ${FZF_ARGS[*]} " == *" --nth=1,2 "* ]]
  run "$FZX" -m ps
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --freeze-left=1 "* && " ${FZF_ARGS[*]} " != *" --with-nth="* ]]
  FZX_HISTDB_FILE=/dev/null run "$FZX" -m history
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --with-nth=2.. "* ]]
  FZX_ROOT="$FZX_REPO" run "$M/module.sh"
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --with-nth=2 "* && " ${FZF_ARGS[*]} " == *" --freeze-left=1 "* ]]
}

@test "under fzx: the load is split and cached apart; copy-line gets the line as it shows" {
  stub_fzf
  "$FZX" --keep -m wide
  local sid dir
  dir="$(session_dirs)"
  sid="${dir##*/}"
  [ "$(< "$dir/meta/freeze")" = 2 ]
  run env FZX_SESSION="$sid" "$FZX" _cb load
  [ "${lines[0]}" = $'a\tname   \textra\tthe rest' ]
  [ "${lines[1]}" = $'b\tother  \textra\tmore of it' ]
  [ -f "$dir/data/main~2" ]
  # from the cache, the same
  run env FZX_SESSION="$sid" "$FZX" _cb load
  [ "${lines[0]}" = $'a\tname   \textra\tthe rest' ]
  load_libs log session builtin
  fzx::clip() { cat > "$BATS_TEST_TMPDIR/clip"; }
  FZX_SESSION_DIR="$dir" fzx::builtin copy-line $'a\tname   \textra\tthe rest'
  [ "$(< "$BATS_TEST_TMPDIR/clip")" = "name    the rest" ]
}

@test "files, dirs and recent keep the end of a path in view; grep shows its start" {
  stub_fzf
  mkdir -p "$BATS_TEST_TMPDIR/d"
  cd "$BATS_TEST_TMPDIR/d"
  run "$FZX" -m files
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --keep-right "* ]]
  run "$FZX" -m files:grep
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --keep-right "* && " ${FZF_ARGS[*]} " == *" --with-nth=3,-1 "* ]]
}
