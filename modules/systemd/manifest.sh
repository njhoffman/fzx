#!/usr/bin/env bash
# systemd menu entries

systemd::manifest() {
  fzx::entry systemd "User services"
  fzx::entry systemd:system "System services"
  fzx::entry systemd:failed "Failed services (user and system)"
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
  [[ "$1" == systemd:failed ]] && return 0 # the entry only shows when something failed
  n="$(SYSTEMD_COLORS=0 systemctl "--$manager" list-units --type=service --state=running --no-legend --plain --no-pager | wc -l)"
  f="$(SYSTEMD_COLORS=0 systemctl "--$manager" list-units --type=service --state=failed --no-legend --plain --no-pager | wc -l)"
  printf '%s running, %s failed\n' "${n// /}" "${f// /}"
}
