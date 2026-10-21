#!/usr/bin/env bats
# prompt icon with a loading state, and FZX_TRACE event logging

load test_helper

setup() {
  setup_fzx
  stub_fzf
  mkdir -p "$FZX_CONFIG_DIR/modules/counter"
}

# config for the counter module (the fixture has no icon of its own)
conf() { printf '%s\n' "$@" > "$FZX_CONFIG_DIR/modules/counter/config.sh"; }

L=$'\e[38;5;240m'
H=$'\e[38;5;45;1m'
R=$'\e[0m'

@test "no icon: fzf's own prompt, no prompt actions" {
  run "$FZX" -m counter
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --prompt="* ]]
  run fzf_bind load
  [ "$status" -eq 1 ]
  [ "$(fzf_bind ctrl-r)" = "ctrl-r:reload($FZX _cb source)" ]
}

@test "icon: starts in the loading form, load switches to the loaded one, reloads switch back" {
  conf 'FZX_ICON=X'
  run "$FZX" -m counter
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --prompt=${L}X$R "* ]]
  [ "$(fzf_bind load)" = "load:change-prompt(${H}X$R )" ]
  [ "$(fzf_bind ctrl-r)" = "ctrl-r:change-prompt(${L}X$R )+reload($FZX _cb source)" ]
}

@test "templates and colors come from config; ')' is dropped; a blank prompt turns it off" {
  conf 'FZX_ICON=X' 'FZX_PROMPT="[{icon}) ok] "' 'FZX_PROMPT_LOADING="... "' 'FZX_COLORS[prompt_loaded]=1'
  run "$FZX" -m counter
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --prompt=... "* ]]
  local b=$'\e[1m'
  [ "$(fzf_bind load)" = "load:change-prompt([${b}X$R ok] )" ]
  conf 'FZX_ICON=' 'FZX_PROMPT="  "'
  run "$FZX" -m counter
  run fzf_bind load
  [ "$status" -eq 1 ]
}

@test "a prompt without an icon works too" {
  conf 'FZX_PROMPT="count> "'
  run "$FZX" -m counter
  [ "$(fzf_bind load)" = "load:change-prompt(count> )" ]
}

@test "in-place refreshes show the loading prompt; the cursor restore no longer uses load" {
  conf 'FZX_ICON=X'
  "$FZX" --keep -m counter
  local dir sid
  dir="$(session_dirs)"
  sid="${dir##*/}"
  FZX_SESSION="$sid" run "$FZX" _cb mode next
  [[ "$output" == *"+change-prompt(${L}X$R )+reload($FZX _cb load)" ]]
  printf '4' > "$dir/state/pos"
  run "$FZX" --resume "$sid"
  [ "$(fzf_bind load)" = "load:change-prompt(${H}X$R )" ]
  [ "$(fzf_bind result-final)" = "result-final:pos(4)+unbind(result-final)" ]
}

@test "the module icons are set" {
  run "$FZX" -m ps
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --prompt="* ]]
}

@test "trace: listed events get a bg-transform first, new events their own binding" {
  FZX_TRACE=start,load,resize run "$FZX" -m counter
  [ "$(fzf_bind start)" = "start:bg-transform($FZX _cb trace start)+reload:$FZX _cb load" ]
  [ "$(fzf_bind resize)" = "resize:bg-transform($FZX _cb trace resize)" ]
  # counter has no prompt, so load had no binding of its own
  [ "$(fzf_bind load)" = "load:bg-transform($FZX _cb trace load)" ]
  run fzf_bind focus
  [ "$status" -eq 1 ]
}

@test "trace: all events, unknown names warned about, nothing standalone" {
  FZX_TRACE=all run "$FZX" -m counter
  [[ "$(fzf_bind focus)" == "focus:bg-transform($FZX _cb trace focus)"* ]]
  [[ "$(fzf_bind result-final)" == "result-final:bg-transform("* ]]
  FZX_TRACE=nope run "$FZX" -m counter
  grep -q "FZX_TRACE: unknown event nope" "$LOG"
  FZX_TRACE=start run "$FZX_REPO/test/fixtures/modules/counter/module.sh"
  [[ "$(fzf_bind start)" != *trace* ]]
}

@test "trace callback: logs the event with fzf's state and prints no action" {
  "$FZX" --keep -m counter
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" FZF_QUERY="a b" FZF_POS=3 FZF_MATCH_COUNT=2 FZF_TOTAL_COUNT=9 FZF_COLUMNS=80 FZF_LINES=24 \
    run "$FZX" _cb trace resize
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q "event resize query='a b' pos=3 matches=2/9 selected= size=80x24" "$LOG"
}
