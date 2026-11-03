#!/usr/bin/env bats
# the logs module: files, unit journals and docker logs (systemctl, journalctl and docker stubbed)

load test_helper

bats_require_minimum_version 1.5.0

MODS="$(readlink -f "$BATS_TEST_DIRNAME/../modules")"

setup() {
  setup_fzx
}

# stub_cmd <name> <body>: an executable on PATH that runs <body> with its args in "$@"
stub_cmd() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0 $*" >> "$BATS_TEST_TMPDIR/calls"\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

plain() { sed 's/\x1b\[[0-9;:]*m//g'; }

# summary <module> <target>: the module's summary, its config and manifest loaded as the menu does
summary() {
  load_libs log config menu
  fzx::menu_entries "$1" "$FZX_REPO/modules/$1"
  "$1::summary" "${@:2}"
}

@test "logs: files from config and globs, newest first, missing ones skipped" {
  mkdir -p "$FZX_CONFIG_DIR/modules/logs" "$BATS_TEST_TMPDIR/logs"
  echo old > "$BATS_TEST_TMPDIR/logs/old.log"
  touch -d '2 days ago' "$BATS_TEST_TMPDIR/logs/old.log"
  echo new > "$BATS_TEST_TMPDIR/logs/new.log"
  echo named > "$BATS_TEST_TMPDIR/named.txt"
  cat > "$FZX_CONFIG_DIR/modules/logs/config.sh" << CFG
FZX_LOGS_FILES=([named]="$BATS_TEST_TMPDIR/named.txt" [missing]=/no/such.log)
FZX_LOGS_GLOBS=("$BATS_TEST_TMPDIR/logs/*.log")
CFG
  touch -d '1 hour ago' "$BATS_TEST_TMPDIR/named.txt"
  FZX_ICONS=unicode run "$MODS/logs/source.sh"
  [ "${#lines[@]}" -eq 3 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1,2 | tr '\t\n' ' |')" = "file $BATS_TEST_TMPDIR/logs/new.log|file $BATS_TEST_TMPDIR/named.txt|file $BATS_TEST_TMPDIR/logs/old.log|" ]
  [[ "$(printf '%s' "${lines[2]}" | plain)" == *"  2d  ● ▤ old "* ]]
}

@test "logs: units mode lists running and failed services of both managers" {
  stub_cmd systemctl 'case "$*" in --user*) printf "a.service loaded active running User thing\n" ;; *) printf "b.service loaded failed failed System thing\n" ;; esac'
  FZX_MODE=units run "$MODS/logs/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1,2 | tr '\t\n' ' |')" = "unit-user a.service|unit-system b.service|" ]
  [[ "$(printf '%s' "${lines[1]}" | plain)" == *"system b.service"*"System thing"* ]]
}

