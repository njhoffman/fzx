#!/usr/bin/env bats
# unit tests for lib/: core, log, session, config, opts

load test_helper

setup() {
  setup_fzx
  load_libs log session config opts
}

@test "module_find: finds a module on FZX_MODULE_PATH" {
  run fzx::module_find counter
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_DIRNAME/fixtures/modules/counter" ]
}

@test "module_find: earlier path entries win" {
  mkdir -p "$BATS_TEST_TMPDIR/mods/counter"
  touch "$BATS_TEST_TMPDIR/mods/counter/module.sh"
  FZX_MODULE_PATH="$BATS_TEST_TMPDIR/mods:$FZX_MODULE_PATH"
  run fzx::module_find counter
  [ "$output" = "$BATS_TEST_TMPDIR/mods/counter" ]
}

@test "module_find: missing module and path-like names fail" {
  run fzx::module_find nope
  [ "$status" -eq 1 ]
  run fzx::module_find ../counter
  [ "$status" -eq 1 ]
}

@test "now_ms: sets a millisecond timestamp" {
  local t
  fzx::now_ms t
  [[ "$t" =~ ^[0-9]{13}$ ]]
}

@test "glyphs_plain: selectors, skin tones, joiners and keycaps go; other text and plain emoji stay" {
  load_libs
  local in out
  in="$(printf 'a \u2764\ufe0f b \U1F44D\U1F3FB c \U1F468\u200d\U1F469 d 1\ufe0f\u20e3 e \u263a\ufe0e f \U1F602 g a\u200bb \u00e9')"
  out="$(fzx::glyphs_plain <<< "$in")"
  [ "$out" = "$(printf 'a \u2764 b \U1F44D c \U1F468\U1F469 d 1 e \u263a f \U1F602 g a\u200bb \u00e9')" ]
  # the same under any locale
  [ "$(LC_ALL=C fzx::glyphs_plain <<< "$in")" = "$out" ]
  # FZX_GLYPHS_PLAIN=0: through untouched
  [ "$(FZX_GLYPHS_PLAIN=0 fzx::glyphs_plain <<< "$in")" = "$in" ]
}

@test "glyphs_plain: only the given fields; -z keeps NUL-separated records" {
  load_libs
  local heart skin row awk
  heart="$(printf '\u2764\ufe0f')" skin="$(printf '\U1F44D\U1F3FB')"
  row="id-$heart"$'\t'"shown $heart"$'\t'"also $skin"$'\t'"kept $skin"
  for awk in gawk mawk; do
    command -v "$awk" > /dev/null || continue
    mkdir -p "$BATS_TEST_TMPDIR/$awk"
    ln -sf "$(command -v "$awk")" "$BATS_TEST_TMPDIR/$awk/awk"
    run env PATH="$BATS_TEST_TMPDIR/$awk:$PATH" bash -c 'source "$1/lib/core.sh"; fzx::glyphs_plain 2 3 <<< "$2"' _ "$FZX_REPO" "$row"
    [ "$output" = "id-$heart"$'\t'"shown $(printf '\u2764')"$'\t'"also $(printf '\U1F44D')"$'\t'"kept $skin" ]
  done
  # a field past the end of a row adds nothing
  [ "$(fzx::glyphs_plain 9 <<< $'a\tb')" = $'a\tb' ]
  [ "$(printf '1\tx%s\ny\0002\tz\0' "$heart" | fzx::glyphs_plain -z | tr '\0' '|')" = "1"$'\t'"x$(printf '\u2764')"$'\n'"y|2"$'\t'"z|" ]
}

@test "plural: singular for one, word plus s or the given plural otherwise" {
  [ "$(fzx::plural 1 file)" = "1 file" ]
  [ "$(fzx::plural 0 file)" = "0 files" ]
  [ "$(fzx::plural 2 file)" = "2 files" ]
  [ "$(fzx::plural 1 entry entries)" = "1 entry" ]
  [ "$(fzx::plural 3 entry entries)" = "3 entries" ]
  [ "$(fzx::plural 2 'work tree')" = "2 work trees" ]
}

@test "plural: blanks dropped (BSD wc -l), empty is zero, no newline" {
  [ "$(fzx::plural '       1' buffer)" = "1 buffer" ]
  [ "$(fzx::plural '' buffer)" = "0 buffers" ]
  [ "$(fzx::plural 1 x | od -An -c | tr -d ' ')" = "1x" ]
}

