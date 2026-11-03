#!/usr/bin/env bats
# the systemd module: services, unit files, timers and sockets of both managers (systemctl stubbed)

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

stub_systemctl() {
  stub_cmd systemctl 'case "$*" in
    *--user*list-units*failed*) ;;
    *--user*list-units*) printf "u1.service loaded active running One\nu2.service loaded inactive dead Two\nghost.service not-found inactive dead ghost\n" ;;
    *--user*list-unit-files*) printf "u1.service enabled enabled\nu3.service disabled enabled\nu4.service static -\nt@.service disabled enabled\nu5.service masked enabled\n" ;;
    *list-unit-files*) ;;
    *--user*list-timers*) printf "[{\"next\":%s000000,\"left\":1,\"last\":%s000000,\"passed\":1,\"unit\":\"tick.timer\",\"activates\":\"tick.service\"},{\"next\":null,\"left\":null,\"last\":null,\"passed\":null,\"unit\":\"idle.timer\",\"activates\":\"idle.service\"}]\n" "$(($(date +%s) + 5400))" "$(($(date +%s) - 330))" ;; # mid-minute: a slow source reads now seconds earlier
    *list-timers*) printf "[{\"next\":%s000000,\"left\":1,\"last\":null,\"passed\":null,\"unit\":\"apt.timer\",\"activates\":\"apt.service\"}]\n" "$(($(date +%s) + 90000))" ;;
    *--user*list-sockets*) printf "[{\"listen\":\"/run/a\",\"unit\":\"a.socket\",\"activates\":\"a.service\"},{\"listen\":\"/run/a2\",\"unit\":\"a.socket\",\"activates\":\"a.service\"},{\"listen\":\"/run/b\",\"unit\":\"b.socket\",\"activates\":null}]\n" ;;
    *list-sockets*) printf "[]\n" ;;
    *show*Triggers*tick.timer) echo tick.service ;;
    *show*Triggers*) ;;
    *list-units*failed*) printf "s1.service loaded failed failed Broken thing\n" ;;
    *list-units*) printf "s1.service loaded failed failed Broken thing\ns2.service loaded active exited Done\n" ;;
    *) echo "systemctl $*" ;;
  esac'
}

@test "systemd: user and system modes; not-found units are dropped" {
  stub_systemctl
  run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "user:u1.service user:u2.service user:u3.service " ]
  FZX_MODE=system run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "system:s1.service system:s2.service " ]
  [[ "$(printf '%s' "${lines[0]}" | plain)" == *"s1.service"*"failed"*"Broken thing"* ]]
}

@test "systemd: unit files that are not loaded: enabled and disabled ones, the rest with the files toggle" {
  stub_systemctl
  run "$MODS/systemd/source.sh"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "${lines[2]}" | plain)" == *"u3.service"*"disabled"*"not loaded"* ]]
  [[ "$output" != *u4.service* && "$output" != *u5.service* && "$output" != *t@.service* ]]
  FZX_TOGGLES=files run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "user:u1.service user:u2.service user:u3.service user:u4.service user:u5.service " ]
  # by state the files that are not loaded come after inactive units
  stub_cmd systemctl 'case "$*" in *list-unit-files*) echo "a.service disabled enabled" ;; *) echo "b.service loaded inactive dead B" ;; esac'
  run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "user:a.service user:b.service " ]
  FZX_SORT=state run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "user:b.service user:a.service " ]
}

@test "systemd: timers of both managers with next and last run; by state the next run first" {
  stub_systemctl
  FZX_MODE=timers run --separate-stderr "$MODS/systemd/source.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "system:apt.timer user:idle.timer user:tick.timer " ]
  local tick
  tick="$(printf '%s\n' "${lines[2]}" | plain)"
  [[ "$tick" == *"user"*"tick.timer"*"in 1h"*"5m ago"*"tick.service"* ]]
  [[ "$(printf '%s\n' "${lines[1]}" | plain)" == *"idle.timer"*" - "*"never"* ]]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"system"*"apt.timer"*"in 1d"* ]]
  FZX_MODE=timers FZX_SORT=state run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "user:tick.timer system:apt.timer user:idle.timer " ]
}

@test "systemd: sockets list each socket once, its addresses joined" {
  stub_systemctl
  FZX_MODE=sockets run "$MODS/systemd/source.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "user:a.socket user:b.socket " ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"a.socket"*"/run/a, /run/a2"*"a.service"* ]]
}

