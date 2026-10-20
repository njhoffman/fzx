#!/usr/bin/env bats
# modules/ps: scripts run standalone, and module.sh run directly without fzx

load test_helper

PS_DIR="$(readlink -f "$BATS_TEST_DIRNAME/../modules/ps")"

setup() {
  setup_fzx
}

@test "source: header first, then rows starting with a left-aligned pid" {
  run "$PS_DIR/source.sh"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ ^PID\ +PPID\ +USER ]]
  [[ "${lines[1]}" =~ ^[0-9]+\ +[0-9]+\  ]]
}

@test "source: right-aligned columns still end under their header" {
  run "$PS_DIR/source.sh"
  local prefix="${lines[0]%%PPID*}PPID" i
  local end="${#prefix}"
  for ((i = 1; i < ${#lines[@]}; i++)); do
    [[ "${lines[i]:end-1:2}" =~ ^[0-9]\ $ ]]
  done
}

@test "source: user mode (the default) shows only own processes; all mode includes pid 1" {
  run "$PS_DIR/source.sh"
  [[ "$output" != *$'\n1 '* ]] || [ "$(id -u)" -eq 0 ]
  FZX_MODE=user run "$PS_DIR/source.sh"
  [[ "$output" != *$'\n1 '* ]] || [ "$(id -u)" -eq 0 ]
  FZX_MODE=all run "$PS_DIR/source.sh"
  [[ "$output" == *$'\n1 '* ]]
}

@test "source: tree mode prints the process forest" {
  FZX_MODE=tree run "$PS_DIR/source.sh"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ ^PID ]]
  [[ "$output" == *'\_ '* ]]
}

@test "source: unknown mode fails with 2" {
  FZX_MODE=nine run "$PS_DIR/source.sh"
  [ "$status" -eq 2 ]
}

@test "source: --ppid lists only direct children" {
  bash -c 'sleep 30 & sleep 31 & wait' &
  local parent=$! i
  for ((i = 0; i < 50; i++)); do
    [[ "$(cat /proc/"$parent"/task/*/children 2> /dev/null | wc -w)" -eq 2 ]] && break
    sleep 0.05
  done
  run "$PS_DIR/source.sh" --ppid "$parent"
  pkill -P "$parent" sleep
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[1]}" =~ ^[0-9]+\ +$parent\  ]]
  [[ "${lines[2]}" =~ ^[0-9]+\ +$parent\  ]]
}

@test "source: --ppid needs a numeric pid" {
  run "$PS_DIR/source.sh" --ppid
  [ "$status" -eq 2 ]
  run "$PS_DIR/source.sh" --ppid abc
  [ "$status" -eq 2 ]
}

@test "source: unknown argument fails with 2" {
  run "$PS_DIR/source.sh" --bogus
  [ "$status" -eq 2 ]
}

@test "preview: shows details for a live pid" {
  run "$PS_DIR/preview.sh" "$$"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ PID.*STARTED ]]
  [[ "$output" == *"$$"* ]]
}

@test "preview: lists direct children" {
  bash -c 'sleep 30 & wait' &
  local parent=$! i
  for ((i = 0; i < 50; i++)); do
    [[ -n "$(cat /proc/"$parent"/task/*/children 2> /dev/null)" ]] && break
    sleep 0.05
  done
  run "$PS_DIR/preview.sh" "$parent"
  pkill -P "$parent" sleep
  [[ "$output" == *$'children:\n  '[0-9]*' sleep'* ]]
}

@test "preview: non-numeric input fails, exited pid is reported" {
  run "$PS_DIR/preview.sh" "PID"
  [ "$status" -eq 1 ]
  [ "$output" = "not a pid: PID" ]
  sleep 0 &
  local pid=$!
  wait "$pid"
  run "$PS_DIR/preview.sh" "$pid"
  [ "$status" -eq 0 ]
  [ "$output" = "process $pid has exited" ]
}

@test "actions: term signals the process" {
  sleep 30 &
  local pid=$!
  run "$PS_DIR/actions.sh" term "$pid"
  [ "$status" -eq 0 ]
  run wait "$pid"
  [ "$status" -eq 143 ]
}

@test "actions: rejects missing pids, bad pids and unknown actions" {
  run "$PS_DIR/actions.sh" term
  [ "$status" -eq 2 ]
  run "$PS_DIR/actions.sh" term 12abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a pid: 12abc"* ]]
  run "$PS_DIR/actions.sh" explode "$$"
  [ "$status" -eq 2 ]
}

@test "module.sh run directly: calls the scripts, no session or fzx callbacks" {
  stub_fzf
  STUB_FZF_OUT=123 run "$PS_DIR/module.sh" --ppid 1
  [ "$status" -eq 0 ]
  [ "$output" = 123 ]
  local dir="$PS_DIR" key
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = user ]
  [ "$(fzf_bind start)" = "start:reload:$dir/source.sh --ppid 1" ]
  [ "$(fzf_flag --preview)" = "$dir/preview.sh {1}" ]
  [ "$(fzf_bind ctrl-x)" = "ctrl-x:execute-silent($dir/actions.sh term {+1})+reload($dir/source.sh --ppid 1)" ]
  for key in alt-r alt-left alt-0 ctrl-o; do
    run fzf_bind "$key"
    [ "$status" -eq 1 ]
  done
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --listen"* ]]
  [ -z "$(< "$BATS_TEST_TMPDIR/fzf.session")" ]
  [ -z "$(session_dirs)" ]
}

@test "module.sh run directly: FZX_MODE picks the mode; unknown modes fail with 2" {
  stub_fzf
  FZX_MODE=tree run "$PS_DIR/module.sh"
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --no-sort "* ]]
  FZX_MODE=nine run "$PS_DIR/module.sh"
  [ "$status" -eq 2 ]
}

@test "under fzx: ps binds route through callbacks" {
  stub_fzf
  run "$FZX" -m ps
  [ "$status" -eq 0 ]
  [ "$(fzf_flag --preview)" = "$FZX _cb preview {1}" ]
  [ "$(fzf_bind ctrl-x)" = "ctrl-x:execute-silent($FZX _cb action term {+1})+reload($FZX _cb source)" ]
  [ "$(fzf_bind ctrl-o)" = "ctrl-o:transform:$FZX _cb nav goto ps --ppid {1}" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --no-sort "* ]]
}

@test "under fzx: switching into or out of tree restarts fzf; user <-> all reloads in place" {
  load_libs log session
  fzx::session_create ps "$PS_DIR"
  printf '%s\0' user all tree > "$FZX_SESSION_DIR/meta/modes"
  run "$FZX" _cb mode next
  [[ "$output" == change-border-label*reload:* ]]
  run "$FZX" _cb mode next
  [ "$output" = "become:$FZX --resume $FZX_SESSION -m :tree" ]
}

@test "under fzx: load callback produces ps output and caches it" {
  load_libs log session
  fzx::session_create ps "$PS_DIR"
  printf '%s\0' user all tree > "$FZX_SESSION_DIR/meta/modes"
  run "$FZX" _cb load
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ ^PID ]]
  # the cache key carries toggles and sort: mode "user", no toggles on, sort cpu
  [ -s "$FZX_SESSION_DIR/data/user+@cpu" ]
}

@test "source: --ppid of a process without children prints only the header" {
  sleep 30 &
  local pid=$!
  run "$PS_DIR/source.sh" --ppid "$pid"
  kill "$pid"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" =~ ^PID ]]
}