@test "plural: the awk function agrees, an unset count is zero" {
  run awk "$FZX_AWK_PLURAL"'BEGIN { print plural(1, "pane") "|" plural(4, "pane") "|" plural(x, "alias", "aliases") "|" plural(1, "alias", "aliases") }'
  [ "$output" = "1 pane|4 panes|0 aliases|1 alias" ]
}

@test "session_create: writes meta and exports the session" {
  fzx::session_create counter /some/dir
  [ -n "$FZX_SESSION" ]
  [ -d "$FZX_SESSION_DIR/state" ] && [ -d "$FZX_SESSION_DIR/data" ]
  [ "$(< "$FZX_SESSION_DIR/meta/module")" = counter ]
  [ "$(< "$FZX_SESSION_DIR/meta/module_dir")" = /some/dir ]
  [ "$(< "$FZX_SESSION_DIR/meta/owner_pid")" = "$$" ]
  [ "$(< "$FZX_SESSION_DIR/meta/cwd")" = "$PWD" ]
  run bash -c 'printf %s "$FZX_SESSION"'
  [ "$output" = "$FZX_SESSION" ]
}

@test "session_args: round-trips args with spaces and empty strings" {
  fzx::session_create counter /d "a b" "" "--flag=x y"
  fzx::session_args
  [ "${#FZX_ARGS[@]}" -eq 3 ]
  [ "${FZX_ARGS[0]}" = "a b" ]
  [ "${FZX_ARGS[1]}" = "" ]
  [ "${FZX_ARGS[2]}" = "--flag=x y" ]
}

@test "session_args: no args gives an empty array" {
  fzx::session_create counter /d
  fzx::session_args
  [ "${#FZX_ARGS[@]}" -eq 0 ]
}

@test "state_set/state_get: round-trips multi-line values; missing keys fail" {
  fzx::session_create counter /d
  fzx::state_set query $'line one\nline two'
  local v
  fzx::state_get query v
  [ "$v" = $'line one\nline two' ]
  run fzx::state_get missing v
  [ "$status" -eq 1 ]
}

@test "session_attach: attaches to an existing session" {
  fzx::session_create counter /d
  local sid="$FZX_SESSION"
  unset FZX_SESSION FZX_SESSION_DIR
  fzx::session_attach "$sid"
  [ "$FZX_SESSION" = "$sid" ]
  [ "$FZX_SESSION_DIR" = "$FZX_RUNTIME_DIR/sessions/$sid" ]
}

@test "session_attach: rejects missing, empty and path-like ids" {
  run fzx::session_attach nope
  [ "$status" -eq 1 ]
  unset FZX_SESSION
  run fzx::session_attach
  [ "$status" -eq 1 ]
  run fzx::session_attach ../sessions
  [ "$status" -eq 1 ]
}

@test "session_destroy: removes the session dir" {
  fzx::session_create counter /d
  fzx::session_destroy
  [ ! -d "$FZX_SESSION_DIR" ]
}

@test "session_destroy: refuses a dir outside the sessions root" {
  fzx::session_create counter /d
  mkdir -p "$BATS_TEST_TMPDIR/precious"
  FZX_SESSION_DIR="$BATS_TEST_TMPDIR/precious"
  run fzx::session_destroy
  [ "$status" -eq 1 ]
  [ -d "$BATS_TEST_TMPDIR/precious" ]
}

@test "log: tags lines with session and level" {
  FZX_SESSION=sid-123
  fzx::log info "hello world"
  run tail -n 1 "$LOG"
  [[ "$output" =~ sid-123\ +[0-9]+\ +info\ +hello\ world$ ]]
}

@test "log: drops lines below FZX_LOG_LEVEL" {
  FZX_LOG_LEVEL=warn
  fzx::log info "quiet"
  fzx::log error "loud"
  run cat "$LOG"
  [[ "$output" != *quiet* ]]
  [[ "$output" == *loud* ]]
}

