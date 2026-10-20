#!/usr/bin/env bats
# bin/fzx: argument handling, session ownership, resume and dry-run, against a stub fzf

load test_helper

setup() {
  setup_fzx
  stub_fzf
}

@test "--help prints usage" {
  run "$FZX" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: fzx"* ]]
}

@test "--mode without a value fails with 2" {
  run "$FZX" --mode
  [ "$status" -eq 2 ]
}

@test "unknown module fails with 2" {
  run "$FZX" -m nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"module not found: nope"* ]]
  [ -z "$(session_dirs)" ]
}

@test "runs fzf inside a session and removes the session afterwards" {
  STUB_FZF_OUT=item-1-a run "$FZX" -m counter
  [ "$status" -eq 0 ]
  [ "$output" = item-1-a ]
  [ -n "$(< "$BATS_TEST_TMPDIR/fzf.session")" ]
  grep -qx meta "$BATS_TEST_TMPDIR/fzf.sessiondir"
  [ -z "$(session_dirs)" ]
}

@test "passes fzf's exit code through" {
  STUB_FZF_RC=130 run "$FZX" -m counter
  [ "$status" -eq 130 ]
  [ -z "$(session_dirs)" ]
}

@test "--keep and FZX_KEEP=1 keep the session" {
  run "$FZX" --keep -m counter
  [ "$(session_dirs | wc -l)" -eq 1 ]
  FZX_KEEP=1 run "$FZX" -m counter
  [ "$(session_dirs | wc -l)" -eq 2 ]
}

@test "unrecognised args and args after -- go to the module" {
  run "$FZX" --keep -m counter --all -- --mode x
  local dir
  dir="$(session_dirs)"
  mapfile -d '' -t args < "$dir/meta/args"
  [ "${args[*]}" = "--all --mode x" ]
}

@test "core binds: start loads, reload key reruns the source, soft reload resumes, back" {
  run "$FZX" -m counter
  [ "$(fzf_bind start)" = "start:reload:$FZX _cb load" ]
  [ "$(fzf_bind ctrl-r)" = "ctrl-r:reload:$FZX _cb source" ]
  [ "$(fzf_bind alt-r)" = "alt-r:transform:$FZX _cb nav resume" ]
  [ "$(fzf_bind alt-left)" = "alt-left:transform:$FZX _cb nav back" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --listen=$FZX_RUNTIME_DIR/sessions/"*"/fzf.sock "* ]]
  [[ " ${FZF_ARGS[*]} " == *" --with-shell=bash -c "* ]]
}

@test "module opts are appended after the core opts" {
  run "$FZX" -m counter
  [ "$(fzf_flag --preview)" = "$FZX _cb preview {1}" ]
  [ "$(fzf_bind ctrl-x)" = "ctrl-x:execute-silent($FZX _cb action mark {+1})" ]
}

@test "user config overrides core keys" {
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_KEYS[reload_hard]=ctrl-g' > "$FZX_CONFIG_DIR/config.sh"
  run "$FZX" -m counter
  [ "$(fzf_bind ctrl-g)" = "ctrl-g:reload:$FZX _cb source" ]
  run fzf_bind ctrl-r
  [ "$status" -eq 1 ]
}

@test "a failing <module>::opts fails with 1 without running fzf" {
  COUNTER_OPTS_FAIL=1 run "$FZX" -m counter
  [ "$status" -eq 1 ]
  [ ! -f "$BATS_TEST_TMPDIR/fzf.args" ]
  [ -z "$(session_dirs)" ]
}

@test "--dry-run prints the fzf command and leaves no session" {
  run "$FZX" -m counter --dry-run
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "# module  counter:one ("* ]]
  [[ "${lines[1]}" == "# session "* ]]
  [ "${lines[2]}" = 'fzf \' ]
  [[ "$output" == *"--bind 'start:reload:$FZX _cb load'"* ]]
  [[ "$output" == *"--preview '$FZX _cb preview {1}'"* ]]
  [ "${lines[-1]}" = '  < /dev/null' ]
  [ ! -f "$BATS_TEST_TMPDIR/fzf.args" ]
  [ -z "$(session_dirs)" ]
}

@test "--resume of a missing session fails with 2" {
  run "$FZX" --resume nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"no such session: nope"* ]]
  unset FZX_SESSION
  run "$FZX" --resume
  [ "$status" -eq 2 ]
}

@test "--resume reuses the session and its cache and does not clean up" {
  "$FZX" --keep -m counter
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" "$FZX" _cb load > /dev/null

  STUB_FZF_OUT=picked run "$FZX" --resume "$sid"
  [ "$status" -eq 0 ]
  [ "$output" = picked ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.session")" = "$sid" ]
  [ -d "$FZX_RUNTIME_DIR/sessions/$sid" ]

  FZX_SESSION="$sid" run "$FZX" _cb load
  [ "$output" = $'one:item-1-a\none:item-1-b' ]
  [ "$(< "$COUNTER_FILE")" = 1 ]
}

@test "--resume defaults to \$FZX_SESSION (the soft reload path)" {
  "$FZX" --keep -m counter
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" run "$FZX" --resume
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.session")" = "$sid" ]
  grep -q "$sid .* session resumed" "$LOG"
}

@test "--resume=SID form" {
  "$FZX" --keep -m counter
  local sid
  sid="$(basename "$(session_dirs)")"
  run "$FZX" --resume="$sid" --dry-run
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "# session $sid ($FZX_RUNTIME_DIR/sessions/$sid)" ]
}

@test "debug ls lists sessions with owner status" {
  "$FZX" --keep -m counter
  run "$FZX" debug ls
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == SESSION* ]]
  [[ "${lines[1]}" =~ counter:one\ +-\ +[0-9]+\ +dead ]]
}

