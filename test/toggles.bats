#!/usr/bin/env bats
# toggles and sort: defaults, session state, cache keys, the toggle/sort callbacks and their keys

load test_helper

setup() {
  setup_fzx
  stub_fzf
  # counter gets toggles and sort keys through the user's override table
  mkdir -p "$FZX_CONFIG_DIR/modules/counter"
  cat > "$FZX_CONFIG_DIR/modules/counter/components.tsv" << 'EOF2'
toggle  hidden  alt-h  show hidden things  -
toggle  big     -      big ones too        on
toggle  slow    alt-s  slow listing        restart
sort    name    -      by name             -
sort    size    f5     by size             default
EOF2
}

# a kept session, attached in the test shell
kept() {
  "$FZX" --keep -m counter "$@"
  SID="$(basename "$(session_dirs)")"
  load_libs log session components
  fzx::session_attach "$SID"
  DIR="$FZX_SESSION_DIR"
}

@test "launch resolves the defaults into state and exports them" {
  STUB_FZF_RUN='echo "$FZX_TOGGLES|$FZX_SORT" > "$BATS_TEST_TMPDIR/env"' run "$FZX" --keep -m counter
  [ "$(< "$BATS_TEST_TMPDIR/env")" = "big|size" ]
  local dir
  dir="$(session_dirs)"
  [ "$(< "$dir/state/toggles")" = big ]
  [ "$(< "$dir/state/sort")" = size ]
}

@test "the source sees toggles and sort; each combination has its own cache" {
  kept
  FZX_SESSION="$SID" "$FZX" _cb load > /dev/null
  [ -f "$DIR/data/one+big@size" ]
  FZX_SESSION="$SID" "$FZX" _cb toggle hidden > /dev/null
  FZX_SESSION="$SID" "$FZX" _cb load > /dev/null
  [ -f "$DIR/data/one+big,hidden@size" ]
  [ "$(< "$COUNTER_FILE")" = 2 ]
  FZX_SESSION="$SID" "$FZX" _cb toggle hidden > /dev/null
  FZX_SESSION="$SID" "$FZX" _cb load > /dev/null
  [ "$(< "$COUNTER_FILE")" = 2 ]
}

@test "toggle flips in place: new footer, reload; unknown toggles fail with 2" {
  kept
  FZX_SESSION="$SID" run "$FZX" _cb toggle big
  [[ "$output" == "change-border-label( counter:one )+change-footer("*")+reload($FZX _cb load)" ]]
  [ "$(< "$DIR/state/toggles")" = "" ]
  FZX_SESSION="$SID" run "$FZX" _cb toggle hidden
  [ "$(< "$DIR/state/toggles")" = hidden ]
  FZX_SESSION="$SID" run "$FZX" _cb toggle nope
  [ "$status" -eq 2 ]
}

@test "a toggle flagged restart restarts fzf" {
  kept
  FZX_SESSION="$SID" FZF_QUERY=q run "$FZX" _cb toggle slow
  [ "$output" = "become:$FZX --resume $SID" ]
  [ "$(< "$DIR/state/toggles")" = "big slow" ]
  [ "$(< "$DIR/state/query")" = q ]
}

@test "sort next/prev wrap, a name selects; unknown names fail with 2" {
  kept
  FZX_SESSION="$SID" "$FZX" _cb sort next > /dev/null
  [ "$(< "$DIR/state/sort")" = name ]
  FZX_SESSION="$SID" "$FZX" _cb sort prev > /dev/null
  [ "$(< "$DIR/state/sort")" = size ]
  FZX_SESSION="$SID" "$FZX" _cb sort name > /dev/null
  [ "$(< "$DIR/state/sort")" = name ]
  FZX_SESSION="$SID" run "$FZX" _cb sort nope
  [ "$status" -eq 2 ]
  [ "$(< "$DIR/state/sort")" = name ]
}

