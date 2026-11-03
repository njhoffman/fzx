#!/usr/bin/env bash
# systemd menu entries

systemd::manifest() {
  fzx::entry systemd "User services"
  fzx::entry systemd:system "System services"
  fzx::entry systemd:failed "Failed services (user and system)"
  fzx::entry systemd:timers "Timers (user and system)"
  fzx::entry systemd:sockets "Sockets (user and system)"
}

# only on systemd hosts; the failed entry only when something has failed
systemd::applicable() {
  [[ -d /run/systemd/system ]] && command -v systemctl > /dev/null || return 1
  [[ "$1" != systemd:failed ]] && return 0
  [[ -n "$(SYSTEMD_COLORS=0 systemctl --system --failed --no-legend --plain --no-pager 2> /dev/null)" ||
    -n "$(SYSTEMD_COLORS=0 systemctl --user --failed --no-legend --plain --no-pager 2> /dev/null)" ]]
}

systemd::summary() {
  local manager=user n f
  [[ "$1" == systemd:system ]] && manager=system
  case "$1" in
    systemd:failed)
      n="$(SYSTEMD_COLORS=0 systemctl --system list-units --state=failed --no-legend --plain --no-pager | wc -l)"
      f="$(SYSTEMD_COLORS=0 systemctl --user list-units --state=failed --no-legend --plain --no-pager | wc -l)"
      printf '%s system, %s user\n' "${n// /}" "${f// /}"
      return 0
      ;;
    systemd:timers)
      n="$(SYSTEMD_COLORS=0 systemctl --system list-timers --no-legend --plain --no-pager | wc -l)"
      f="$(SYSTEMD_COLORS=0 systemctl --user list-timers --no-legend --plain --no-pager | wc -l)"
      printf '%s system, %s user\n' "${n// /}" "${f// /}"
      return 0
      ;;
    systemd:sockets)
      n="$(SYSTEMD_COLORS=0 systemctl --system list-sockets --no-legend --plain --no-pager | wc -l)"
      f="$(SYSTEMD_COLORS=0 systemctl --user list-sockets --no-legend --plain --no-pager | wc -l)"
      printf '%s system, %s user\n' "${n// /}" "${f// /}"
      return 0
      ;;
  esac
  n="$(SYSTEMD_COLORS=0 systemctl "--$manager" list-units --type=service --state=running --no-legend --plain --no-pager | wc -l)"
  f="$(SYSTEMD_COLORS=0 systemctl "--$manager" list-units --type=service --state=failed --no-legend --plain --no-pager | wc -l)"
  printf '%s running, %s failed\n' "${n// /}" "${f// /}"
}