@test "systemd: reload is reload-or-restart; daemon-reload once per manager; a timer's journal is its service's" {
  stub_systemctl
  stub_cmd sudo '"$@"'
  stub_cmd journalctl ':'
  run "$MODS/systemd/actions.sh" reload user:u1.service
  [ "$status" -eq 0 ]
  run "$MODS/systemd/actions.sh" daemon-reload user:u1.service user:u2.service system:s1.service
  [ "$status" -eq 0 ]
  run "$MODS/systemd/actions.sh" journal user:tick.timer
  [ "$status" -eq 0 ]
  run "$MODS/systemd/actions.sh" journal user:u1.service
  run grep -v '^.*/sudo ' "$BATS_TEST_TMPDIR/calls"
  run cut -d' ' -f2- <<< "$output"
  [ "${lines[0]}" = "--user reload-or-restart -- u1.service" ]
  [ "${lines[1]}" = "--system daemon-reload" ]
  [ "${lines[2]}" = "--user daemon-reload" ]
  [ "${lines[3]}" = "--user show -p Triggers --value -- tick.timer" ]
  [ "${lines[4]}" = "--user -u tick.service -n 100 -f" ]
  [ "${lines[5]}" = "--user -u u1.service -n 100 -f" ]
}

@test "systemd: failed mode collects failed units of both managers" {
  stub_systemctl
  FZX_MODE=failed run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "system:s1.service " ]
}

@test "systemd: actions use sudo only for system units" {
  stub_systemctl
  stub_cmd sudo '"$@"'
  run "$MODS/systemd/actions.sh" restart user:u1.service system:s1.service
  [ "$status" -eq 0 ]
  run cut -d' ' -f2- "$BATS_TEST_TMPDIR/calls"
  [ "${lines[0]}" = "--user restart -- u1.service" ]
  [ "${lines[1]}" = "systemctl --system restart -- s1.service" ]
  [ "${lines[2]}" = "--system restart -- s1.service" ]
}

@test "systemd: bad ids and unknown actions fail with 2" {
  run "$MODS/systemd/actions.sh" start
  [ "$status" -eq 2 ]
  run "$MODS/systemd/actions.sh" start nginx.service
  [ "$status" -eq 2 ]
  run "$MODS/systemd/actions.sh" explode user:u1.service
  [ "$status" -eq 2 ]
  run "$MODS/systemd/preview.sh" nginx.service
  [ "$status" -eq 1 ]
}

@test "systemd: every action key is bound and listed in the header" {
  stub_fzf
  run "$FZX" -m systemd
  [[ "$(fzf_bind alt-R)" == "alt-R:execute($FZX _cb action restart {+1})+change-prompt("*")+reload($FZX _cb source)" ]]
  [ "$(fzf_bind ctrl-l)" = "ctrl-l:execute($FZX _cb action journal {+1})" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=alt-s start  ctrl-x stop  alt-R restart  alt-L reload  alt-e enable  alt-d disable  ctrl-l journal  ctrl-e edit "* ]]
}

@test "systemd: by name, or by state (failed, running, other active, inactive), the sorted column underlined" {
  stub_cmd systemctl 'printf "a.service loaded inactive dead A\nb.service loaded active running B\nc.service loaded failed failed C\n"'
  run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f2 | tr '\n' ' ')" = "a.service b.service c.service " ]
  [[ "${lines[0]}" == *$'\e[4ma.service\e[0m'* ]]
  FZX_SORT=state run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f2 | tr '\n' ' ')" = "c.service b.service a.service " ]
  [[ "${lines[0]}" == *$'\e[38;5;244m\e[4mfailed\e[0m'* ]]
}

@test "systemd: a header row (FZX_SORTED_SHOW=header) names the columns over the rows, the sorted one marked" {
  stub_cmd systemctl 'printf "a.service loaded inactive dead A\nb.service loaded active running B\n"'
  FZX_SORTED_SHOW=header FZX_SORT_HEADER=1 FZX_SORT=state FZX_SORTED_ARROWS='^ v' run "$MODS/systemd/source.sh"
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == $'\t\t'*UNIT*$'\e[1;38;2;0;215;255mSTATE^\e[0m'*DESCRIPTION && "${lines[1]}" != *$'\e[4m'* ]]
  header_aligned 2 "${lines[0]}" UNIT "${lines[1]}" b.service
  header_aligned 2 "${lines[0]}" DESCRIPTION "${lines[1]}" B
  # without a header row in the view, none
  FZX_SORTED_SHOW=header run "$MODS/systemd/source.sh"
  [ "${#lines[@]}" -eq 2 ]
}

@test "systemd: an unknown mode fails with 2" {
  stub_systemctl
  FZX_MODE=bogus run --separate-stderr "$MODS/systemd/source.sh"
  [ "$status" -eq 2 ]
  [ "$stderr" = "systemd: unknown mode: bogus" ]
}

