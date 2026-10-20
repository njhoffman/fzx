#!/usr/bin/env bash
# systemd preview: systemctl status of one unit

# systemd::preview <manager:unit>
systemd::preview() {
  local id="${1:-}"
  [[ "$id" == user:* || "$id" == system:* ]] || {
    printf 'not a unit id: %s\n' "$id"
    return 1
  }
  SYSTEMD_COLORS=1 command systemctl "--${id%%:*}" status --no-pager --lines=20 -- "${id#*:}"
  return 0
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && systemd::preview "$@"