@test "config_load: defaults, then module defaults, then user, then user per module" {
  local mod="$BATS_TEST_TMPDIR/mods/m"
  mkdir -p "$mod" "$FZX_CONFIG_DIR/modules/m"
  echo 'FZX_KEYS[m.a]=ctrl-a; FZX_KEYS[m.b]=ctrl-b; FZX_FZF_OPTS+=(--module-layer)' > "$mod/config.sh"
  echo 'FZX_KEYS[reload_hard]=ctrl-g; FZX_KEYS[m.a]=alt-a; FZX_FZF_OPTS+=(--user-layer)' > "$FZX_CONFIG_DIR/config.sh"
  echo 'FZX_KEYS[m.a]=f1; FZX_FZF_OPTS+=(--user-module-layer)' > "$FZX_CONFIG_DIR/modules/m/config.sh"

  fzx::config_load "$mod" m
  [ "${FZX_KEYS[reload_hard]}" = ctrl-g ]
  [ "${FZX_KEYS[m.b]}" = ctrl-b ]
  [ "${FZX_KEYS[m.a]}" = f1 ]
  [ "${FZX_FZF_OPTS[0]}" = --ansi ]
  [ "${FZX_FZF_OPTS[*]: -3}" = "--module-layer --user-layer --user-module-layer" ]
  [ "${#FZX_CONFIG_LOADED[@]}" -eq 4 ]
}

@test "config_load: a user's global key is not undone by a module default" {
  local mod="$BATS_TEST_TMPDIR/mods/m"
  mkdir -p "$mod" "$FZX_CONFIG_DIR"
  echo 'FZX_KEYS[m.a]=ctrl-a' > "$mod/config.sh"
  echo 'FZX_KEYS[m.a]=alt-a' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load "$mod" m
  [ "${FZX_KEYS[m.a]}" = alt-a ]
}

@test "config_load: defaults only when no other layers exist" {
  fzx::config_load
  [ "${FZX_KEYS[reload_hard]}" = ctrl-r ]
  [ "${FZX_KEYS[reload_soft]}" = alt-r ]
}

@test "config_load: the sorted column's decorations and underline color become FZX_COLORS[sorted]" {
  unset FZX_SORTED_STYLE FZX_SORTED_UNDERLINE_COLOR
  fzx::config_load
  [ "${FZX_COLORS[sorted]}" = "4:5;58;2;110;110;110" ]
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_SORTED_STYLE="bold dim italic underline blink reverse overline"; FZX_SORTED_UNDERLINE_COLOR=245' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[sorted]}" = "1;2;3;4;5;7;53;58;5;245" ]
  echo 'FZX_SORTED_STYLE="underdouble undercurl underdotted"; FZX_SORTED_UNDERLINE_COLOR=""' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[sorted]}" = "4:2;4:3;4:4" ]
  # an underline color without an underline is left out
  echo 'FZX_SORTED_STYLE=bold' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[sorted]}" = 1 ]
  # nothing to add: 24, which is still a valid parameter after a ";"
  echo 'FZX_SORTED_STYLE=""' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[sorted]}" = 24 ]
  # unknown names and colors are skipped with a warning
  echo 'FZX_SORTED_STYLE="sparkle underline"; FZX_SORTED_UNDERLINE_COLOR=gray' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[sorted]}" = 4 ]
  grep -q 'unknown decoration sparkle' "$LOG"
  grep -q 'FZX_SORTED_UNDERLINE_COLOR: not #rrggbb or 0-255: gray' "$LOG"
  # FZX_COLORS[sorted] set by a layer wins
  echo 'FZX_COLORS[sorted]="1;4"' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[sorted]}" = "1;4" ]
  # ... except under FZX_SORTED_SHOW=header: the rows stay plain
  echo 'FZX_COLORS[sorted]="1;4"; FZX_SORTED_SHOW=header' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[sorted]}" = 24 ]
}

@test "config_load: header rows by default: #007e95 columns, the sorted one bold, underlined #00d7ff, the rows plain" {
  unset FZX_SORTED_SHOW FZX_HEADER_COLUMN_COLOR FZX_SORTED_HEADER_STYLE
  fzx::config_load
  [ "${FZX_COLORS[header_column]}" = "38;2;0;126;149" ] && [ "${FZX_COLORS[header_sorted]}" = "1;4;38;2;0;215;255" ]
  [ "$FZX_SORTED_SHOW" = header ] && [ "$FZX_SORTED_ARROWS" = "↑ ↓" ] && [ "${FZX_COLORS[sorted]}" = 24 ]
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_HEADER_COLUMN_COLOR=245; FZX_SORTED_HEADER_STYLE="bold underline"; FZX_SORTED_HEADER_COLOR=""; FZX_SORTED_SHOW=both' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[header_column]}" = "38;5;245" ] && [ "${FZX_COLORS[header_sorted]}" = "1;4" ]
  [ "${FZX_COLORS[sorted]}" = 4 ]
  echo 'FZX_SORTED_HEADER_STYLE=""; FZX_SORTED_HEADER_COLOR=""; FZX_SORTED_SHOW=sideways' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[header_sorted]}" = 1 ] && [ "$FZX_SORTED_SHOW" = header ]
  grep -q 'FZX_SORTED_SHOW: not header, rows or both: sideways' "$LOG"
  echo 'FZX_COLORS[header_column]=""; FZX_HEADER_COLUMN_COLOR=245; FZX_COLORS[header_sorted]="7"' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[header_column]}" = "" ] && [ "${FZX_COLORS[header_sorted]}" = 7 ]
}

