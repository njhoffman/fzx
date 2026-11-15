#!/usr/bin/env bats
# no shipped module binds a key in FZX_RESERVED_KEYS, in any of its modes: one test per module, so bats
# --jobs runs them beside the rest of the suite (a single test launching every module in every mode took
# 7+ minutes under the parallel suite and held back the results reported after it)

load test_helper

setup() {
  setup_fzx
  stub_fzf
}

# reserved_keys_in <module>: launch it in each mode its resolved table has (executable tables run, as fzx
# runs them) and fail on any reserved-key warning in the log
reserved_keys_in() {
  local m="$1" dir="$FZX_REPO/modules/$1" mode modes
  if [[ -x "$dir/components.tsv" ]]; then
    modes="$(FZX_MODULE_DIR="$dir" FZX_MODULE="$m" "$dir/components.tsv" 2> /dev/null | awk -F'\t' '$1 == "mode" { print $2 }')"
  else
    modes="$(awk '$1 == "mode" { print $2 }' "$dir/components.tsv" 2> /dev/null)"
  fi
  for mode in ${modes:-""}; do
    run "$FZX" -m "$m${mode:+:$mode}"
  done
  run grep "is reserved (FZX_RESERVED_KEYS)" "$LOG"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

for _dir in "$BATS_TEST_DIRNAME"/../modules/*/; do
  _m="$(basename "$_dir")"
  # the actions menu is a child screen of another module's, launched only from one
  [[ "$_m" == actions ]] && continue
  bats_test_function --description "no reserved key bound by $_m in any of its modes" -- reserved_keys_in "$_m"
done
unset _dir _m