@test "debug with an unknown subcommand fails with 2" {
  run "$FZX" debug bogus
  [ "$status" -eq 2 ]
}

@test "the first mode is the default and is exported to fzf" {
  "$FZX" --keep -m counter
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = one ]
  [ "$(fzf_flag --header 2> /dev/null || true)" = "" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=mode:one "* ]]
  [[ " ${FZF_ARGS[*]} " == *" --border-label= counter:one "* ]]
  [ "$(< "$(session_dirs)/state/mode")" = one ]
}

@test "-m module:mode starts in that mode" {
  run "$FZX" -m counter:two
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = two ]
}

@test "-m module:unknown fails with 2 and leaves no session" {
  run "$FZX" -m counter:nine
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown mode for counter: nine (modes: one two three)"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/fzf.args" ]
  [ -z "$(session_dirs)" ]
}

@test "modes are recorded in meta for callbacks" {
  "$FZX" --keep -m counter
  mapfile -d '' -t modes < "$(session_dirs)/meta/modes"
  [ "${modes[*]}" = "one two three" ]
}

@test "several modes: footer hints and mode keys are bound" {
  run "$FZX" -m counter
  [ "$(fzf_bind alt-0)" = "alt-0:transform:$FZX _cb mode next" ]
  [ "$(fzf_bind alt-9)" = "alt-9:transform:$FZX _cb mode prev" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --footer="*one*two*three* ]]
}

@test "a module without modes has mode main and no footer or mode keys" {
  COUNTER_MODES="" run "$FZX" -m counter
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = main ]
  run fzf_bind alt-0
  [ "$status" -eq 1 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --footer="* ]]
}

@test "--resume restores the saved query and cursor position" {
  "$FZX" --keep -m counter
  local dir sid
  dir="$(session_dirs)"
  sid="${dir##*/}"
  printf 'my query' > "$dir/state/query"
  printf '5' > "$dir/state/pos"
  run "$FZX" --resume "$sid"
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --query=my query "* ]]
  [ "$(fzf_bind load)" = "load:pos(5)+unbind(load)" ]
}

@test "--resume does not bind load when the cursor was on the first line" {
  "$FZX" --keep -m counter
  local dir
  dir="$(session_dirs)"
  printf '1' > "$dir/state/pos"
  run "$FZX" --resume "${dir##*/}"
  run fzf_bind load
  [ "$status" -eq 1 ]
}

@test "--resume -m :mode switches mode; a module name is rejected" {
  "$FZX" --keep -m counter
  local sid
  sid="$(basename "$(session_dirs)")"
  run "$FZX" --resume "$sid" -m :three
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = three ]
  [ "$(< "$FZX_RUNTIME_DIR/sessions/$sid/state/mode")" = three ]
  run "$FZX" --resume "$sid" -m counter:two
  [ "$status" -eq 2 ]
}

@test "--resume falls back to the first mode when the saved one no longer exists" {
  "$FZX" --keep -m counter:two
  local sid
  sid="$(basename "$(session_dirs)")"
  COUNTER_MODES="one three" run "$FZX" --resume "$sid"
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = one ]
  grep -q "saved mode 'two' no longer exists, using one" "$LOG"
}

@test "a child session's label shows the path from the root" {
  "$FZX" --keep -m counter:two
  local root child
  root="$(basename "$(session_dirs)")"
  run env FZX_SESSION="$root" "$FZX" _cb nav goto counter:three --x
  child="${output% -m*}"
  child="${child##* }"
  run "$FZX" --resume "$child" -m :three --dry-run
  [[ "$output" == *"'--border-label= counter:two > counter:three '"* ]]
}

@test "the owner removes child sessions with the root" {
  STUB_FZF_RUN="'$FZX' _cb nav goto counter --x > /dev/null" run "$FZX" -m counter
  [ "$status" -eq 0 ]
  [ -z "$(session_dirs)" ]
  grep -q "session destroyed (and 1 children)" "$LOG"
}

@test "the owner leaves other trees alone" {
  "$FZX" --keep -m counter
  local other
  other="$(session_dirs)"
  run "$FZX" -m counter
  [ "$(session_dirs)" = "$other" ]
}

@test "a resumed launch execs fzf; the owner runs it as a child" {
  local pid sid
  STUB_FZF_RUN='printf "%s" "$$" > "$BATS_TEST_TMPDIR/fzf.pid"'
  export STUB_FZF_RUN

  "$FZX" --keep -m counter &
  pid=$!
  wait "$pid"
  [ "$(< "$BATS_TEST_TMPDIR/fzf.pid")" != "$pid" ]

  sid="$(basename "$(session_dirs)")"
  "$FZX" --resume "$sid" &
  pid=$!
  wait "$pid"
  [ "$(< "$BATS_TEST_TMPDIR/fzf.pid")" = "$pid" ]
  grep -q "$sid .* fzf exec module=counter" "$LOG"
}

@test "per-module history by default; FZX_HISTORY=0 leaves fzf's history alone" {
  run "$FZX" -m counter
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --history=$FZX_STATE_DIR/history/counter "* ]]
  [ -d "$FZX_STATE_DIR/history" ]
  FZX_HISTORY=0 run "$FZX" -m counter
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --history="* ]]
}

@test "FZX_FZF_COLORS is passed as --color" {
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_FZF_COLORS="dark,hl:208"' > "$FZX_CONFIG_DIR/config.sh"
  run "$FZX" -m counter
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --color=dark,hl:208 "* ]]
}

@test "fzx config: unknown module fails with 2" {
  run "$FZX" config -m nope
  [ "$status" -eq 2 ]
}
