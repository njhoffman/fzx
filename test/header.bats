#!/usr/bin/env bats
# header components: styles, footer vs header placement, in-place refresh

load test_helper

setup() {
  setup_fzx
  stub_fzf
  mkdir -p "$FZX_CONFIG_DIR"
}

conf() { printf '%s\n' "$@" > "$FZX_CONFIG_DIR/config.sh"; }

line_for() {
  load_libs log config opts components
  fzx::config_load
  FZX_HEADER_STYLE="$1"
  FZX_COMP=($'toggle\tk\t-\t-\t-')
  FZX_MODES=(a b) FZX_MODE=b FZX_TOGGLES=k FZX_SORT=""
  fzx::component_line LINE
}

@test "bubble: rounded pills, on/off backgrounds from FZX_COLORS" {
  line_for bubble
  [[ "$LINE" == *$'\e[48;5;237;38;5;248ma\e[0m'* ]]
  [[ "$LINE" == *$'\e[48;5;39;38;5;16mb\e[0m'* ]]
  [[ "$LINE" == *$'\e[48;5;39;38;5;16mk\e[0m'* ]]
}

@test "triangle: one powerline with an arrow between items" {
  line_for triangle
  [[ "$LINE" == *$'\e[48;5;237;38;5;248m a \e[38;5;237;48;5;39m'* ]]
  [[ "$LINE" == *$'\e[0m\e[38;5;39m\e[0m' ]]
}

@test "none: no line at all, the mode keys still work" {
  line_for none
  [ -z "$LINE" ]
  conf 'FZX_HEADER_STYLE=none'
  run "$FZX" -m counter
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --footer="* ]]
  [ "$(fzf_bind alt-0)" = "alt-0:transform:$FZX _cb mode next" ]
}

@test "footer by default; header position puts the line above the module's header" {
  run "$FZX" -m counter
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --footer="*one*two*three* ]]
  [[ " ${FZF_ARGS[*]} " == *" --header=mode:one "* ]]
  conf 'FZX_HEADER_POSITION=header'
  "$FZX" --keep -m counter
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --footer="* ]]
  printf '%s\n' "${FZF_ARGS[@]}" | grep -q $'^--header=.*three.*$'
  printf '%s\n' "${FZF_ARGS[@]}" | grep -qx 'mode:one'
  [ "$(< "$(session_dirs)/meta/header")" = "mode:one" ]
}

@test "header position: refreshes fetch the header through the header callback" {
  conf 'FZX_HEADER_POSITION=header'
  "$FZX" --keep -m counter
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" run "$FZX" _cb mode next
  [ "$output" = "change-border-label( counter:two )+transform-header($FZX _cb header)+reload:$FZX _cb load" ]
  FZX_SESSION="$sid" run "$FZX" _cb header
  [[ "${lines[0]}" == *one*two*three* ]]
  [ "${lines[1]}" = "mode:one" ]
}

@test "standalone shows the component line too" {
  run "$(readlink -f "$BATS_TEST_DIRNAME/fixtures/modules/counter")/module.sh"
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --footer="*one*two*three* ]]
}
