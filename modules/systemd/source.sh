#!/usr/bin/env bash
# systemd source. Lines are "manager:unit<TAB>unit<TAB>display".
# Mode from $FZX_MODE: user (default), system, failed (failed units of both managers).
# $FZX_SORT: name (default) or state (failed, running, other active, inactive); the sorted column is drawn
# in FZX_COLORS[sorted] as well.

# systemd::units <manager> [systemctl list-units args...]
systemd::units() {
  local manager="$1"
  shift
  SYSTEMD_COLORS=0 command systemctl "--$manager" list-units --type=service --no-legend --plain --no-pager "$@" |
    awk -v m="$manager" -v sort="${FZX_SORT:-name}" -v hl=$'\e['"${FZX_COLORS[sorted]:-4}m" '
      function cell(color, text, w, on) { return color (on ? hl : "") text "\033[0m" sprintf("%" (w - length(text) > 0 ? w - length(text) : 0) "s", "") }
      $2 == "not-found" { next }
      { unit = $1; active = $3; sub_ = $4; desc = ""; for (i = 5; i <= NF; i++) desc = desc (i > 5 ? " " : "") $i
        if (active == "failed") { icon = "\033[31m●\033[0m"; rank = 0 }
        else if (active == "active" && sub_ == "running") { icon = "\033[32m●\033[0m"; rank = 1 }
        else if (active == "active") { icon = "\033[32m○\033[0m"; rank = 2 }
        else { icon = "\033[38;5;240m○\033[0m"; rank = 3 }
        printf "%s\t%s:%s\t%s\t%s %s %s %s\n", (sort == "state" ? rank : "") tolower(unit), m, unit, unit, icon,
          cell("", unit, 48, sort == "name"), cell("\033[38;5;244m", sub_, 8, sort == "state"), desc }' |
    sort -s -t $'\t' -k1,1 | cut -f2-
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