@test "header: cells padded outside their color, the sorted one with the sort's arrow; awk's the same; rows only with FZX_SORT_HEADER" {
  load_libs header
  declare -gA FZX_COLORS=([header_column]="" [header_sorted]=1)
  local c
  FZX_SORT_DESC=1 fzx::header_cell c CPU 6 1 1
  [ "$c" = $'  \e[1mCPU↓\e[0m' ]
  fzx::header_cell c NAME 6 0 1
  [ "$c" = $'\e[1mNAME↑\e[0m ' ]
  fzx::header_cell c PID 5 0 0
  [ "$c" = "PID  " ]
  FZX_COLORS[header_column]=245
  FZX_SORTED_ARROWS="" fzx::header_cell c PID 0 0 1
  [ "$c" = $'\e[1mPID\e[0m' ]
  NO_COLOR=1 fzx::header_cell c PID 4 1 0
  [ "$c" = " PID" ]
  # awk: the arrow's width counted in characters
  FZX_SORT_HEADER=1 FZX_SORT_DESC=1 NO_COLOR=1 fzx::header_vars
  [ "$(awk "${FZX_HEADER_VARS[@]}" "$FZX_HEADER_AWK"'BEGIN { printf "[%s][%s]%d", hcell("CPU", 6, 1, 1), hcell("A", 3, 0, 0), hon }')" = "[  CPU↓][A  ]1" ]
  # rows: empty fields first, a two-space gap, a field break, NUL-ended; none without FZX_SORT_HEADER
  FZX_COLORS[header_column]=""
  [ -z "$(fzx::header_print 1 A A 2 0 B 0 0)" ]
  [ "$(FZX_SORT_HEADER=1 fzx::header_print 1 B A 2 0 "" 0 0 B 0 0 $'\t' 0 0 C 0 0)" = $'\tA   \e[1mB↑\e[0m \tC' ]
  [ "$(FZX_SORT_HEADER=1 fzx::header_print -z 0 "" A 0 0 | tr '\0' @)" = "A@" ]
}

@test "cb: routes through fzx _cb under a session" {
  run fzx::cb preview {1}
  [ "$output" = "$FZX_BIN _cb preview {1}" ]
  run fzx::cb source
  [ "$output" = "$FZX_BIN _cb source" ]
}

@test "cb: calls module scripts directly when standalone" {
  FZX_STANDALONE=1
  FZX_MODULE_DIR="/mods/my mod"
  FZX_ARGS=(--all "x y")
  run fzx::cb source
  [ "$output" = '/mods/my\ mod/source.sh --all x\ y' ]
  run fzx::cb preview {1}
  [ "$output" = '/mods/my\ mod/preview.sh {1}' ]
  run fzx::cb action term {+1}
  [ "$output" = '/mods/my\ mod/actions.sh term {+1}' ]
  run fzx::cb bogus
  [ "$status" -eq 1 ]
}

