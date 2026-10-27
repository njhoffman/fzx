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
  cmd="$(bash -c "${bind#f1:transform:}")"
  cmd="${cmd#show-preview+preview:}"
  bash -c "$cmd" | sed 's/\x1b\[[0-9;]*m//g'
}

# one section of the page ("▌ NAME  subtitle" up to the next title), from $output
section() {
  printf '%s\n' "$output" | awk -v t="▌ $1 " 'index($0, t) == 1 { on = 1; next } /^▌ / { on = 0 } on'
}

@test "f1: the components, this screen's keys, then fzx's, the global ones and the free keys" {
  run "$FZX" -m ps
  run help_text
  local titles
  titles="$(printf '%s\n' "$output" | grep '^▌' | cut -d' ' -f2 | tr '\n' ' ')"
  [ "$titles" = "components ps fzx global free " ]
  # the version opens the page
  [ "${lines[0]}" = "fzx $(< "$FZX_REPO/VERSION")" ]
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
  local bind cmd
  bind="$(fzf_bind f3)"
  cmd="$(bash -c "${bind#f3:transform:}")"
  run bash -c "${cmd#show-preview+preview:}"
  [[ "$output" == *"f5"*"send SIGTERM"* ]]
  [[ "$output" == *"f3"*"this help"* ]]
}

@test "several keys per action: a binding per key, each in f1, checked and reserved one by one" {
  mkdir -p "$FZX_CONFIG_DIR/modules/ps"
  echo 'FZX_KEYS[back]="alt-left,ctrl-bspace"' > "$FZX_CONFIG_DIR/config.sh"
  # ctrl-f is reserved for modules: the action keeps its other key
  echo 'action  term  f5,ctrl-f  =  =' > "$FZX_CONFIG_DIR/modules/ps/components.tsv"
  run "$FZX" -m ps
  [ "$(fzf_bind alt-left)" = "alt-left:transform:$FZX _cb nav back" ]
  [ "$(fzf_bind ctrl-bspace)" = "ctrl-bspace:transform:$FZX _cb nav back" ]
  [[ "$(fzf_bind f5)" == "f5:execute-silent("* ]]
  run fzf_bind ctrl-f
  [ "$status" -eq 1 ]
  grep -q "key ctrl-f is reserved" "$LOG"
  run help_text
  run section fzx
  [[ "$output" =~ alt-left\ +back\ to ]] && [[ "$output" =~ ctrl-bspace\ +back\ to ]]
  # the comma key is a key, not a separator
  load_libs log
  local ks=()
  fzx::split_keys "alt-.,alt-," ks
  [ "${#ks[@]}" -eq 2 ] && [ "${ks[1]}" = "alt-," ]
  # each key of a list is taken, not free
  echo 'FZX_KEYS[back]="alt-left,alt-q"' > "$FZX_CONFIG_DIR/config.sh"
  run "$FZX" -m ps
  run help_text
  run section free
  [[ "$output" == *alt-p* && "$output" != *alt-q* ]]
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

@test "f1 again: the grid; a third time the list; FZF_ACTION tells them apart" {
  run "$FZX" -m ps
  local bind
  bind="$(fzf_bind f1)"
  [[ "$bind" == "f1:transform:$FZX keys --toggle s:full m:ps "* ]]
  run bash -c "${bind#f1:transform:}"
  [[ "$output" == "show-preview+preview:$FZX keys s:full m:ps "* && "$output" != *l:grid* ]]
  FZF_ACTION=show-preview run bash -c "${bind#f1:transform:}"
  [[ "$output" == "ignore+preview:$FZX keys s:full m:ps "*" l:grid " ]]
  run bash -c "${output#ignore+preview:} | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "$output" == *"▌ keys  by modifier"* && "$output" != *"▌ free"* ]]
  [[ "$output" =~ ctrl-\ +a\ b\ c\ d\ e\ f\ g\ j ]]
  [[ "$output" =~ alt-shift-\ +A\ B ]]
  FZF_ACTION=ignore run bash -c "${bind#f1:transform:}"
  [[ "$output" == show-preview+preview:* ]]
}

@test "grid: each key in the color of who binds it, free ones dim" {
  run "$FZX" keys m:ps k:$'ps\tctrl-x\tterm' k:$'fzx\talt-left\tback' l:grid
  [[ "$output" == *$'\e[1;38;5;45mx\e[0m'* ]]
  [[ "$output" == *$'\e[1;38;5;213mleft\e[0m'* ]]
  [[ "$output" == *$'\e[38;5;238mz\e[0m'* ]]
}

@test "key style: full, short or glyph in the page, components and free keys; FZX_KEY_STYLE reaches f1" {
  load_libs keys
  local l
  fzx::key_label ctrl-x l short && [ "$l" = "^X" ]
  fzx::key_label 'ctrl-\' l short && [ "$l" = '^\' ]
  fzx::key_label alt-left l short && [ "$l" = "M-left" ]
  fzx::key_label ctrl-alt-up l short && [ "$l" = "C-M-up" ]
  fzx::key_label shift-tab l short && [ "$l" = "S-tab" ]
  fzx::key_label alt-X l short && [ "$l" = "M-X" ]
  fzx::key_label ctrl-x l glyph && [ "$l" = "⌃X" ]
  fzx::key_label alt-left l glyph && [ "$l" = "⌥←" ]
  fzx::key_label alt-X l glyph && [ "$l" = "⌥⇧X" ]
  fzx::key_label alt-bs l glyph && [ "$l" = "⌥⌫" ]
  fzx::key_label f5 l glyph && [ "$l" = "F5" ]
  fzx::key_label alt-left l full && [ "$l" = "alt-left" ]
  run bash -c "'$FZX' keys s:glyph m:ps k:\$'ps\tctrl-x\tterm' c:\$'action\tterm\tctrl-x,f5\tkill' | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "$output" == *"term [⌃X,F5]"* ]]
  [[ "$output" =~ ⌃X\ +term ]]
  [[ "$(printf '%s\n' "$output" | sed -n '/^▌ free/,$p')" =~ ⌃[A-Z] ]]
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_KEY_STYLE=short' > "$FZX_CONFIG_DIR/config.sh"
  run "$FZX" -m ps
  [[ "$(fzf_bind f1)" == "f1:transform:$FZX keys --toggle s:short "* ]]
  run help_text
  [[ "$output" =~ \^R\ +reload ]]
}