@test "logs: docker mode, and nothing when docker is unavailable" {
  stub_cmd docker 'printf "abc123\tweb\tnginx:1\tUp 2 hours\n"'
  FZX_MODE=docker run "$MODS/logs/source.sh"
  [ "$(printf '%s' "$output" | cut -f1,2)" = $'docker\tabc123' ]
  stub_cmd docker 'echo "Cannot connect" >&2; exit 1'
  FZX_MODE=docker run --separate-stderr "$MODS/logs/source.sh"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "logs: preview and follow use the right tool per kind" {
  stub_cmd journalctl 'echo journal'
  stub_cmd docker 'echo docker'
  stub_cmd systemctl ':'
  export FZX_LOGS_PREVIEW_FOLLOW=0
  printf 'l1\nl2\n' > "$BATS_TEST_TMPDIR/x.log"
  run "$MODS/logs/preview.sh" file "$BATS_TEST_TMPDIR/x.log"
  [[ "$(printf '%s' "$output" | plain)" == *l2* ]]
  run "$MODS/logs/preview.sh" unit-system foo.service
  run "$MODS/logs/preview.sh" docker abc
  run "$MODS/logs/actions.sh" follow unit-user bar.service
  [ "$(grep -v /systemctl "$BATS_TEST_TMPDIR/calls" | cut -d' ' -f2- | tr '\n' '|')" = "--system -u foo.service -n 200 --no-pager|logs --tail 200 abc|--user -u bar.service -n 200 --no-pager -f|" ]
  run "$MODS/logs/preview.sh" bogus x
  [ "$status" -eq 2 ]
}

@test "logs: opts bind follow and accept the target" {
  stub_fzf
  run "$FZX" -m logs:units
  [ "$(fzf_bind alt-F)" = "alt-F:execute($FZX _cb action follow {1} {2})" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=2 "* ]]
}

@test "logs: files sort by size or name; the sorted column is underlined" {
  mkdir -p "$FZX_CONFIG_DIR/modules/logs" "$BATS_TEST_TMPDIR/logs"
  head -c 5000 /dev/zero > "$BATS_TEST_TMPDIR/logs/big.log"
  touch -d '2 days ago' "$BATS_TEST_TMPDIR/logs/big.log"
  echo a > "$BATS_TEST_TMPDIR/logs/abc.log"
  printf 'FZX_LOGS_FILES=()\nFZX_LOGS_GLOBS=("%s/logs/*.log")\n' "$BATS_TEST_TMPDIR" > "$FZX_CONFIG_DIR/modules/logs/config.sh"
  run "$MODS/logs/source.sh"
  [[ "${lines[0]}" == *abc.log* && "${lines[0]}" =~ $'\e[38;5;46;4m'[0-9]+s ]]
  FZX_SORT=size run "$MODS/logs/source.sh"
  [[ "${lines[0]}" == *big.log* && "${lines[0]}" == *$'\e[38;5;152;4m4K\e[0m'* ]]
  FZX_SORT=name run "$MODS/logs/source.sh"
  [[ "${lines[0]}" == *abc.log* && "${lines[0]}" == *$'\e[4mabc\e[0m'* && "${lines[1]}" == *big.log* ]]
}


@test "logs: a header row (FZX_SORTED_SHOW=header) over the files, the sorted one marked, with or without the dot" {
  mkdir -p "$FZX_CONFIG_DIR/modules/logs" "$BATS_TEST_TMPDIR/logs"
  head -c 5000 /dev/zero > "$BATS_TEST_TMPDIR/logs/big.log"
  printf 'FZX_LOGS_FILES=()\nFZX_LOGS_GLOBS=("%s/logs/*.log")\n' "$BATS_TEST_TMPDIR" > "$FZX_CONFIG_DIR/modules/logs/config.sh"
  export FZX_SORTED_SHOW=header FZX_SORT_HEADER=1 FZX_SORTED_ARROWS='^ v'
  FZX_SORT=size FZX_SORT_DESC=1 run "$MODS/logs/source.sh"
  [[ "${lines[0]}" == $'\t\t'*'AGE  '*NAME*$'\e[1;38;2;0;215;255mSIZEv\e[0m PATH' && "${lines[1]}" != *';4m'* ]]
  header_aligned 2 "${lines[0]}" NAME "${lines[1]}" big
  header_aligned 2 "${lines[0]}" PATH "${lines[1]}" "${BATS_TEST_TMPDIR:0:1}"
  FZX_LOGS_AGE_DOT="" FZX_ICONS=none run "$MODS/logs/source.sh"
  [[ "${lines[0]}" == *$'\e[1;38;2;0;215;255mAGE^\e[0m'* ]]
  header_aligned 2 "${lines[0]}" NAME "${lines[1]}" big
}

@test "logs: an unknown mode fails with 2" {
  FZX_MODE=bogus run --separate-stderr "$MODS/logs/source.sh"
  [ "$status" -eq 2 ]
  [ "$stderr" = "logs: unknown mode: bogus" ]
}

@test "logs: follow tails a file by name (-F), a container with -f; an unknown kind fails" {
  stub_cmd tail ':'
  stub_cmd docker ':'
  FZX_LOGS_LINES=50 run "$MODS/logs/actions.sh" follow file /var/log/x.log
  [ "$status" -eq 0 ]
  run "$MODS/logs/actions.sh" follow docker abc
  [ "$(cut -d' ' -f2- "$BATS_TEST_TMPDIR/calls" | tr '\n' '|')" = "-n 50 -F -- /var/log/x.log|logs --tail 200 -f abc|" ]
  run "$MODS/logs/actions.sh" follow bogus x
  [ "$status" -eq 0 ]
  run "$MODS/logs/actions.sh" explode file x
  [ "$status" -eq 2 ]
}

@test "logs: entries apply when their tool is there; summaries count files, failed units and containers" {
  mkdir -p "$FZX_CONFIG_DIR/modules/logs" "$BATS_TEST_TMPDIR/logs"
  echo a > "$BATS_TEST_TMPDIR/logs/a.log"
  echo b > "$BATS_TEST_TMPDIR/logs/b.log"
  printf 'FZX_LOGS_FILES=()\nFZX_LOGS_GLOBS=("%s/logs/*.log")\n' "$BATS_TEST_TMPDIR" > "$FZX_CONFIG_DIR/modules/logs/config.sh"
  stub_cmd systemctl 'printf "x.service loaded failed failed X\ny.service loaded failed failed Y\n"'
  stub_cmd docker 'printf "c1\nc2\nc3\n"'
  stub_cmd journalctl ':'
  load_libs log config menu
  fzx::menu_entries logs "$FZX_REPO/modules/logs"
  logs::applicable logs
  logs::applicable logs:units
  logs::applicable logs:docker
  (PATH=/nonexistent; ! logs::applicable logs:docker && ! logs::applicable logs:units)
  [ "$(logs::summary logs)" = "2 log files" ]
  [ "$(logs::summary logs:units)" = "2 failed system units" ]
  [ "$(logs::summary logs:docker)" = "3 running containers" ]
}

@test "logs: actions get the kind and the target; copy takes the targets; the preview follows the end" {
  stub_fzf
  run "$FZX" -m logs
  [ "$status" -eq 0 ]
  [[ "$(fzf_bind 'ctrl-\')" == *'goto actions follow,view {1} {2} --fzx-- copy {+2} --fzx--'* ]]
  [ "$(fzf_flag --preview)" = "$FZX _cb preview {1} {2}" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --with-nth=3 "* && " ${FZF_ARGS[*]} " == *" --tiebreak=index "* ]]
  [[ " ${FZF_ARGS[*]} " == *"follow,nowrap"* ]]
}

@test "logs: the preview follows the log by default: tail -F, journalctl -f, docker logs -f" {
  stub_cmd tail ':'
  stub_cmd journalctl ':'
  stub_cmd docker ':'
  stub_cmd systemctl ':'
  run "$MODS/logs/preview.sh" file /var/log/x.log
  run "$MODS/logs/preview.sh" unit-user a.service
  run "$MODS/logs/preview.sh" docker abc
  [ "$(grep -v /systemctl "$BATS_TEST_TMPDIR/calls" | cut -d' ' -f2- | tr '\n' '|')" = "-n 200 -F -- /var/log/x.log|--user -u a.service -n 200 --no-pager -f|logs --tail 200 -f abc|" ]
}

@test "logs: files and containers go through the colorizer, journals do not; none or NO_COLOR: plain" {
  stub_cmd ccze 'sed "s/^/CZ:/"'
  stub_cmd journalctl 'echo journal'
  stub_cmd docker 'echo docker'
  stub_cmd systemctl ':'
  export FZX_LOGS_PREVIEW_FOLLOW=0
  printf 'l1\n' > "$BATS_TEST_TMPDIR/x.log"
  run "$MODS/logs/preview.sh" file "$BATS_TEST_TMPDIR/x.log"
  [ "$output" = "CZ:l1" ]
  run "$MODS/logs/preview.sh" docker abc
  [ "$output" = "CZ:docker" ]
  run "$MODS/logs/preview.sh" unit-system foo.service
  [[ "$output" == *journal && "$output" != *CZ:* ]]
  grep -q '/ccze -A$' "$BATS_TEST_TMPDIR/calls"
  # following, the colorizer still applies (the action, and the preview by default)
  stub_cmd tail 'echo followed'
  run "$MODS/logs/actions.sh" follow file /var/log/x.log
  [ "$output" = "CZ:followed" ]
  NO_COLOR=1 run "$MODS/logs/preview.sh" docker abc
  [ "$output" = docker ]
  # an empty array: none
  run bash -c "FZX_LOGS_COLORIZER=(); source '$MODS/logs/preview.sh'; logs::preview docker abc"
  [ "$output" = docker ]
  # a colorizer that is not installed: plain
  run bash -c "FZX_LOGS_COLORIZER=(no-such-colorizer); source '$MODS/logs/preview.sh'; logs::preview docker abc"
  [ "$output" = docker ]
}

@test "logs: a unit's preview pins the top of its status, without the process tree, above the journal" {
  stub_cmd systemctl 'printf "%s\n" "● a.service - A" "     Loaded: loaded" " Invocation: 123" "     Active: active" "     CGroup: /a" "             ├─1 /bin/a" "             └─2 /bin/b"'
  stub_cmd journalctl 'echo journal'
  export FZX_LOGS_PREVIEW_FOLLOW=0 FZF_PREVIEW_COLUMNS=10
  run "$MODS/logs/preview.sh" unit-user a.service
  [ "$status" -eq 0 ]
  # 8 status lines (padded), the rule, then the journal
  [ "${#lines[@]}" -eq 6 ] # run drops the padding's empty lines from lines[]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 10 ]
  [ "${lines[0]}" = "● a.service - A" ] && [ "${lines[2]}" = "     Active: active" ] && [ "${lines[3]}" = "     CGroup: /a" ]
  [ "$(printf '%s' "${lines[4]}" | plain)" = "──────────" ]
  [ "${lines[5]}" = journal ]
  grep -q 'systemctl --user status a.service --no-pager -n 0' "$BATS_TEST_TMPDIR/calls"
  FZX_LOGS_STATUS_LINES=2 run "$MODS/logs/preview.sh" unit-user a.service
  [ "${#lines[@]}" -eq 4 ] && [ "${lines[1]}" = "     Loaded: loaded" ] && [ "${lines[3]}" = journal ]
}

@test "logs: units pins the status lines in the preview and restarts fzf; files do not pin" {
  stub_fzf
  run "$FZX" -m logs:units
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *"--preview-window=down,60%,follow,nowrap,nohidden,~9 "* ]]
  run "$FZX" -m logs
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *"--preview-window=down,60%,follow,nowrap,nohidden "* ]]
  load_libs log session
  fzx::session_create logs "$MODS/logs"
  printf '%s\0' files units docker > "$FZX_SESSION_DIR/meta/modes"
  run "$FZX" _cb mode next
  [ "$output" = "become:$FZX --resume $FZX_SESSION -m :units" ]
}

