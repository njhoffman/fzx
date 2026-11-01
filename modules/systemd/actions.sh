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

# systemd::_journal_unit <manager> <unit> <var>: the unit whose journal to follow: what a timer or socket
# activates (Triggers), else the unit itself
systemd::_journal_unit() {
  local _t=""
  if [[ "$2" == *.timer || "$2" == *.socket ]]; then
    _t="$(SYSTEMD_COLORS=0 command systemctl "--$1" show -p Triggers --value -- "$2" 2> /dev/null)"
    _t="${_t%% *}"
  fi
  printf -v "$3" '%s' "${_t:-$2}"
}

# systemd::action <start|stop|restart|reload|enable|disable|daemon-reload|journal|edit> <manager:unit...>
# reload is reload-or-restart (a unit without ExecReload restarts); daemon-reload runs once per manager of
# the selection.
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
    start | stop | restart | reload | enable | disable)
      [[ "$action" == reload ]] && action=reload-or-restart
      for id in "$@"; do
        systemd::_run "${id%%:*}" systemctl "--${id%%:*}" "$action" -- "${id#*:}" || rc=$?
      done
      return "$rc"
      ;;
    daemon-reload)
      local manager
      for manager in system user; do
        [[ " $* " == *" $manager:"* ]] || continue
        systemd::_run "$manager" systemctl "--$manager" daemon-reload || rc=$?
      done
      return "$rc"
      ;;
    journal)
      trap : INT
      id="$1"
      local unit
      systemd::_journal_unit "${id%%:*}" "${id#*:}" unit
      SYSTEMD_COLORS=1 command journalctl "--${id%%:*}" -u "$unit" -n 100 -f
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
