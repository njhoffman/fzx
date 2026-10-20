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

@test "component_line: modes, toggles and the sort key, active ones highlighted" {
  load_libs components
  fzx::config_load
  FZX_COMP=($'toggle\ta\t-\t-\t-' $'toggle\tb\t-\t-\t-')
  FZX_MODES=(one two) FZX_MODE=two FZX_TOGGLES=b FZX_SORT=mem
  local line
  fzx::component_line line
  local on=$'\e[38;5;45;1m' off=$'\e[38;5;240m' r=$'\e[0m' ton=$'\e[38;5;49m' srt=$'\e[38;5;45m'
  [ "$line" = "${off}one${r}  ${on}two${r}${off}  |  ${r}${off}a${r}  ${ton}b${r}${off}  |  ${r}${srt}"$'\u2193'"mem${r}" ]
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
