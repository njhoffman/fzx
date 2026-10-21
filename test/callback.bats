#!/usr/bin/env bats
# `fzx _cb <verb>`: the handlers fzf binds invoke

load test_helper

bats_require_minimum_version 1.5.0

COUNTER_DIR="$(readlink -f "$BATS_TEST_DIRNAME/fixtures/modules/counter")"

setup() {
  setup_fzx
  load_libs log session
  fzx::session_create counter "$COUNTER_DIR"
}

# record modes as a launch would
set_modes() {
  printf '%s\0' "$@" > "$FZX_SESSION_DIR/meta/modes"
}

@test "load: runs the source when there is no cache and writes the cache" {
  run "$FZX" _cb load
  [ "$status" -eq 0 ]
  [ "$output" = $'main:item-1-a\nmain:item-1-b' ]
  [ "$(< "$FZX_SESSION_DIR/data/main")" = "$output" ]
}

@test "load: serves the cache without rerunning the source" {
  "$FZX" _cb load > /dev/null
  run "$FZX" _cb load
  [ "$output" = $'main:item-1-a\nmain:item-1-b' ]
  [ "$(< "$COUNTER_FILE")" = 1 ]
  grep -q 'load: cache hit' "$LOG"
}

@test "load: the source sees the current mode and each mode has its own cache" {
  set_modes one two
  run "$FZX" _cb load
  [ "$output" = $'one:item-1-a\none:item-1-b' ]
  fzx::state_set mode two
  run "$FZX" _cb load
  [ "$output" = $'two:item-2-a\ntwo:item-2-b' ]
  fzx::state_set mode one
  run "$FZX" _cb load
  [ "$output" = $'one:item-1-a\none:item-1-b' ]
  [ -f "$FZX_SESSION_DIR/data/one" ] && [ -f "$FZX_SESSION_DIR/data/two" ]
}

@test "source: always reruns the source and replaces the cache" {
  "$FZX" _cb load > /dev/null
  run "$FZX" _cb source
  [ "$output" = $'main:item-2-a\nmain:item-2-b' ]
  [ "$(< "$FZX_SESSION_DIR/data/main")" = "$output" ]
}

@test "source: passes the session's module args" {
  fzx::session_destroy
  fzx::session_create counter "$COUNTER_DIR" --all "x y"
  run "$FZX" _cb source
  [ "${lines[2]}" = "args:--all x y" ]
}

@test "source: a failing source keeps the previous cache" {
  "$FZX" _cb load > /dev/null
  COUNTER_FAIL=1 run "$FZX" _cb source
  [ "$status" -eq 3 ]
  [ "$(< "$FZX_SESSION_DIR/data/main")" = $'main:item-1-a\nmain:item-1-b' ]
  [ -z "$(find "$FZX_SESSION_DIR/data" -name 'main.*')" ]
  grep -q 'source failed mode=main rc=3, cache kept' "$LOG"
}

@test "source: stderr goes to the log, not to fzf" {
  run --separate-stderr "$FZX" _cb source
  [[ "$output" != *stderr* ]]
  [ -z "$stderr" ]
  grep -q 'counter stderr run 1' "$LOG"
}

@test "preview: calls <module>::preview with the args" {
  run "$FZX" _cb preview item-1-a "x y"
  [ "$status" -eq 0 ]
  [ "$output" = "preview:item-1-a x y" ]
}

@test "action: calls <module>::action, logs stderr and passes the exit code" {
  run "$FZX" _cb action mark a b
  [ "$status" -eq 0 ]
  [ "$(< "$COUNTER_FILE.actions")" = "mark a b" ]
  grep -q 'action stderr' "$LOG"
  run "$FZX" _cb action fail a
  [ "$status" -eq 1 ]
}

@test "callbacks are logged with verb, rc and duration" {
  "$FZX" _cb source > /dev/null
  run grep -E "$FZX_SESSION +[0-9]+ +info +cb source rc=0 [0-9]+ms" "$LOG"
  [ "$status" -eq 0 ]
}

@test "unknown verb fails with 2" {
  run "$FZX" _cb bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown callback verb: bogus"* ]]
}

@test "outside a session fails with 2" {
  FZX_SESSION=nope run "$FZX" _cb load
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside a session"* ]]
}

@test "missing module function fails with 127" {
  local mod="$BATS_TEST_TMPDIR/mods/bare"
  mkdir -p "$mod"
  fzx::meta_set module bare
  fzx::meta_set module_dir "$mod"
  run -127 "$FZX" _cb preview x
  [[ "$output" == *"bare::preview not defined"* ]]
}

