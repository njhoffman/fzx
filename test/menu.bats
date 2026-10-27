#!/usr/bin/env bats
# step 5: manifests, the menu module, cached summaries and opening entries

load test_helper

bats_require_minimum_version 1.5.0

MENU_DIR="$(readlink -f "$BATS_TEST_DIRNAME/../modules/menu")"

setup() {
  setup_fzx
  load_libs log session menu
}

# a root menu session attached in the test shell
menu_session() {
  fzx::session_create menu "$MENU_DIR"
}

# summaries from the fixture modules only: the real ones run real tools (zoxide can block for half a
# minute on an unreachable mount), which these tests must not depend on
fixture_modules() {
  export FZX_MODULE_PATH="$BATS_TEST_DIRNAME/fixtures/modules"
}

# menu lines without colors, as "id|display"
plain_lines() {
  "$FZX" _cb source | sed 's/\x1b\[[0-9;]*m//g; s/\t/|/'
}

# entry <id>: the plain line of one entry (real modules list alongside the fixtures, in name order)
entry() {
  printf '%s\n' "${lines[@]}" | grep -m1 -F "$1|"
}

@test "fzx::entry: stores args quoted, no args as empty" {
  FZX_ENTRY_TARGETS=() FZX_ENTRY_DESCS=() FZX_ENTRY_ARGS=()
  fzx::entry a "first"
  fzx::entry b:m "second" --x "a b" ""
  [ "${FZX_ENTRY_ARGS[0]}" = "" ]
  fzx::menu_entry_args 0
  [ "${#FZX_ARGS[@]}" -eq 0 ]
  fzx::menu_entry_args 1
  [ "${#FZX_ARGS[@]}" -eq 3 ]
  [ "${FZX_ARGS[1]}" = "a b" ] && [ "${FZX_ARGS[2]}" = "" ]
}

@test "menu_modules: modules with a manifest, first path wins, menu excluded" {
  mkdir -p "$BATS_TEST_TMPDIR/mods/ps" "$BATS_TEST_TMPDIR/mods/nomanifest"
  touch "$BATS_TEST_TMPDIR/mods/ps/manifest.sh" "$BATS_TEST_TMPDIR/mods/nomanifest/module.sh"
  FZX_MODULE_PATH="$BATS_TEST_TMPDIR/mods:$FZX_MODULE_PATH"
  run fzx::menu_modules
  [[ "$output" == *"$(printf 'counter\t%s' "$BATS_TEST_DIRNAME/fixtures/modules/counter")"* ]]
  [[ "$output" == *"$(printf 'ps\t%s' "$BATS_TEST_TMPDIR/mods/ps")"* ]]
  [ "$(printf '%s\n' "${lines[@]}" | grep -c '^ps')" -eq 1 ]
  [[ "$output" != *nomanifest* && "$output" != *$'\n'menu$'\t'* ]]
}

@test "source: one line per applicable entry with a stable id" {
  menu_session
  run plain_lines
  # the module's icon first (blank: the fixture sets none)
  [[ "$(entry 'counter#0')" == "counter#0|  counter "*"Counter in its first mode"* ]]
  [[ "$(entry 'counter#1')" == 'counter#1|  counter:two --x a\ b '*"Counter in mode two"* ]]
  [[ "$output" == *$'\n'"ps#0|"?" ps "* ]]
}

@test "source: a mode's own icon and color, else the module's, else the target color" {
  mkdir -p "$BATS_TEST_TMPDIR/mods/iconed"
  cat > "$BATS_TEST_TMPDIR/mods/iconed/config.sh" << 'EOF'
FZX_ICON="M"
FZX_ICON_MODES[grep]="G"
FZX_COLORS[iconed_icon]="38;5;75"
FZX_COLORS[iconed_icon_grep]="38;5;170"
EOF
  cat > "$BATS_TEST_TMPDIR/mods/iconed/manifest.sh" << 'EOF'
iconed::manifest() {
  fzx::entry iconed "default mode"
  fzx::entry iconed:grep "grep mode"
  fzx::entry iconed:dirs "a mode without its own icon"
}
EOF
  export FZX_MODULE_PATH="$BATS_TEST_TMPDIR/mods:$FZX_MODULE_PATH"
  menu_session
  run "$FZX" _cb source
  [[ "$output" == *$'iconed#0\t\e[38;5;75mM\e[0m '* ]]
  [[ "$output" == *$'iconed#1\t\e[38;5;170mG\e[0m '* ]]
  [[ "$output" == *$'iconed#2\t\e[38;5;75mM\e[0m '* ]]
  # the next module starts from the defaults: no icon, the target color
  [[ "$output" == *$'counter#1\t\e[38;5;110m \e[0m '* ]]
  FZX_ICONS=unicode run plain_lines
  [[ "$(entry 'iconed#1')" == 'iconed#1|iconed:grep '* ]]
}

