#!/usr/bin/env bash
# bluetooth actions on the selected addresses, through bluetoothctl (which prints its errors on stdout:
# the quiet actions pass its last line on stderr, so the footer names the failure)

# bluetooth::wait: keep a failure on screen until a key (foreground actions return to fzf at once)
bluetooth::wait() {
  [[ -t 1 ]] || return 0
  printf '\n\e[2m(press a key)\e[0m'
  read -rsn1 < /dev/tty || :
}

# bluetooth::_quiet <bluetoothctl args...>: run it, its last line on stderr when it fails
bluetooth::_quiet() {
  local out rc=0
  out="$(command bluetoothctl "$@" 2>&1)" || rc=$?
  ((rc)) && printf '%s\n' "${out##*$'\n'}" >&2
  return "$rc"
}

# bluetooth::_field <bluetoothctl info|show output> <key>: the value of "Key: value"
bluetooth::_field() {
  awk -v k="$2" -F': ' '$1 == "\t" k { print $2; exit }' <<< "$1"
}

# bluetooth::action <action> <address...>
bluetooth::action() {
  local action="${1:-}" id rc=0 info secs="${FZX_BLUETOOTH_SCAN_SECONDS:-5}"
  shift
  # the header row's id, should it come along
  local ids=()
  for id; do [[ -n "$id" && "$id" != - ]] && ids+=("$id"); done
  case "$action" in
    connect | pair)
      for id in "${ids[@]}"; do
        if [[ "$action" == pair ]]; then
          command bluetoothctl pair "$id" && command bluetoothctl trust "$id" > /dev/null &&
            command bluetoothctl connect "$id" || rc=$?
        else
          command bluetoothctl connect "$id" || rc=$?
        fi
      done
      ((rc)) && bluetooth::wait
      ;;
    disconnect)
      for id in "${ids[@]}"; do bluetooth::_quiet disconnect "$id" || rc=$?; done
      ;;
    trust)
      for id in "${ids[@]}"; do
        info="$(command bluetoothctl info "$id" 2>&1)" || { printf '%s\n' "${info%%$'\n'*}" >&2; rc=1; continue; }
        if [[ "$(bluetooth::_field "$info" Trusted)" == yes ]]; then
          bluetooth::_quiet untrust "$id" || rc=$?
        else
          bluetooth::_quiet trust "$id" || rc=$?
        fi
      done
      ;;
    remove)
      for id in "${ids[@]}"; do command bluetoothctl remove "$id" || rc=$?; done
      ((rc)) && bluetooth::wait
      ;;
    scan)
      [[ "${FZX_MODE:-paired}" == all ]] || { printf 'bluetooth: scan lists its finds in the all mode\n' >&2; return 2; }
      printf 'scanning for %ss...\n' "$secs"
      command bluetoothctl --timeout "$secs" scan on || { rc=$?; bluetooth::wait; }
      ;;
    power)
      info="$(command bluetoothctl show 2>&1)" || { printf '%s\n' "${info%%$'\n'*}" >&2; return 1; }
      if [[ "$(bluetooth::_field "$info" Powered)" == yes ]]; then
        bluetooth::_quiet power off || rc=$?
      else
        bluetooth::_quiet power on || rc=$?
      fi
      ;;
    *)
      printf 'bluetooth: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" bluetooth
  bluetooth::action "$@"
}