@test "mode next/prev: cycles with wrap-around, updates state, reloads in place" {
  set_modes one two
  fzx::state_set mode one
  run "$FZX" _cb mode next
  [ "$status" -eq 0 ]
  [ "$(< "$FZX_SESSION_DIR/state/mode")" = two ]
  [[ "$output" == "change-border-label( counter:two )+change-footer("*")+reload($FZX _cb load)" ]]
  run "$FZX" _cb mode next
  [ "$(< "$FZX_SESSION_DIR/state/mode")" = one ]
  run "$FZX" _cb mode prev
  [ "$(< "$FZX_SESSION_DIR/state/mode")" = two ]
}

@test "mode: footer highlights the new mode" {
  set_modes one two
  run "$FZX" _cb mode two
  local on=$'\e[38;5;45;1m' off=$'\e[38;5;240m' rst=$'\e[0m'
  [[ "$output" == *"change-footer(${off}one${rst}  ${on}two${rst})"* ]]
}

@test "mode: a named mode is selected; an unknown one fails with 2 and changes nothing" {
  set_modes one two
  run "$FZX" _cb mode two
  [ "$(< "$FZX_SESSION_DIR/state/mode")" = two ]
  run "$FZX" _cb mode nine
  [ "$status" -eq 2 ]
  [ "$(< "$FZX_SESSION_DIR/state/mode")" = two ]
}

@test "mode: a single mode prints nothing" {
  run "$FZX" _cb mode next
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mode: mode_restart restarts fzf into the new mode, keeping the query" {
  set_modes one two three
  fzx::state_set mode two
  FZF_QUERY="abc" FZF_POS=7 run "$FZX" _cb mode next
  [ "$output" = "become:$FZX --resume $FZX_SESSION -m :three" ]
  [ "$(< "$FZX_SESSION_DIR/state/mode")" = two ]
  [ "$(< "$FZX_SESSION_DIR/state/query")" = abc ]
  [ "$(< "$FZX_SESSION_DIR/state/pos")" = 1 ]
}

@test "nav resume: saves query and position, becomes the same session" {
  FZF_QUERY="foo bar" FZF_POS=4 run "$FZX" _cb nav resume
  [ "$status" -eq 0 ]
  [ "$output" = "become:$FZX --resume $FZX_SESSION" ]
  [ "$(< "$FZX_SESSION_DIR/state/query")" = "foo bar" ]
  [ "$(< "$FZX_SESSION_DIR/state/pos")" = 4 ]
}

@test "nav back: rings the bell at the root" {
  run "$FZX" _cb nav back
  [ "$status" -eq 0 ]
  [ "$output" = bell ]
}

@test "nav goto: creates a child linked to its parent and the root" {
  local parent="$FZX_SESSION" owner
  owner="$(< "$FZX_SESSION_DIR/meta/owner_pid")"
  run "$FZX" _cb nav goto counter --x 1
  [ "$status" -eq 0 ]
  [[ "$output" == "become:$FZX --resume "* ]]
  local child="${output##* }"
  [ "$child" != "$parent" ]
  local cdir="$FZX_RUNTIME_DIR/sessions/$child"
  [ "$(< "$cdir/meta/parent")" = "$parent" ]
  [ "$(< "$cdir/meta/root")" = "$parent" ]
  [ "$(< "$cdir/meta/owner_pid")" = "$owner" ]
  mapfile -d '' -t args < "$cdir/meta/args"
  [ "${args[*]}" = "--x 1" ]
}

@test "nav goto: the same target and args reuse the child; other args make a new one" {
  run "$FZX" _cb nav goto counter --x 1
  local first="${output##* }"
  run "$FZX" _cb nav goto counter --x 1
  [ "${output##* }" = "$first" ]
  run "$FZX" _cb nav goto counter --x 2
  [ "${output##* }" != "$first" ]
}

@test "nav goto: module:mode passes the mode to the resumed session" {
  run "$FZX" _cb nav goto counter:two
  [[ "$output" == "become:$FZX --resume "*" -m :two" ]]
}

@test "nav goto: an unknown module fails with 2 and creates nothing" {
  run "$FZX" _cb nav goto nope
  [ "$status" -eq 2 ]
  [ "$(session_dirs | wc -l)" -eq 1 ]
}

@test "nav back: from a child becomes the parent; grandchildren keep the root" {
  local root="$FZX_SESSION"
  run "$FZX" _cb nav goto counter --x 1
  local child="${output##* }"
  FZX_SESSION="$child" run "$FZX" _cb nav goto counter --y 1
  local grandchild="${output##* }"
  [ "$(< "$FZX_RUNTIME_DIR/sessions/$grandchild/meta/root")" = "$root" ]
  FZX_SESSION="$grandchild" run "$FZX" _cb nav back
  [ "$output" = "become:$FZX --resume $child" ]
}

@test "nav: unknown action fails with 2" {
  run "$FZX" _cb nav sideways
  [ "$status" -eq 2 ]
}
