#!/usr/bin/env bats
# lib/components.sh: components.tsv tables, user overrides, executable tables, modes from rows

load test_helper

setup() {
  setup_fzx
  load_libs log session config components
  MOD="$BATS_TEST_TMPDIR/mods/m"
  mkdir -p "$MOD" "$FZX_CONFIG_DIR/modules/m"
  FZX_MODULE=m FZX_MODULE_DIR="$MOD"
}

table() { printf '%s\n' "$@" > "$MOD/components.tsv"; }

# comp_load without the built-in rows (config/components.tsv), which every module gets
load_own() {
  local r rows=()
  fzx::comp_load "$MOD" m
  for r in "${FZX_COMP[@]}"; do [[ ",${r##*$'\t'}," == *,builtin,* ]] || rows+=("$r"); done
  FZX_COMP=("${rows[@]}")
}

@test "rows split on tabs or on runs of two or more spaces; comments and blanks skipped" {
  table '# kind name key description flags' '' $'mode\tone\tf3\tthe first mode\tdefault' 'mode  two  -  the second one, with spaces  restart' 'toggle  t  alt-t  a toggle'
  load_own
  [ "${#FZX_COMP[@]}" -eq 3 ]
  [ "${FZX_COMP[0]}" = $'mode\tone\tf3\tthe first mode\tdefault' ]
  [ "${FZX_COMP[1]}" = $'mode\ttwo\t-\tthe second one, with spaces\trestart' ]
  [ "${FZX_COMP[2]}" = $'toggle\tt\talt-t\ta toggle\t-' ]
  [ "${FZX_MODES[*]}" = "one two" ]
}

@test "bad rows are reported and skipped" {
  table 'mode  ok' 'bogus  x' 'mode  bad name!'
  run fzx::comp_load "$MOD" m
  [[ "$output" == *"bad component row: bogus  x"* && "$output" == *"bad name!"* ]]
  load_own 2> /dev/null
  [ "${#FZX_COMP[@]}" -eq 1 ]
}

@test "the default flag picks the starting mode; no mode rows means the single mode main" {
  table 'mode  a' 'mode  b  -  -  default'
  fzx::comp_load "$MOD" m
  [ "$FZX_MODE_DEFAULT" = b ]
  table 'toggle  t'
  fzx::comp_load "$MOD" m
  [ "${FZX_MODES[*]}" = main ] && [ "$FZX_MODE_DEFAULT" = main ]
  rm "$MOD/components.tsv"
  fzx::comp_load "$MOD" m
  [ "${FZX_MODES[*]}" = main ]
}

@test "hidden modes are left out of the cycle and the default, but still exist" {
  table 'mode  drill  -  a drill-down  hidden' 'mode  one' 'mode  two  -  -  default'
  load_own
  [ "${FZX_MODES[*]}" = "one two" ]
  [ "${FZX_MODES_HIDDEN[*]}" = drill ]
  [ "$FZX_MODE_DEFAULT" = two ]
}

@test "mode_desc: a scoped description's part for the mode; unknown names or no mode return it whole" {
  load_libs components
  local d='status: stage the files; log, reflog: cherry-pick (oldest: first)' out
  fzx::mode_desc "$d" reflog out status log reflog
  [ "$out" = "cherry-pick (oldest: first)" ]
  fzx::mode_desc "$d" status out status log reflog
  [ "$out" = "stage the files" ]
  ! fzx::mode_desc "$d" stash out status log reflog stash
  fzx::mode_desc "$d" "" out status log reflog
  [ "$out" = "$d" ]
  fzx::mode_desc "note: plain text" log out status log
  [ "$out" = "note: plain text" ]
  fzx::mode_desc "status: x; and some prose" log out status log
  [ "$out" = "status: x; and some prose" ]
}

@test "user rows replace by kind+name; '=' keeps a field, 'off' removes, new names are added" {
  table 'mode  a  f3  first  default' 'mode  b  -  second' 'action  x  ctrl-x  do x  silent'
  printf '%s\n' 'mode  a  f5  =  =' 'mode  b  =  =  off' 'action  y  alt-y  do y  foreground' > "$FZX_CONFIG_DIR/modules/m/components.tsv"
  load_own
  [ "${FZX_COMP[*]}" = $'mode\ta\tf5\tfirst\tdefault action\tx\tctrl-x\tdo x\tsilent action\ty\talt-y\tdo y\tforeground' ]
  [ "${FZX_MODES[*]}" = a ]
}

@test "an executable table is run, with the module's dir and name in its environment" {
  printf '#!/usr/bin/env bash\nprintf "mode\\t%%s\\t-\\t%%s\\t-\\n" "$FZX_MODULE" "$FZX_MODULE_DIR"\n' > "$MOD/components.tsv"
  chmod +x "$MOD/components.tsv"
  fzx::comp_load "$MOD" m
  [ "${FZX_COMP[0]}" = "mode	m	-	$MOD	-" ]
}

@test "comp_field and comp_flag" {
  table 'mode  a  f3  first  default,restart'
  fzx::comp_load "$MOD" m
  local key
  fzx::comp_field mode a key key
  [ "$key" = f3 ]
  fzx::comp_flag mode a restart
  run fzx::comp_flag mode a nope
  [ "$status" -eq 1 ]
  run fzx::comp_field mode zz key key
  [ "$status" -eq 1 ]
}

@test "the resolved table is stored in the session and read back by callbacks" {
  stub_fzf
  "$FZX" --keep -m ps
  local dir
  dir="$(session_dirs)"
  run cat "$dir/meta/components"
  [[ "${lines[0]}" == $'mode\tuser\t-\t'* ]]
  [[ "${lines[2]}" == *$'\trestart' ]]
}

@test "a mode row with a key gets a binding straight to that mode" {
  stub_fzf
  mkdir -p "$FZX_CONFIG_DIR/modules/ps"
  echo 'mode  all  f5  =  =' > "$FZX_CONFIG_DIR/modules/ps/components.tsv"
  run "$FZX" -m ps
  [ "$(fzf_bind f5)" = "f5:transform:$FZX _cb mode all" ]
}