@test "logs: a dot before each file in its age's color; FZX_LOGS_AGE_DOT empty leaves it out" {
  mkdir -p "$FZX_CONFIG_DIR/modules/logs" "$BATS_TEST_TMPDIR/logs"
  local f
  for f in new hour day old; do echo x > "$BATS_TEST_TMPDIR/logs/$f.log"; done
  touch -d '5 minutes ago' "$BATS_TEST_TMPDIR/logs/hour.log"
  touch -d '3 hours ago' "$BATS_TEST_TMPDIR/logs/day.log"
  touch -d '3 days ago' "$BATS_TEST_TMPDIR/logs/old.log"
  printf 'FZX_LOGS_FILES=()\nFZX_LOGS_GLOBS=("%s/logs/*.log")\n' "$BATS_TEST_TMPDIR" > "$FZX_CONFIG_DIR/modules/logs/config.sh"
  run "$MODS/logs/source.sh"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *new.log* && "${lines[0]}" == *$'\e[38;5;46m●\e[0m '* ]]
  [[ "${lines[1]}" == *hour.log* && "${lines[1]}" == *$'\e[38;5;34m●\e[0m '* ]]
  [[ "${lines[2]}" == *day.log* && "${lines[2]}" == *$'\e[38;5;28m●\e[0m '* ]]
  [[ "${lines[3]}" == *old.log* && "${lines[3]}" == *$'\e[38;5;240m●\e[0m '* ]]
  echo 'FZX_LOGS_AGE_DOT=""' >> "$FZX_CONFIG_DIR/modules/logs/config.sh"
  run "$MODS/logs/source.sh"
  [[ "${lines[0]}" == *new.log* && "${lines[0]}" != *●* ]]
}