@test "source: applicable hides an entry without renumbering the others" {
  menu_session
  COUNTER_HIDE_TWO=1 run plain_lines
  [ -n "$(entry 'counter#0')" ]
  [[ "$output" != *counter#1* ]]
  [[ "$output" == *$'\n'ps#0* ]]
}

@test "source: a broken manifest drops only its module" {
  mkdir -p "$BATS_TEST_TMPDIR/mods/broken"
  printf 'broken::manifest() { return 1; }\n' > "$BATS_TEST_TMPDIR/mods/broken/manifest.sh"
  mkdir -p "$BATS_TEST_TMPDIR/mods/syntax"
  printf 'syntax::manifest() { (( ; }\n' > "$BATS_TEST_TMPDIR/mods/syntax/manifest.sh"
  export FZX_MODULE_PATH="$BATS_TEST_TMPDIR/mods:$FZX_MODULE_PATH"
  menu_session
  run plain_lines
  [[ "$output" != *broken* && "$output" != *syntax* ]]
  [ -n "$(entry 'counter#0')" ]
  grep -q 'menu: manifest of syntax failed' "$LOG"
}

@test "refresh: writes stale summaries, asks for one reload, then is quiet" {
  fixture_modules
  menu_session
  run "$FZX" _cb transform refresh
  [ "$output" = "reload:$FZX _cb source" ]
  run plain_lines
  [[ "${lines[0]}" == *"summary of counter" ]]
  [[ "${lines[1]}" == *"summary of counter:two --x a b" ]]
  run "$FZX" _cb transform refresh
  [ -z "$output" ]
  [ "$(wc -l < "$COUNTER_FILE.summaries")" -eq 2 ]
}

@test "refresh: summaries older than FZX_SUMMARY_TTL are recomputed" {
  fixture_modules
  menu_session
  "$FZX" _cb transform refresh > /dev/null
  find "$FZX_CACHE_DIR/summary" -name 'counter@*' | head -1 | xargs touch -d '10 minutes ago'
  run "$FZX" _cb transform refresh
  [ "$output" = "reload:$FZX _cb source" ]
  [ "$(wc -l < "$COUNTER_FILE.summaries")" -eq 3 ]
}

@test "summary cache: keyed by what the entry opens, not its position in the manifest" {
  load_libs menu
  local a b c
  FZX_ENTRY_TARGETS=(x:one x:two) FZX_ENTRY_ARGS=("" "")
  fzx::summary_path a x 1
  # x:one dropped from the manifest: x:two is now entry 0 and keeps its summary
  FZX_ENTRY_TARGETS=(x:two) FZX_ENTRY_ARGS=("")
  fzx::summary_path b x 0
  [ "$a" = "$b" ]
  # the same target with other args is another entry
  FZX_ENTRY_ARGS=("--y")
  fzx::summary_path c x 0
  [ "$c" != "$b" ]
}

@test "refresh: summaries are per directory" {
  fixture_modules
  menu_session
  "$FZX" _cb transform refresh > /dev/null
  cd "$BATS_TEST_TMPDIR"
  run "$FZX" _cb transform refresh
  [ "$output" = "reload:$FZX _cb source" ]
  [ "$(wc -l < "$COUNTER_FILE.summaries")" -eq 4 ]
}

@test "refresh: entries that do not apply are not summarized" {
  fixture_modules
  menu_session
  COUNTER_HIDE_TWO=1 "$FZX" _cb transform refresh > /dev/null
  [ "$(< "$COUNTER_FILE.summaries")" = counter ]
}

@test "refresh: a slow summary is cut off at FZX_SUMMARY_TIMEOUT and cached empty" {
  fixture_modules
  menu_session
  local start=$EPOCHSECONDS
  COUNTER_SUMMARY_SLEEP=10 FZX_SUMMARY_TIMEOUT=1 run "$FZX" _cb transform refresh
  ((EPOCHSECONDS - start < 5))
  [ "$output" = "reload:$FZX _cb source" ]
  grep -q 'summary of counter#0 failed or timed out' "$LOG"
  run "$FZX" _cb transform refresh
  [ -z "$output" ]
}

@test "refresh: a failing summary is cached empty and not retried within the ttl" {
  fixture_modules
  menu_session
  COUNTER_SUMMARY_FAIL=1 "$FZX" _cb transform refresh > /dev/null
  COUNTER_SUMMARY_FAIL=1 "$FZX" _cb transform refresh > /dev/null
  [ "$(wc -l < "$COUNTER_FILE.summaries")" -eq 2 ]
  run plain_lines
  [[ "${lines[0]}" =~ Counter\ in\ its\ first\ mode\ *$ ]]
}

@test "transform: unknown name fails with 2" {
  menu_session
  run "$FZX" _cb transform bogus
  [ "$status" -eq 2 ]
}

@test "nav entry: opens the entry as a child with its mode and args" {
  menu_session
  local menu="$FZX_SESSION"
  run "$FZX" _cb nav entry counter#1
  [[ "$output" == "become:$FZX --resume "*" -m :two" ]]
  local child="${output% -m*}"
  child="${child##* }"
  [ "$(< "$FZX_RUNTIME_DIR/sessions/$child/meta/parent")" = "$menu" ]
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${#args[@]}" -eq 2 ] && [ "${args[1]}" = "a b" ]
}

@test "nav entry: entries of the same module and args share one child" {
  menu_session
  run "$FZX" _cb nav entry ps#0
  local first="${output##* }"
  run "$FZX" _cb nav entry ps#2
  [[ "$output" == *" $first -m :tree" ]]
}

@test "nav entry: malformed, unknown and out-of-range ids fail with 2" {
  menu_session
  local id
  for id in "" counter counter#x nope#0 counter#9; do
    run "$FZX" _cb nav entry "$id"
    [ "$status" -eq 2 ]
  done
}

@test "action-returning callbacks log what they print" {
  menu_session
  "$FZX" _cb nav entry counter#0 > /dev/null
  grep -q "actions: become:$FZX --resume " "$LOG"
}

@test "preview: the entry, its summary, the module's modes (the entry's marked) and the command it runs" {
  menu_session
  "$FZX" _cb transform refresh > /dev/null
  run "$FZX" _cb preview counter#1
  output="$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g')"
  mapfile -t lines <<< "$output"
  [[ "${lines[0]}" == *"counter:two" ]]
  [ "${lines[1]}" = "Counter in mode two" ]
  [ "${lines[2]}" = "summary of counter:two --x a b" ]
  [[ "$output" == *"▌ modes"* ]]
  [[ "$output" =~ ▸\ +two\ +counter\ mode\ two ]]
  [[ "$output" =~ $'\n'\ +one\ +counter\ mode\ one ]]
  [[ "$output" == *"fzx -m counter:two --x a\\ b"* ]]
  run "$FZX" _cb preview nope#0
  [ "$status" -eq 1 ]
}

@test "fzx without arguments opens the menu" {
  stub_fzf
  run "$FZX"
  [ "$status" -eq 0 ]
  local sid
  sid="$(< "$BATS_TEST_TMPDIR/fzf.session")"
  [ -n "$sid" ]
  [ "$(fzf_bind enter)" = "enter:transform:$FZX _cb nav entry {1}" ]
  [ "$(fzf_bind start)" = "start:reload:$FZX _cb load" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" start:+bg-transform:$FZX _cb transform refresh "* ]]
  [[ " ${FZF_ARGS[*]} " == *" --border-label= menu:main "* ]]
}

@test "the menu run directly lists entries but cannot open them" {
  stub_fzf
  run "$MENU_DIR/module.sh"
  [ "$status" -eq 0 ]
  [ "$(fzf_bind start)" = "start:reload:$MENU_DIR/source.sh" ]
  run fzf_bind enter
  [ "$status" -eq 1 ]
  run "$MENU_DIR/source.sh"
  [[ "$output" == *counter#0$'\t'* ]]
}
