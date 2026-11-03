#!/usr/bin/env bash
# bluetooth scan: keeps bluez discovering and reloads the list as devices appear, while the all mode's scan
# toggle is on. Started detached by the source (bluetooth::scan_control), which also stops it on any load
# where the toggle is off or another mode shows; it ends by itself once fzf's socket stops answering or its
# pid file names another scanner.
#   scan.sh <fzf socket> <pid file> <reload action>
# Discovery lasts as long as a `bluetoothctl scan on` client runs: one runs for FZX_BLUETOOTH_SCAN_RUN
# seconds (60) and is started again, so a scanner killed hard leaves discovery on a minute at most. Its
# "[NEW] Device" and "[DEL] Device" lines are the events (watching the bus itself needs root); reloads come
# at most once a second.

bluetooth::_fzf() {
  command curl -s -m 2 --unix-socket "$1" "${@:2}" 2> /dev/null
}

bluetooth::scanner() {
  local sock="$1" pidf="$2" act="$3" run="${FZX_BLUETOOTH_SCAN_RUN:-60}" fd bt="" line pending=0 last=0 checked=0 owner
  [[ -n "$sock" && -n "$pidf" && -n "$act" ]] || return 2
  # one scanner a session
  if [[ -f "$pidf" ]] && read -r owner < "$pidf" && [[ -n "$owner" && "$owner" != "$$" ]] && kill -0 "$owner" 2> /dev/null; then
    return 0
  fi
  printf '%s\n' "$$" > "$pidf"
  # shellcheck disable=SC2064  # the paths now
  trap "bluetooth::_scanner_stop '$pidf'" EXIT
  trap 'exit 0' TERM INT HUP
  local started
  while :; do
    started=$SECONDS
    exec {fd}< <(exec bluetoothctl --timeout "$run" scan on 2> /dev/null)
    bt=$!
    BLUETOOTH_SCAN_CHILD="$bt"
    while :; do
      if IFS= read -r -t 1 -u "$fd" line; then
        [[ "$line" == *NEW*Device* || "$line" == *DEL*Device* ]] && pending=1
      elif (($? <= 128)); then
        # bluetoothctl ended (its timeout): start another
        break
      fi
      if ((SECONDS - checked >= 2)); then
        checked=$SECONDS
        bluetooth::_fzf "$sock" 'http://localhost?limit=0' > /dev/null || exit 0
        read -r owner < "$pidf" 2> /dev/null && [[ "$owner" == "$$" ]] || exit 0
      fi
      if ((pending && SECONDS - last >= 1)); then
        bluetooth::_fzf "$sock" -X POST --data-binary "$act" http://localhost > /dev/null
        pending=0 last=$SECONDS
      fi
    done
    exec {fd}<&-
    wait "$bt" 2> /dev/null
    # a client that fails at once is not restarted in a tight loop
    ((SECONDS - started >= 2)) || sleep 1
    bluetooth::_fzf "$sock" 'http://localhost?limit=0' > /dev/null || exit 0
  done
}

# bluetooth::_scanner_stop <pid file>: end the bluetoothctl client (discovery stops with it), drop the pid
# file when it is still ours
bluetooth::_scanner_stop() {
  local owner
  [[ -n "${BLUETOOTH_SCAN_CHILD:-}" ]] && kill "$BLUETOOTH_SCAN_CHILD" 2> /dev/null
  read -r owner < "$1" 2> /dev/null && [[ "$owner" == "$$" ]] && rm -f -- "$1"
  return 0
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && bluetooth::scanner "$@"
