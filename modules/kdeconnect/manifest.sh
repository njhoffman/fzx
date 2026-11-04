#!/usr/bin/env bash
# kdeconnect menu entries, where the daemon is running: asked on the bus, which does not start it

kdeconnect::manifest() {
  fzx::entry kdeconnect "KDE Connect devices"
  fzx::entry kdeconnect:notifications "Notifications on your KDE Connect devices"
  fzx::entry kdeconnect:commands "Commands your KDE Connect devices offer"
}

# once per menu listing, not once per entry
kdeconnect::applicable() {
  if [[ -z "${_KDECONNECT_UP:-}" ]]; then
    command -v kdeconnect-cli > /dev/null && command -v busctl > /dev/null && command -v jq > /dev/null &&
      command busctl --user status org.kde.kdeconnect > /dev/null 2>&1
    _KDECONNECT_UP=$?
  fi
  return "$_KDECONNECT_UP"
}

# kdeconnect::summary <target>: what is connected and its battery; how many notifications
kdeconnect::summary() {
  source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
  local id name charge parts=() n=0
  case "$1" in
    kdeconnect)
      while read -r id name; do
        [[ -n "$id" ]] || continue
        charge="$(kdeconnect::battery "$id" | cut -d' ' -f1)"
        parts+=("$name${charge:+ ${charge}%}")
      done < <(kdeconnect::connected)
      if ((${#parts[@]})); then
        (IFS=,; printf '%s\n' "${parts[*]}")
      else
        printf 'nothing connected\n'
      fi
      ;;
    kdeconnect:notifications)
      while read -r id name; do
        [[ -n "$id" ]] || continue
        n=$((n + $(kdeconnect::notification_ids "$id" | wc -l)))
      done < <(kdeconnect::connected)
      printf '%s notification%s\n' "$n" "$( ((n == 1)) || echo s)"
      ;;
  esac
}