@test "opts_print: pairs flags with separate values and quotes when needed" {
  FZX_OPTS=(--ansi --bind "ctrl-r:reload(x y)" --header-lines=1 --preview "cat {}")
  run fzx::opts_print
  [ "${lines[0]}" = 'fzf \' ]
  [ "${lines[1]}" = '  --ansi \' ]
  [ "${lines[2]}" = "  --bind 'ctrl-r:reload(x y)' \\" ]
  [ "${lines[3]}" = '  --header-lines=1 \' ]
  [ "${lines[4]}" = "  --preview 'cat {}' \\" ]
  [ "${lines[5]}" = '  < /dev/null' ]
}

@test "session_create: a root session is its own root and owned by this process" {
  fzx::session_create counter /d
  [ "$(< "$FZX_SESSION_DIR/meta/root")" = "$FZX_SESSION" ]
  [ ! -f "$FZX_SESSION_DIR/meta/parent" ]
}

@test "session_create_child: links parent and root, inherits the owner" {
  fzx::session_create counter /d
  local root="$FZX_SESSION"
  fzx::session_create_child counter /d --x
  local child="$FZX_SESSION"
  fzx::session_create_child counter /d --y
  [ "$(< "$FZX_SESSION_DIR/meta/parent")" = "$child" ]
  [ "$(< "$FZX_SESSION_DIR/meta/root")" = "$root" ]
  [ "$(< "$FZX_SESSION_DIR/meta/owner_pid")" = "$$" ]
}

@test "session_modes/session_mode: default main, first mode, then state" {
  fzx::session_create counter /d
  local m
  fzx::session_modes
  [ "${FZX_MODES[*]}" = main ]
  printf '%s\0' one two > "$FZX_SESSION_DIR/meta/modes"
  fzx::session_modes
  fzx::session_mode m
  [ "$m" = one ]
  fzx::state_set mode two
  fzx::session_mode m
  [ "$m" = two ]
}

@test "session_label: module:mode from the root down, into the caller's variable" {
  fzx::session_create a /d
  fzx::state_set mode x
  fzx::session_create_child b /d
  fzx::session_create_child c /d
  fzx::state_set mode z
  local label
  fzx::session_label label
  [ "$label" = "a:x > b > c:z" ]
}

@test "border title: white where it came from, brighter and bold where it is; nerd arrow, else >; settings" {
  unset FZX_TITLE_COLOR FZX_TITLE_CURRENT_COLOR
  fzx::config_load
  [ "${FZX_COLORS[title]}" = "38;5;7" ] && [ "${FZX_COLORS[title_current]}" = "1;38;5;15" ]
  load_libs icons
  local t
  FZX_ICONS=none fzx::title_paint t menu:list glyphs:nerd
  [ "$t" = $'\e[38;5;7mmenu:list > \e[0m\e[1;38;5;15mglyphs:nerd\e[0m' ]
  FZX_ICONS=nerd fzx::title_paint t menu:list glyphs:nerd
  [[ "$t" == *$'menu:list \357\220\262 '* ]]
  FZX_ICONS=none fzx::title_paint t ps:user
  [ "$t" = $'\e[1;38;5;15mps:user\e[0m' ]
  NO_COLOR=1 FZX_ICONS=none fzx::title_paint t a b c
  [ "$t" = "a > b > c" ]
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_TITLE_COLOR="#112233"; FZX_TITLE_CURRENT_COLOR=""' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[title]}" = "38;2;17;34;51" ] && [ "${FZX_COLORS[title_current]}" = "" ]
  echo 'FZX_COLORS[title_current]="7"' > "$FZX_CONFIG_DIR/config.sh"
  fzx::config_load
  [ "${FZX_COLORS[title_current]}" = 7 ]
}

@test "component_line: modes, toggles and the sort key, active ones highlighted" {
  load_libs components
  fzx::config_load
  FZX_COMP=($'toggle\ta\t-\t-\t-' $'toggle\tb\t-\t-\t-')
  FZX_MODES=(one two) FZX_MODE=two FZX_TOGGLES=b FZX_SORT=mem
  local line
  fzx::component_line line
  local on=$'\e[38;5;45;1m' off=$'\e[38;5;240m' r=$'\e[0m' ton=$'\e[38;5;49m' srt=$'\e[38;5;45m'
  # minimal: the toggles' state is their color, the sort keeps its arrow
  FZX_ICONS=unicode fzx::component_line line
  [ "$line" = "${off}one${r}  ${on}two${r}${off}  |  ${r}${off}a${r}  ${ton}b${r}${off}  |  ${r}${srt}↓ mem${r}" ]
  # icon style, unicode icons: toggles marked on/off
  FZX_COMPONENT_STYLE=icon FZX_ICONS=unicode fzx::component_line line
  [ "$line" = "${off}one${r}  ${on}two${r}${off}  |  ${r}${off}○ a${r}  ${ton}● b${r}${off}  |  ${r}${srt}↓ mem${r}" ]
  # no icons: the names alone, the sort keeps its arrow
  FZX_COMPONENT_STYLE=icon FZX_ICONS=none fzx::component_line line
  [ "$line" = "${off}one${r}  ${on}two${r}${off}  |  ${r}${off}a${r}  ${ton}b${r}${off}  |  ${r}${srt}↓ mem${r}" ]
  FZX_MODES=(main) FZX_COMP=() FZX_SORT=""
  fzx::component_line line
  [ -z "$line" ]
}

@test "persist_ttl: accepts none, session and cache:<n>[smhd]" {
  local ttl
  fzx::persist_ttl none ttl && [ "$ttl" = 0 ]
  fzx::persist_ttl session ttl && [ "$ttl" = 0 ]
  fzx::persist_ttl cache:90 ttl && [ "$ttl" = 90 ]
  fzx::persist_ttl cache:90s ttl && [ "$ttl" = 90 ]
  fzx::persist_ttl cache:5m ttl && [ "$ttl" = 300 ]
  fzx::persist_ttl cache:2h ttl && [ "$ttl" = 7200 ]
  fzx::persist_ttl cache:1d ttl && [ "$ttl" = 86400 ]
}

@test "persist_ttl: rejects anything else" {
  local ttl p
  for p in "" cache cache: cache:0 cache:5x cache:-1 always; do
    run fzx::persist_ttl "$p" ttl
    [ "$status" -eq 1 ]
  done
}

@test "pid_start/owner_alive: live owner, dead owner, recycled pid" {
  local start
  fzx::pid_start $$ start
  [[ "$start" =~ ^[0-9]+$ ]]
  fzx::session_create counter /d
  fzx::owner_alive "$FZX_SESSION_DIR"

  printf '999999999' > "$FZX_SESSION_DIR/meta/owner_pid"
  run fzx::owner_alive "$FZX_SESSION_DIR"
  [ "$status" -eq 1 ]

  printf '%s' $$ > "$FZX_SESSION_DIR/meta/owner_pid"
  printf '1' > "$FZX_SESSION_DIR/meta/owner_start"
  run fzx::owner_alive "$FZX_SESSION_DIR"
  [ "$status" -eq 1 ]
}

@test "session_create: a cache key that depends on module, args and cwd" {
  fzx::session_create counter /d --x
  local a b c
  a="$(< "$FZX_SESSION_DIR/meta/cache_key")"
  fzx::session_create counter /d --x
  b="$(< "$FZX_SESSION_DIR/meta/cache_key")"
  fzx::session_create counter /d --y
  c="$(< "$FZX_SESSION_DIR/meta/cache_key")"
  [ "$a" = "$b" ] && [ "$a" != "$c" ]
  cd "$BATS_TEST_TMPDIR"
  fzx::session_create counter /d --x
  [ "$(< "$FZX_SESSION_DIR/meta/cache_key")" != "$a" ]
}

@test "config_show: layers, keys, colors and settings" {
  run fzx::config_show ps
  [ "${lines[0]}" = "# layers (later wins)" ]
  [[ "$output" == *"/modules/ps/config.sh"* ]]
  [[ "$output" == *"ps.children          ctrl-o"* ]]
  [[ "$output" == *"FZX_HISTORY              1"* ]]
}

# an editor like vim: replaces one with ONE and ends the file with a newline
edit_stub() {
  cat > "$BATS_TEST_TMPDIR/ed" << 'STUB'
#!/usr/bin/env bash
f="${@: -1}"
case "${ED_DO:-change}" in
  change) sed -i 's/one/ONE/' "$f"; [ -n "$(tail -c1 "$f")" ] && echo >> "$f" ;;
  empty) : > "$f" ;;
  blank) echo > "$f" ;;
  fail) exit 1 ;;
esac
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/ed"
  mkdir -p "$BATS_TEST_TMPDIR/t"
  export VISUAL="$BATS_TEST_TMPDIR/ed" FZX_TTY=/dev/null TMPDIR="$BATS_TEST_TMPDIR/t"
}

@test "edit_text: the edited text; the newline the editor adds is dropped unless the input had one" {
  fzx::require builtin
  edit_stub
  local out
  fzx::edit_text out < <(printf 'one\ntwo')
  [ "$out" = $'ONE\ntwo' ]
  fzx::edit_text out < <(printf 'one\n\n')
  [ "$out" = $'ONE\n\n' ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "edit_text: emptied, a lone newline or a failing editor (:cq) is false with nothing" {
  fzx::require builtin
  edit_stub
  local out=stale
  ED_DO=empty run fzx::edit_text out < <(printf 'one')
  [ "$status" -ne 0 ]
  ED_DO=blank run fzx::edit_text out < <(printf 'one')
  [ "$status" -ne 0 ]
  ED_DO=fail fzx::edit_text out < <(printf 'one') || :
  [ -z "$out" ]
}