@test "systemd: preview is the unit's status, in color, from its manager" {
  stub_systemctl
  run "$MODS/systemd/preview.sh" system:s1.service
  [ "$status" -eq 0 ]
  [ "$output" = "systemctl --system status --no-pager --lines=20 -- s1.service" ]
  stub_cmd systemctl 'echo "colors=$SYSTEMD_COLORS"'
  run "$MODS/systemd/preview.sh" user:u1.service
  [ "$output" = "colors=1" ]
}

@test "systemd: start, stop, enable and disable act on each unit, user ones without sudo" {
  stub_systemctl
  stub_cmd sudo '"$@"'
  local a
  for a in start stop enable disable; do
    run "$MODS/systemd/actions.sh" "$a" user:u1.service user:u2.service
    [ "$status" -eq 0 ]
  done
  [ "$(cut -d' ' -f2- "$BATS_TEST_TMPDIR/calls" | tr '\n' '|')" = "--user start -- u1.service|--user start -- u2.service|--user stop -- u1.service|--user stop -- u2.service|--user enable -- u1.service|--user enable -- u2.service|--user disable -- u1.service|--user disable -- u2.service|" ]
  [[ "$(cat "$BATS_TEST_TMPDIR/calls")" != *sudo* ]]
}

@test "systemd: a failing unit fails the action, the rest still run" {
  stub_cmd systemctl '[[ "$*" == *bad.service ]] && exit 5; exit 0'
  run "$MODS/systemd/actions.sh" restart user:bad.service user:good.service
  [ "$status" -eq 5 ]
  [[ "$(cat "$BATS_TEST_TMPDIR/calls")" == *good.service* ]]
}

@test "systemd: edit goes through sudo for a system unit; a socket that activates nothing follows its own journal" {
  [[ "$EUID" -ne 0 ]] || skip "root needs no sudo"
  stub_systemctl
  stub_cmd sudo '"$@"'
  stub_cmd journalctl ':'
  run "$MODS/systemd/actions.sh" edit system:s1.service
  run "$MODS/systemd/actions.sh" edit user:u1.service
  run "$MODS/systemd/actions.sh" journal user:b.socket
  [ "$status" -eq 0 ]
  run cut -d' ' -f2- "$BATS_TEST_TMPDIR/calls"
  [ "${lines[0]}" = "systemctl --system edit -- s1.service" ]
  [ "${lines[1]}" = "--system edit -- s1.service" ]
  [ "${lines[2]}" = "--user edit -- u1.service" ]
  [ "${lines[3]}" = "--user show -p Triggers --value -- b.socket" ]
  [ "${lines[4]}" = "--user -u b.socket -n 100 -f" ]
}

@test "systemd: entries apply on systemd hosts; failed only when something failed; summaries count units" {
  [[ -d /run/systemd/system ]] || skip "not a systemd host"
  load_libs log config menu
  fzx::menu_entries systemd "$FZX_REPO/modules/systemd"
  stub_cmd systemctl 'case "$*" in
    *--failed*) ;;
    *--system*list-timers*) printf "a.timer\nb.timer\n" ;;
    *--user*list-timers*) printf "c.timer\n" ;;
    *--system*list-sockets*) printf "/run/a a.socket a.service\n" ;;
    *list-sockets*) ;;
    *--state=running*) printf "x.service\ny.service\n" ;;
    *--state=failed*) printf "z.service\n" ;;
  esac'
  systemd::applicable systemd
  systemd::applicable systemd:timers
  run systemd::applicable systemd:failed
  [ "$status" -ne 0 ]
  [ "$(systemd::summary systemd)" = "2 running, 1 failed" ]
  [ "$(systemd::summary systemd:timers)" = "2 system, 1 user" ]
  [ "$(systemd::summary systemd:sockets)" = "1 system, 0 user" ]
  [ -z "$(systemd::summary systemd:failed)" ]
  stub_cmd systemctl 'case "$*" in *--user*--failed*) echo "f.service loaded failed failed F" ;; esac'
  systemd::applicable systemd:failed
}

@test "systemd: the files toggle and the sorts are bound under fzx; enter prints unit names" {
  stub_fzf
  run "$FZX" -m systemd
  [ "$status" -eq 0 ]
  [[ "$(fzf_bind alt-u)" == *'_cb toggle files'* ]]
  [[ "$(fzf_bind alt-L)" == *'_cb action reload {+1}'* ]]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=2 "* && " ${FZF_ARGS[*]} " == *" --with-nth=3 "* ]]
}
