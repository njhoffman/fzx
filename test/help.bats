#!/usr/bin/env bats
# f1 help: the shortcuts page (fzx keys), from the bindings fzx::bind records and the component rows

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

# one section of the page ("▌ NAME  subtitle" up to the next title), from $output
section() {
  printf '%s\n' "$output" | awk -v t="▌ $1 " 'index($0, t) == 1 { on = 1; next } /^▌ / { on = 0 } on'
}

@test "f1: this screen's keys, then fzx's, then the global ones, the components and the free keys" {
  run "$FZX" -m ps
  run help_text
  local titles
  titles="$(printf '%s\n' "$output" | grep '^▌' | cut -d' ' -f2 | tr '\n' ' ')"
  [ "$titles" = "ps fzx global components free " ]
  run section ps
  [[ "$output" =~ ctrl-x\ +action:\ send\ SIGTERM ]]
  [[ "$output" =~ ctrl-o\ +open\ the\ children ]]
  [[ "$output" =~ alt-k\ +toggle:\ show\ kernel\ threads ]]
  [[ "$output" != *ctrl-r* ]]
}

@test "f1: fzx's keys, with what they take over from fzf; components list names and keys" {
  run "$FZX" -m ps
  run help_text
  local all="$output"
  run section fzx
  [[ "$output" =~ ctrl-r\ +reload:\ run\ the\ source\ again ]]
  [[ "$output" =~ alt-left\ +back\ to\ the\ previous\ screen\ +over\ fzf:\ backward-word ]]
  [[ "$output" =~ f1\ +this\ help ]]
  output="$all"
  run section components
  [[ "$output" == *"modes    user  all  tree"* ]]
  [[ "$output" == *"toggles  kernel [alt-k]"* ]]
  [[ "$output" == *"actions  term [ctrl-x]  kill"* ]]
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
  local all="$output"
  run section ps
  [[ "$output" == *"ctrl-x"* && "$output" != *"ctrl-o"* ]]
  output="$all"
  run section fzx
  [[ "$output" != *"alt-left"* ]]
}

@test "a module without modes lists no modes" {
  COUNTER_MODES="" run "$FZX" -m counter
  run help_text
  run section components
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

@test "f1: global keys are the user's binds, then fzf's defaults; fzx's own win; free keys" {
  printf '%s\n' "# comment --bind 'ctrl-t:nope'" "--bind 'ctrl-t:toggle-all,alt-z:first'" \
    "--bind=\"ctrl-r:change-preview-window(a,b|c)\"" > "$BATS_TEST_TMPDIR/fzfrc"
  FZF_DEFAULT_OPTS_FILE="$BATS_TEST_TMPDIR/fzfrc" FZF_DEFAULT_OPTS="--bind f9:abort" run "$FZX" -m ps
  FZF_DEFAULT_OPTS_FILE="$BATS_TEST_TMPDIR/fzfrc" FZF_DEFAULT_OPTS="--bind f9:abort" run help_text
  local all="$output"
  run section global
  [[ "$output" =~ ctrl-t\ +yours\ +toggle-all ]]
  [[ "$output" =~ alt-z\ +yours\ +first ]]
  [[ "$output" =~ f9\ +yours\ +abort ]]
  [[ "$output" =~ ctrl-a\ +fzf\ +beginning-of-line ]]
  # taken by fzx (ctrl-r) or the module (ctrl-x): not listed as global
  [[ "$output" != *" ctrl-r "* && "$output" != *" ctrl-x "* && "$output" != *nope* && "$output" != *" start "* ]]
  output="$all"
  run section fzx
  [[ "$output" =~ ctrl-r\ +reload:\ run\ the\ source\ again\ +over\ yours:\ change-preview ]]
  output="$all"
  run section free
  local free
  free="$(printf '%s\n' "$output" | grep '^  ctrl  ')"
  [[ " $free " != *" ctrl-t "* && " $free " != *" ctrl-x "* && " $free " != *" ctrl-h "* && " $free " == *" ctrl-v "* ]]
}

@test "fzx keys: synonyms fold into one name; continuation lines and double quotes parse" {
  printf '%s\n' "--bind 'return:accept' \\" "  --bind \"bs:kill-line\"" > "$BATS_TEST_TMPDIR/fzfrc"
  FZF_DEFAULT_OPTS_FILE="$BATS_TEST_TMPDIR/fzfrc" FZF_DEFAULT_OPTS= run "$FZX" keys shift-tab
  output="$(printf '%s' "$output" | sed 's/\x1b\[[0-9;]*m//g')"
  [[ "$output" =~ enter\ +yours\ +accept ]]
  [[ "$output" =~ bspace\ +yours\ +kill-line ]]
  run section fzx
  [[ "$output" == *"btab"* ]]
}
