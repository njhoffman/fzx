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

# menu entry lines without colors, as "id|display" (group headers and the empty header field left out)
plain_lines() {
  "$FZX" _cb source | sed 's/\x1b\[[0-9;:]*m//g; /^@/d; s/\t[^\t]*\t[^\t]*$//; s/\t/|/'
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

@test "source: modules are listed at once; one over FZX_APPLICABLE_TIMEOUT is left out and logged" {
  mkdir -p "$BATS_TEST_TMPDIR/mods/aaslow" "$BATS_TEST_TMPDIR/mods/zslow"
  cat > "$BATS_TEST_TMPDIR/mods/aaslow/manifest.sh" << 'EOF2'
aaslow::manifest() { fzx::entry aaslow "slow but in time"; }
aaslow::applicable() { sleep 0.4; }
EOF2
  cat > "$BATS_TEST_TMPDIR/mods/zslow/manifest.sh" << 'EOF2'
zslow::manifest() { fzx::entry zslow "too slow"; }
zslow::applicable() { sleep 60; }
EOF2
  # margins for the parallel suite, where every module's manifest is read at once on a loaded machine
  export FZX_MODULE_PATH="$BATS_TEST_TMPDIR/mods:$FZX_MODULE_PATH" FZX_APPLICABLE_TIMEOUT=6
  menu_session
  fzx::state_set mode list
  local start=$EPOCHSECONDS
  run plain_lines
  ((EPOCHSECONDS - start < 12))
  # in module order, the slow one in time included
  [[ "${lines[0]}" == "aaslow#0|"* ]]
  [ -n "$(entry 'counter#0')" ]
  [[ "$output" != *zslow* ]]
  grep -q 'menu: zslow took over 6s, left out' "$LOG"
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

@test "summary cache: a module's summary_key adds to the key, asked once per module and listing" {
  load_libs menu
  local a b c d e
  FZX_ENTRY_TARGETS=(x:one x:two) FZX_ENTRY_ARGS=("" "")
  fzx::summary_path a x 0
  x::summary_key() { printf '%s\n' "$KEYV"; printf 'x\n' >> "$BATS_TEST_TMPDIR/asked"; }
  KEYV=1 fzx::summary_path b x 0
  KEYV=1 fzx::summary_path c x 1
  [ "$a" != "$b" ] && [ "$b" != "$c" ]
  # the other entry, and a changed key, reuse what the first entry asked: one listing, one key
  KEYV=2 fzx::summary_path d x 0
  [ "$d" = "$b" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/asked")" -eq 1 ]
  # the next listing (a new process) asks again
  _FZX_SUMMARY_KEYS=()
  KEYV=2 fzx::summary_path e x 0
  [ "$e" != "$b" ]
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
  output="$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;:]*m//g')"
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
  [[ " ${FZF_ARGS[*]} " == *" --border-label= menu:list "* ]]
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

# stats row <age_days> <event> <detail>
stat_row() {
  local now
  fzx::now_ms now
  printf '%s\tr\ts\tm\t-\t%s\t0\t-\t%s\n' "$((now - $1 * 86400000))" "$2" "$3" >> "$FZX_STATS_FILE"
}

# collected entry lines: "<id>\t<display>\t<target>\t<group>"
collected() {
  local spec id target group
  for spec in "$@"; do
    IFS=: read -r id target group <<< "$spec"
    printf '%s\tshow %s\t%s\t%s\n' "$id" "$id" "${target//+/:}" "$group"
  done
}

@test "menu_scores: launches by module and navigations by target, decaying; the menu and old rows do not count" {
  export FZX_STATS_FILE="$BATS_TEST_TMPDIR/stats.tsv" FZX_MENU_HALF_LIFE_DAYS=7 FZX_MENU_STATS_DAYS=30
  stat_row 0 start "files /tmp/x"
  stat_row 7 start "files"
  stat_row 0 nav "goto:git:log"
  stat_row 0 nav "back"
  stat_row 0 start "menu"
  stat_row 31 start "ps"
  stat_row 0 source "miss"
  run fzx::menu_scores
  [ "$status" -eq 0 ]
  # rounded to 3 decimals: the rows are stamped "now minus N days" a moment before the scores are taken,
  # and under the parallel suite that moment can show in the sixth decimal (0.999999)
  [ "$(printf '%s\n' "${lines[@]}" | sort | awk -F '\t' '{ printf "%s %.3f\n", $1, $2 }')" = "$(printf 'files 1.500\ngit:log 1.000')" ]
  rm "$FZX_STATS_FILE"
  run fzx::menu_scores
  [ -z "$output" ]
}

@test "arrange list: module order, an empty header field" {
  run fzx::_menu_arrange list < <(collected a#0:a:x b#0:b:y)
  [ "$output" = "$(printf 'a#0\tshow a#0\t\ta\nb#0\tshow b#0\t\tb')" ]
}

@test "arrange groups: recent on top, then groups in FZX_MENU_GROUPS order, others by name, most used first" {
  export FZX_STATS_FILE="$BATS_TEST_TMPDIR/stats.tsv"
  FZX_MENU_GROUPS=(sys dev) FZX_MENU_RECENT=1
  stat_row 0 start "c"
  stat_row 0 start "c"
  stat_row 0 nav "goto:b+m"
  stat_row 0 nav "goto:a:m"
  run fzx::_menu_arrange groups < <(collected a#0:a:dev a#1:a+m:dev b#0:b:zz b#1:b+n:aa c#0:c:dev d#0:d:sys)
  [ "$status" -eq 0 ]
  local ids
  ids="$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')"
  [ "$ids" = "@recent c#0 @sys d#0 @dev a#1 a#0 @aa b#1 @zz b#0 " ]
  [[ "${lines[0]}" == $'@recent\t\t'*"── recent"* ]]
  [[ "${lines[1]}" == $'c#0\tshow c#0\t\t'* ]]
}

@test "arrange groups: no recent header without use; FZX_MENU_RECENT=0 shows none; no group means other" {
  export FZX_STATS_FILE="$BATS_TEST_TMPDIR/stats.tsv"
  FZX_MENU_GROUPS=(dev other)
  run fzx::_menu_arrange groups < <(collected a#0:a:dev b#0:b:)
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "@dev a#0 @other b#0 " ]
  stat_row 0 start "a"
  FZX_MENU_RECENT=0
  run fzx::_menu_arrange groups < <(collected a#0:a:dev b#0:b:)
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "@dev a#0 @other b#0 " ]
}

@test "headers are shown but never match a query" {
  command -v fzf > /dev/null || skip "no fzf"
  run fzf --filter=recent --delimiter=$'\t' --with-nth=2,3 --nth=1 < <(printf '@recent\t\t── recent\nr#0\trecent dirs\t\n')
  [ "$output" = "$(printf 'r#0\trecent dirs\t')" ]
}

@test "a header: enter moves down, the preview is empty" {
  menu_session
  run "$FZX" _cb nav entry @recent
  [ "$status" -eq 0 ]
  [ "$output" = down ]
  run "$FZX" _cb preview @recent
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "grouped, the cursor starts under the first header; not in list mode, nor over a saved place" {
  stub_fzf
  run "$FZX" --keep -m menu:groups
  [ "$(fzf_bind result-final)" = "result-final:pos(2)+unbind(result-final)" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --with-nth=2,3 --nth=1 --tabstop=1 "* ]]
  local sid
  sid="$(< "$BATS_TEST_TMPDIR/fzf.session")"
  printf '5' > "$FZX_SESSIONS_DIR/$sid/state/pos"
  run "$FZX" --resume "$sid"
  [ "$(fzf_binds result-final)" = "result-final:pos(5)+unbind(result-final)" ]
  # list is what the menu opens in
  run "$FZX"
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = list ]
  run fzf_bind result-final
  [ "$status" -eq 1 ]
}

@test "descriptions stay in their column: the modules' fit, a longer one is cut; every module has an icon" {
  local long
  long="$(grep -hoE 'fzx::entry +[^ ]+ +"[^"]*"' "$FZX_REPO"/modules/*/manifest.sh | awk -F'"' 'length($2) > 42')"
  [ -z "$long" ] || { printf 'too long for the column:\n%s\n' "$long"; return 1; }
  local m="$BATS_TEST_TMPDIR/mods/wordy"
  mkdir -p "$m"
  cat > "$m/manifest.sh" << 'EOF2'
wordy::manifest() { fzx::entry wordy "0123456789012345678901234567890123456789 and more"; }
wordy::summary() { echo STATUS; }
EOF2
  export FZX_MODULE_PATH="$BATS_TEST_TMPDIR/mods" FZX_SESSION_DIR="$BATS_TEST_TMPDIR" FZX_LOG_FILE=/dev/null
  load_libs log config menu
  run fzx::menu_lines
  [[ "$output" == *'01234567890123456789012345678901234567890…'* || "$output" == *'0123456789012345678901234567890123456789 …'* ]]
  [[ "$output" != *'and more'* ]]
  local missing="" d
  for d in "$FZX_REPO"/modules/*/; do
    [[ -f "$d/manifest.sh" ]] || continue
    grep -qE "^FZX_ICON=(\\$'|\"[^\"])" "$d/config.sh" || missing+=" ${d%/}"
  done
  [ -z "$missing" ] || { printf 'no icon:%s\n' "$missing"; return 1; }
}

@test "alt-o: to the menu in the path, however deep; else a new one under this screen; not bound in the menu" {
  stub_fzf
  run "$FZX" --keep
  local menu child grand
  menu="$(< "$BATS_TEST_TMPDIR/fzf.session")"
  run fzf_bind alt-o
  [ "$status" -eq 1 ]
  run env FZX_SESSION="$menu" "$FZX" _cb nav goto counter
  child="${output#become:$FZX --resume }" child="${child%% *}"
  run env FZX_SESSION="$child" "$FZX" _cb nav goto counter:two --x
  grand="${output#become:$FZX --resume }" grand="${grand%% *}"
  [ -n "$grand" ] && [ "$grand" != "$child" ]
  run env FZX_SESSION="$grand" "$FZX" _cb nav menu
  [ "$output" = "become:$FZX --resume $menu" ]
  # started outside the menu: a child menu, and alt-left comes back
  run "$FZX" --keep -m counter
  [ "$(fzf_bind alt-o)" = "alt-o:transform:$FZX _cb nav menu" ]
  local solo sub
  solo="$(< "$BATS_TEST_TMPDIR/fzf.session")"
  run env FZX_SESSION="$solo" "$FZX" _cb nav menu
  sub="${output#become:$FZX --resume }" sub="${sub%% *}"
  [ "$sub" != "$solo" ]
  [ "$(< "$FZX_SESSIONS_DIR/$sub/meta/module")" = menu ]
  [ "$(< "$FZX_SESSIONS_DIR/$sub/meta/parent")" = "$solo" ]
  # the same menu the next time
  run env FZX_SESSION="$solo" "$FZX" _cb nav menu
  [[ "$output" == "become:$FZX --resume $sub"* ]]
}

@test "alt-o is free in every module: no component row or module key takes it" {
  run grep -lE '^(action|toggle|mode|sort)[[:space:]]+[^[:space:]]+[[:space:]]+alt-o[[:space:]]' "$FZX_REPO"/modules/*/components.tsv
  [ -z "$output" ]
  run grep -lE '=alt-o([[:space:]]|$)' "$FZX_REPO"/modules/*/config.sh
  [ -z "$output" ]
}

@test "every module in the menu has a group from FZX_MENU_GROUPS" {
  local name dir group
  source "$MENU_DIR/config.sh"
  while IFS=$'\t' read -r name dir; do
    group="$(FZX_MENU_GROUP="" && source "$dir/config.sh" && printf '%s' "${FZX_MENU_GROUP:-}")"
    [[ " ${FZX_MENU_GROUPS[*]} " == *" $group "* ]] || {
      echo "$name: group '$group'"
      return 1
    }
  done < <(FZX_MODULE_PATH="$FZX_REPO/modules" fzx::menu_modules)
}

@test "alt-y copies the whole line in every module: only todos has its own, the others moved to alt-Y" {
  run grep -lE '^action[[:space:]]+[^[:space:]]+[[:space:]]+alt-y[[:space:]]' "$FZX_REPO"/modules/*/components.tsv
  [ "$output" = "$FZX_REPO/modules/todos/components.tsv" ]
  stub_fzf
  run "$FZX" -m counter
  [[ "$(fzf_bind alt-y)" == *"copy-line"* ]]
  run "$FZX"
  [[ "$(fzf_bind alt-y)" == "alt-y:transform($FZX _cb notify copy-line {+})"* ]]
  run "$FZX" -m shell:params
  [[ "$(fzf_bind alt-Y)" == *"value"* ]]
}

@test "ctrl-y reports in the footer on every screen, never reaching fzfrc's notify-send" {
  stub_fzf
  local d m missing=""
  for d in "$FZX_REPO"/modules/*/; do
    m="${d%/}"; m="${m##*/}"
    [[ -f "$d/module.sh" ]] || continue
    # a module that does not apply here may not start; what it binds is what is checked
    run "$FZX" -m "$m" --dry-run
    [[ "$output" == *"ctrl-y:transform($FZX _cb notify "* || "$output" == *"ctrl-y:transform("*"_cb notify "* ]] || missing+=" $m"
  done
  [ -z "$missing" ] || { printf 'not through the footer:%s\n' "$missing"; return 1; }
  run "$FZX"
  [[ "$(fzf_bind ctrl-y)" == "ctrl-y:transform($FZX _cb notify copy {+4})"* ]]
}

@test "ctrl-y in the menu copies the entry's target: both modes carry it, a group header none" {
  load_libs log config menu
  run fzx::_menu_arrange list < <(printf 'ps#1\tthe row\tps:all\tsystem\n')
  [ "$output" = $'ps#1\tthe row\t\tps:all' ]
  FZX_MENU_RECENT=0 run fzx::_menu_arrange groups < <(printf 'ps#1\tthe row\tps:all\tsystem\n')
  [ "${lines[1]}" = $'ps#1\tthe row\t\tps:all' ]
  [[ "${lines[0]}" == "@system"$'\t\t'* ]]
}

@test "the menu's yanks go to the clipboard and say so, though its action rows are off" {
  stub_fzf
  "$FZX" --keep
  local sid
  sid="$(< "$BATS_TEST_TMPDIR/fzf.session")"
  mkdir -p "$BATS_TEST_TMPDIR/clipbin"
  printf '#!/bin/sh\ncat > "%s/clip"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/clipbin/xclip"
  cp "$BATS_TEST_TMPDIR/clipbin/xclip" "$BATS_TEST_TMPDIR/clipbin/xsel"
  chmod +x "$BATS_TEST_TMPDIR/clipbin/"*
  FZX_SESSION="$sid" PATH="$BATS_TEST_TMPDIR/clipbin:$PATH" run "$FZX" _cb notify copy "ps:all"
  [ "$status" -eq 0 ]
  [[ "$output" == *change-footer* ]]
  [ "$(< "$BATS_TEST_TMPDIR/clip")" = "ps:all" ]
}
