#!/usr/bin/env bash
# systemd actions. Bound with fzf execute (foreground) so sudo can prompt for system units.

# systemd::_run <manager> <cmd...>: run as is for user units, through sudo for system units unless root
systemd::_run() {
  local manager="$1"
  shift
  if [[ "$manager" == system && "$EUID" -ne 0 ]]; then
    command sudo "$@"
  else
    "$@"
  fi
}

# systemd::action <start|stop|restart|enable|disable|journal|edit> <manager:unit...>
systemd::action() {
  local action="${1:-}" id rc=0
  shift
  (($#)) || {
    printf 'systemd: %s: no units given\n' "$action" >&2
    return 2
  }
  for id in "$@"; do
    [[ "$id" == user:* || "$id" == system:* ]] || {
      printf 'systemd: not a unit id: %s\n' "$id" >&2
      return 2
    }
  done
  case "$action" in
    start | stop | restart | enable | disable)
      for id in "$@"; do
        systemd::_run "${id%%:*}" systemctl "--${id%%:*}" "$action" -- "${id#*:}" || rc=$?
      done
      return "$rc"
      ;;
    journal)
      trap : INT
      id="$1"
      SYSTEMD_COLORS=1 command journalctl "--${id%%:*}" -u "${id#*:}" -n 100 -f
      return 0
      ;;
    edit)
      id="$1"
      systemd::_run "${id%%:*}" systemctl "--${id%%:*}" edit -- "${id#*:}"
      ;;
    *)
      printf 'systemd: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && systemd::action "$@"
