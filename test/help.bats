#!/usr/bin/env bats
# f1 help: bindings recorded by fzx::bind, printed by a preview command embedded in the f1 binding

load test_helper

setup() {
  setup_fzx
  stub_fzf
}

# run the f1 binding's preview command, as fzf would (bash -c), without colors
help_text() {
  local bind cmd
  bind="$(fzf_bind f1)"
  cmd="${bind#f1:show-preview+preview:}"
  bash -c "$cmd" | sed 's/\x1b\[[0-9;]*m//g'
}

@test "f1 shows the module's keys, then fzx's, then the modes" {
  run "$FZX" -m ps
  run help_text
  [ "${lines[0]}" = "ps keys" ]
  [[ "$output" =~ $'\n'\ \ ctrl-x\ +action:\ send\ SIGTERM ]]
  [[ "$output" =~ $'\n'\ \ ctrl-o\ +open\ the\ children ]]
  [[ "$output" =~ $'\n'\ \ alt-k\ +toggle:\ show\ kernel\ threads ]]
  [[ "$output" == *$'\n'"fzx keys"$'\n'*"  ctrl-r       reload: run the source again"* ]]
  [[ "$output" == *"  alt-left     back to the previous screen"* ]]
  [[ "$output" == *"  f1           this help"* ]]
  [[ "$output" == *$'\nmodes\n  user'*"your processes, busiest first"* ]]
  [[ "$output" == *"  tree"*"process tree"* ]]
}

@test "rebinding a key changes both the binding and the help" {
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_KEYS[help]=f3' > "$FZX_CONFIG_DIR/config.sh"
  mkdir -p "$FZX_CONFIG_DIR/modules/ps"
  echo 'action  term  f5  =  =' > "$FZX_CONFIG_DIR/modules/ps/components.tsv"
  run "$FZX" -m ps
  [[ "$(fzf_bind f5)" == "f5:execute-silent("* ]]
  run fzf_bind f1
  [ "$status" -eq 1 ]
  local bind
  bind="$(fzf_bind f3)"
  run bash -c "${bind#f3:show-preview+preview:}"
  [[ "$output" == *"f5"*"send SIGTERM"* ]]
  [[ "$output" == *"f3"*"this help"* ]]
}

@test "binding one key twice logs a warning" {
  mkdir -p "$FZX_CONFIG_DIR"
  mkdir -p "$FZX_CONFIG_DIR/modules/ps"
  echo 'action  term  ctrl-r  =  =' > "$FZX_CONFIG_DIR/modules/ps/components.tsv"
  run "$FZX" -m ps
  grep -q "key ctrl-r is bound twice (reload: run the source again / action: send SIGTERM to the selected processes)" "$LOG"
}

@test "standalone modules have help too, without session-only keys" {
  run "$BATS_TEST_DIRNAME/../modules/ps/module.sh"
  run help_text
  [ "${lines[0]}" = "ps keys" ]
  [[ "$output" == *"ctrl-x"* && "$output" != *"ctrl-o"* && "$output" != *"alt-left"* ]]
}

@test "a module without modes lists no modes" {
  COUNTER_MODES="" run "$FZX" -m counter
  run help_text
  [[ "$output" != *modes* ]]
}

@test "fzx::bind and key_hints: module scope only in hints" {
  load_libs log session opts
  FZX_OPTS=() FZX_HELP=()
  _FZX_BIND_SCOPE=fzx fzx::bind ctrl-r reload:x "core thing"
  _FZX_BIND_SCOPE=m fzx::bind alt-a 'execute(a)' "do a"
  _FZX_BIND_SCOPE=m fzx::bind alt-b 'execute(b)' "do b"
  [ "${FZX_OPTS[*]}" = "--bind ctrl-r:reload:x --bind alt-a:execute(a) --bind alt-b:execute(b)" ]
  local hints
  fzx::key_hints hints
  [ "$hints" = "alt-a do a  alt-b do b" ]
}