@test "keys: toggle rows with a key, f11/f12 for sort, a sort row's own key" {
  run "$FZX" -m counter
  [ "$(fzf_bind alt-h)" = "alt-h:transform:$FZX _cb toggle hidden" ]
  [ "$(fzf_bind f12)" = "f12:transform:$FZX _cb sort next" ]
  [ "$(fzf_bind f11)" = "f11:transform:$FZX _cb sort prev" ]
  [ "$(fzf_bind f5)" = "f5:transform:$FZX _cb sort size" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --footer="*hidden*big*slow*size* ]]
}

@test "one sort key or none: no f11/f12" {
  echo 'toggle  t  -  a toggle  -' > "$FZX_CONFIG_DIR/modules/counter/components.tsv"
  run "$FZX" -m counter
  run fzf_bind f12
  [ "$status" -eq 1 ]
}

@test "toggle and sort changes are recorded in stats" {
  kept
  FZX_SESSION="$SID" "$FZX" _cb toggle hidden > /dev/null
  FZX_SESSION="$SID" "$FZX" _cb sort next > /dev/null
  run awk -F'\t' '$6 == "toggle" || $6 == "sort" { print $6, $9 }' "$FZX_STATE_DIR/stats.tsv"
  [ "$output" = $'toggle hidden:on\nsort size>name' ]
}

@test "standalone: FZX_TOGGLES and FZX_SORT from the environment, defaults otherwise" {
  local mod
  mod="$(readlink -f "$BATS_TEST_DIRNAME/fixtures/modules/counter")"
  STUB_FZF_RUN='echo "$FZX_TOGGLES|$FZX_SORT" > "$BATS_TEST_TMPDIR/env"' run "$mod/module.sh"
  [ "$(< "$BATS_TEST_TMPDIR/env")" = "big|size" ]
  FZX_TOGGLES="hidden" FZX_SORT=name STUB_FZF_RUN='echo "$FZX_TOGGLES|$FZX_SORT" > "$BATS_TEST_TMPDIR/env"' run "$mod/module.sh"
  [ "$(< "$BATS_TEST_TMPDIR/env")" = "hidden|name" ]
  FZX_SORT=bogus STUB_FZF_RUN='echo "$FZX_SORT" > "$BATS_TEST_TMPDIR/env"' run "$mod/module.sh"
  [ "$(< "$BATS_TEST_TMPDIR/env")" = size ]
}

@test "ps: kernel threads hidden unless toggled; sort by pid ascends" {
  # the plain table: the pid then a space, no color codes
  export NO_COLOR=1
  FZX_MODE=all run "$BATS_TEST_DIRNAME/../modules/ps/source.sh"
  [[ "$output" != *$'\n2 '* ]]
  FZX_MODE=all FZX_TOGGLES=kernel run "$BATS_TEST_DIRNAME/../modules/ps/source.sh"
  [[ "$output" == *$'\n2 '* ]]
  FZX_MODE=all FZX_SORT=pid FZX_TOGGLES=kernel run "$BATS_TEST_DIRNAME/../modules/ps/source.sh"
  [[ "${lines[1]}" =~ ^1\  ]]
}

@test "sort rows scoped by mode: the first that applies starts, other modes have none, another mode's sort is ignored" {
  cat > "$FZX_CONFIG_DIR/modules/counter/components.tsv" << 'EOF2'
sort  size  f5  one: by size        default
sort  name  -   one, two: by name   -
EOF2
  STUB_FZF_RUN='echo "[$FZX_SORT]" > "$BATS_TEST_TMPDIR/env"' run "$FZX" -m counter:two
  [ "$(< "$BATS_TEST_TMPDIR/env")" = "[name]" ]
  STUB_FZF_RUN='echo "[$FZX_SORT]" > "$BATS_TEST_TMPDIR/env"' run "$FZX" -m counter:three
  [ "$(< "$BATS_TEST_TMPDIR/env")" = "[]" ]
  read_fzf_args
  local footer
  footer="$(printf '%s\n' "${FZF_ARGS[@]}" | grep -- '^--footer=')"
  [[ "$footer" == *three* && "$footer" != *name* ]]
  kept
  FZX_SESSION="$SID" "$FZX" _cb mode two > /dev/null
  # size is one's only: f5 does nothing in two, next stays on the one sort two has
  FZX_SESSION="$SID" run "$FZX" _cb sort size
  [ "$status" -eq 0 ]
  FZX_SESSION="$SID" "$FZX" _cb sort next > /dev/null
  [ "$(< "$DIR/state/sort")" = name ]
}

@test "ps: the sorted column is underlined, header too; tree has no sort" {
  FZX_MODE=all FZX_SORT=mem run "$BATS_TEST_DIRNAME/../modules/ps/source.sh"
  [[ "${lines[0]}" == *$'\e[1;38;5;245;4m%MEM\e[0m'* && "${lines[0]}" != *'4m%CPU'* ]]
  [[ "${lines[1]}" =~ $'\e['[0-9\;]+';4m'[0-9.]+$'\e[0m' ]]
  FZX_MODE=tree FZX_SORT= run "$BATS_TEST_DIRNAME/../modules/ps/source.sh"
  [[ "${lines[0]}" != *';4m'* ]]
  load_libs log session components
  fzx::comp_load "$FZX_REPO/modules/ps" ps
  local names=()
  FZX_MODE=tree fzx::comp_sort_names names
  [ "${#names[@]}" -eq 0 ]
  FZX_MODE=user fzx::comp_sort_names names
  [ "${names[*]}" = "cpu mem age pid" ]
}