@test "logs: a followed preview stops once its row loses focus or fzf stops answering; the follow action is not watched" {
  local log="$BATS_TEST_TMPDIR/quiet-$$.log" focus="$BATS_TEST_TMPDIR/focus.json" pid
  echo first > "$log"
  # fzf's socket: the focused row from focus.json; no file, no answer
  stub_cmd curl '[[ -f "'"$focus"'" ]] || exit 7; cat "'"$focus"'"'
  printf '{"current":{"text":"file\\t%s\\tquiet"}}' "$log" > "$focus"
  export FZF_SOCK="$BATS_TEST_TMPDIR/fzf.sock" FZX_LOGS_FOLLOW_CHECK=0.2
  "$MODS/logs/preview.sh" file "$log" > "$BATS_TEST_TMPDIR/out" &
  pid=$!
  sleep 1
  # still focused: still following
  kill -0 "$pid"
  pgrep -f "tail -n 200 -F -- $log" > /dev/null
  printf '{"current":{"text":"file\\t/var/log/other\\tother"}}' > "$focus"
  local i
  for ((i = 0; i < 30; i++)); do kill -0 "$pid" 2> /dev/null || break; sleep 0.1; done
  ! kill -0 "$pid" 2> /dev/null
  ! pgrep -f "tail -n 200 -F -- $log"
  [[ "$(plain < "$BATS_TEST_TMPDIR/out")" == first* ]]
  # fzf gone (become, exit): the socket stops answering
  printf '{"current":{"text":"file\\t%s\\tquiet"}}' "$log" > "$focus"
  "$MODS/logs/preview.sh" file "$log" > /dev/null &
  pid=$!
  sleep 0.6
  rm "$focus"
  for ((i = 0; i < 30; i++)); do kill -0 "$pid" 2> /dev/null || break; sleep 0.1; done
  ! kill -0 "$pid" 2> /dev/null
  ! pgrep -f "tail -n 200 -F -- $log"
  # the follow action (execute: fzf cannot answer meanwhile) is never stopped by the watcher
  "$MODS/logs/actions.sh" follow file "$log" > /dev/null &
  pid=$!
  sleep 1
  kill -0 "$pid"
  pkill -f "tail -n 200 -F -- $log" || :
  wait "$pid" || :
}
