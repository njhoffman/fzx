#!/usr/bin/env bats
# modules/ps: scripts run standalone, and module.sh run directly without fzx

load test_helper

bats_require_minimum_version 1.5.0

PS_DIR="$(readlink -f "$BATS_TEST_DIRNAME/../modules/ps")"

setup() {
  setup_fzx
  # column positions are checked on the plain text; the colors have their own test
  export NO_COLOR=1
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
  # labels without their icons, so the lines start with them
  FZX_ICONS=none run "$PS_DIR/preview.sh" "$$"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ ^pid\ $$\ +parent\ [0-9]+\ .*user\ [a-z] ]]
  [[ "${lines[1]}" =~ ^state\ [A-Z].*threads\ [0-9]+.*started.*elapsed ]]
  [[ "${lines[2]}" =~ ^cpu\ .*%\ +mem\ .*rss\ [0-9.]+[KMG] ]]
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
  [[ "$output" == *$'children\n  '[0-9]*' sleep'* ]]
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

# stub <name> <body>: an executable on PATH recording its args in $BATS_TEST_TMPDIR/calls
stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${0##*/} $*" >> "$BATS_TEST_TMPDIR/calls"\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "actions: term on a process that is not yours goes through sudo -n; failing that, a message" {
  [[ "$EUID" -ne 0 ]] || skip "root signals every process"
  stub sudo 'exit 0'
  run "$PS_DIR/actions.sh" term 1
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "sudo -n kill -TERM -- 1" ]
  stub sudo 'exit 1'
  run --separate-stderr "$PS_DIR/actions.sh" term 1
  [ "$status" -eq 1 ]
  [ "$stderr" = "ps: 1: not yours (sudo-term or sudo-kill ask for the password)" ]
}

@test "actions: a pid that has exited fails without sudo" {
  stub sudo 'exit 0'
  sleep 0 &
  local pid=$!
  wait "$pid"
  run --separate-stderr "$PS_DIR/actions.sh" kill "$pid"
  [ "$status" -eq 1 ]
  [ "$stderr" = "ps: $pid: no such process" ]
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
}

@test "actions: sudo-term and sudo-kill ask sudo" {
  stub sudo 'exit 0'
  run "$PS_DIR/actions.sh" sudo-term 1 2
  [ "$status" -eq 0 ]
  run "$PS_DIR/actions.sh" sudo-kill 1
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "$(printf '%s\n' 'sudo kill -TERM -- 1 2' 'sudo kill -KILL -- 1')" ]
}

@test "actions: trace follows the first pid with strace (failing calls only with trace-errors)" {
  stub strace 'exit 0'
  stub sudo '"$@"'
  run "$PS_DIR/actions.sh" trace 1 2
  [ "$status" -eq 0 ]
  run "$PS_DIR/actions.sh" trace-errors 1
  [ "$status" -eq 0 ]
  # pid 1 is never yours: through sudo unless root
  if [[ "$EUID" -ne 0 ]]; then
    [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "$(printf '%s\n' 'sudo strace -f -p 1' 'strace -f -p 1' 'sudo strace -f -Z -p 1' 'strace -f -Z -p 1')" ]
  fi
}

@test "actions: trace without strace says so" {
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/empty" "$(command -v bash)" "$PS_DIR/actions.sh" trace "$$" < /dev/null
  [ "$status" -eq 1 ]
  [[ "$stderr" == "ps: strace is not installed"* ]]
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
  [[ "$(fzf_bind ctrl-x)" == "ctrl-x:execute-silent($dir/actions.sh term {+1})+change-prompt("*")+reload($dir/source.sh --ppid 1)" ]]
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
  [[ "$(fzf_bind ctrl-x)" == "ctrl-x:transform($FZX _cb notify term {+1})+change-prompt("*")+reload($FZX _cb source)" ]]
  [ "$(fzf_bind ctrl-o)" = "ctrl-o:transform:$FZX _cb nav goto ps --ppid {1}" ]
  [ "$(fzf_bind alt-o)" = "alt-o:transform:$FZX _cb nav goto network:files --pid {1}" ]
  [ "$(fzf_bind alt-t)" = "alt-t:execute($FZX _cb action trace {+1})" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --no-sort "* ]]
}

@test "under fzx: switching into or out of tree restarts fzf; user <-> all reloads in place" {
  load_libs log session
  fzx::session_create ps "$PS_DIR"
  printf '%s\0' user all tree > "$FZX_SESSION_DIR/meta/modes"
  run "$FZX" _cb mode next
  [[ "$output" == change-border-label*reload\(* ]]
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

@test "source: colored rows keep the plain text and its alignment; root, state, load and command parts" {
  # ps's layout: fixed-width columns, COMMAND at the same offset on every line
  local fmt='%5s %5s %-8s %4s %4s %7s %11s %-4s %-8s %s\n' table
  table="$(printf "$fmt" PID PPID USER %CPU %MEM RSS ELAPSED STAT TT COMMAND \
    101 1 root 0.0 0.1 2048 01:00 Ss '?' '/usr/sbin/sshd -D' \
    202 101 me 75.5 12.0 3145728 02:00 R pts/1 ' \_ /usr/bin/vim --clean notes.md' \
    303 2 root 0.0 0.0 0 03:00 I '?' '[kworker/0:1]')"
  run env -u NO_COLOR bash -c "source '$PS_DIR/source.sh'; USER=me ps::color 0 <<< \"\$1\"" _ "$table"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  # pid first; root red, sleeping dim, running green, high cpu and mem red, rss as M/G
  [[ "${lines[1]}" == $'\e[1;38;5;141m101'* && "${lines[1]}" == *$'\e[1;38;5;203mroot'* ]]
  [[ "${lines[2]}" == *$'\e[1;38;5;48mR'* && "${lines[2]}" == *$'\e[1;38;5;203m75.5'* && "${lines[2]}" == *"3.0G"* ]]
  # the command: tree branch dim, directory dim, name bold white, options blue
  [[ "${lines[2]}" == *$'\e[38;5;244m/usr/bin/\e[0m\e[1;38;5;255mvim\e[0m \e[38;5;110m--clean'* ]]
  local plain
  plain="$(sed 's/\x1b\[[0-9;:]*m//g' <<< "${lines[2]}")"
  [[ "$plain" =~ ^202\ +101\ me\ +75\.5\ 12\.0\ +3\.0G\ +02:00\ R\ +pts/1\ +\ \\_\ /usr/bin/vim\ --clean\ notes\.md$ ]]
  # kernel threads (parent 2) only with the toggle; then cyan
  run env -u NO_COLOR bash -c "source '$PS_DIR/source.sh'; USER=me ps::color 1 <<< \"\$1\" | tail -1" _ "$table"
  [[ "$output" == *$'\e[38;5;81m[kworker/0:1]'* ]]
}
