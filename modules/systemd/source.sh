#!/usr/bin/env bash
# systemd source. Lines are "manager:unit<TAB>unit<TAB>display".
# Mode from $FZX_MODE: user (default), system, failed (failed units of both managers).

# systemd::units <manager> [systemctl list-units args...]
systemd::units() {
  local manager="$1"
  shift
  SYSTEMD_COLORS=0 command systemctl "--$manager" list-units --type=service --no-legend --plain --no-pager "$@" |
    awk -v m="$manager" '
      $2 == "not-found" { next }
      { unit = $1; active = $3; sub_ = $4; desc = ""; for (i = 5; i <= NF; i++) desc = desc (i > 5 ? " " : "") $i
        if (active == "failed") icon = "\033[31m●\033[0m"
        else if (active == "active" && sub_ == "running") icon = "\033[32m●\033[0m"
        else if (active == "active") icon = "\033[32m○\033[0m"
        else icon = "\033[38;5;240m○\033[0m"
        printf "%s:%s\t%s\t%s %-48s \033[38;5;244m%-8s\033[0m %s\n", m, unit, unit, icon, unit, sub_, desc }'
  return "${PIPESTATUS[0]}"
}

systemd::source() {
  case "${FZX_MODE:-user}" in
    user) systemd::units user --all ;;
    system) systemd::units system --all ;;
    failed)
      systemd::units system --state=failed
      systemd::units user --state=failed
      ;;
    *)
      printf 'systemd: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && systemd::source "$@"
