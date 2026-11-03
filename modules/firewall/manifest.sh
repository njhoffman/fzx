#!/usr/bin/env bash
# firewall menu entries, where ufw is installed

firewall::manifest() {
  fzx::entry firewall "Firewall rules (ufw)"
  fzx::entry firewall:apps "Firewall application profiles"
}

firewall::applicable() {
  command -v ufw > /dev/null || [[ -x /usr/sbin/ufw ]]
}

# firewall::summary <target>: on or off (from ufw.conf: ufw itself answers only root), the profile count
firewall::summary() {
  local dir="${FZX_FIREWALL_APPS_DIR:-/etc/ufw/applications.d}" n
  case "$1" in
    firewall)
      awk -F= '$1 == "ENABLED" { gsub(/["[:space:]]/, "", $2); print ($2 == "yes" ? "on" : "off"); exit }' \
        "${FZX_FIREWALL_CONF:-/etc/ufw/ufw.conf}" 2> /dev/null
      ;;
    firewall:apps)
      n="$(cat "$dir"/* 2> /dev/null | grep -c '^\[')" || :
      printf '%s profiles\n' "${n:-0}"
      ;;
  esac
}
