#!/usr/bin/env bash
# systemd source. Lines are "manager:unit<TAB>unit<TAB>display".
# Mode from $FZX_MODE: user (default), system, failed (failed units of both managers), timers and sockets
# (both managers; each row names its manager).
# user and system merge the unit files that are not loaded (list-units only knows loaded units): enabled and
# disabled ones always, static, masked, generated and alias ones with the files toggle ($FZX_TOGGLES).
# Template units (foo@.service) are left out: they need an instance name to start or enable.
# $FZX_SORT: name (default) or state (failed, running, other active, inactive, not loaded); the sorted column
# is drawn in FZX_COLORS[sorted] as well. With a header row (FZX_SORT_HEADER, lib/header.sh) the columns are
# named first.

# systemd::_awk_lib: awk functions shared by the lists
systemd::_awk_lib() {
  printf '%s' '
    function cell(color, text, w, on) { return color (on ? hl : "") text "\033[0m" sprintf("%" (w - length(text) > 0 ? w - length(text) : 0) "s", "") }
    # a duration as 45s, 28m, 16h or 3d
    function rel(s) { if (s < 0) s = -s
      return s < 60 ? int(s) "s" : s < 3600 ? int(s / 60) "m" : s < 86400 ? int(s / 3600) "h" : int(s / 86400) "d" }
  '
}

# systemd::units <manager> [systemctl list-units args...]: services, loaded ones merged with unit files when
# no --state is given
systemd::units() {
  local manager="$1" files=/dev/null allfiles=0
  shift
  [[ " ${FZX_TOGGLES:-} " == *" files "* ]] && allfiles=1
  if [[ " $* " != *" --state="* ]]; then
    files="$(mktemp)"
    # shellcheck disable=SC2064  # the path is fixed now
    trap "rm -f -- '$files'" RETURN
    SYSTEMD_COLORS=0 command systemctl "--$manager" list-unit-files --type=service --no-legend --plain \
      --no-pager > "$files" 2> /dev/null || : > "$files"
  fi
  SYSTEMD_COLORS=0 command systemctl "--$manager" list-units --type=service --no-legend --plain --no-pager "$@" |
    awk -v m="$manager" -v src="$files" -v sort="${FZX_SORT:-name}" -v all="$allfiles" -v hl=$'\e['"${FZX_COLORS[sorted]:-4}m" \
      "$(systemd::_awk_lib)"'
      function row(rank, unit, icon, sub_, desc) {
        printf "%s\t%s:%s\t%s\t%s %s %s %s\n", (sort == "state" ? rank : "") tolower(unit), m, unit, unit, icon,
          cell("", unit, 48, sort == "name"), cell("\033[38;5;244m", sub_, 8, sort == "state"), desc
      }
      FILENAME == src { if (NF >= 2) file[$1] = $2; next }
      $2 == "not-found" { next }
      { unit = $1; active = $3; sub_ = $4; desc = ""; for (i = 5; i <= NF; i++) desc = desc (i > 5 ? " " : "") $i
        seen[unit] = 1
        if (active == "failed") { icon = "\033[31m●\033[0m"; rank = 0 }
        else if (active == "active" && sub_ == "running") { icon = "\033[32m●\033[0m"; rank = 1 }
        else if (active == "active") { icon = "\033[32m○\033[0m"; rank = 2 }
        else { icon = "\033[38;5;240m○\033[0m"; rank = 3 }
        row(rank, unit, icon, sub_, desc) }
      END {
        for (unit in file) {
          state = file[unit]
          if (unit in seen || unit ~ /@\./) continue
          if (!all && state != "enabled" && state != "disabled") continue
          row(4, unit, "\033[38;5;238m◌\033[0m", state, "\033[38;5;240mnot loaded\033[0m")
        }
      }' "$files" - |
    sort -s -t $'\t' -k1,1 | cut -f2-
  return "${PIPESTATUS[0]}"
}

# systemd::_json_rows <keys...>: systemctl's -o json array of flat objects on stdin -> one line per object,
# the values of the keys given tab-separated ("" for null)
systemd::_json_rows() {
  awk -v keys="$*" '
    BEGIN { RS = "}"; nk = split(keys, k, " ") }
    {
      line = ""
      for (i = 1; i <= nk; i++) {
        v = ""
        if (match($0, "\"" k[i] "\":(\"[^\"]*\"|[^,}]*)")) {
          v = substr($0, RSTART + length(k[i]) + 3, RLENGTH - length(k[i]) - 3)
          if (v == "null") v = ""
          gsub(/^"|"$/, "", v)
        }
        line = line (i > 1 ? "\t" : "") v
      }
      if (line ~ /[^\t]/) print line
    }'
}

# systemd::timers <manager>: next run (in N), last run (N ago), the unit it activates
systemd::timers() {
  local manager="$1"
  SYSTEMD_COLORS=0 command systemctl "--$manager" list-timers --all -o json --no-pager |
    systemd::_json_rows unit next last activates |
    awk -F '\t' -v m="$manager" -v now="$(date +%s)" -v sort="${FZX_SORT:-name}" -v hl=$'\e['"${FZX_COLORS[sorted]:-4}m" \
      "$(systemd::_awk_lib)"'
      $1 == "" { next }
      { next_ = ($2 + 0 > 0) ? "in " rel($2 / 1000000 - now) : "-"
        last = ($3 + 0 > 0) ? rel(now - $3 / 1000000) " ago" : "never"
        icon = ($2 + 0 > 0) ? "\033[32m●\033[0m" : "\033[38;5;240m○\033[0m"
        key = sort == "state" ? (($2 + 0 > 0) ? sprintf("0%020d", $2) : "1") : ""
        printf "%s%s\t%s:%s\t%s\t%s %s %s %s %s \033[38;5;244m%s\033[0m\n", key, tolower($1), m, $1, $1, icon,
          cell("\033[38;5;240m", m, 7, 0), cell("", $1, 44, sort == "name"),
          cell("\033[38;5;110m", next_, 9, sort == "state"), cell("\033[38;5;244m", last, 10, 0), $4 }'
}

# systemd::sockets <manager>: what each socket listens on (several addresses joined), the unit it activates
systemd::sockets() {
  local manager="$1"
  SYSTEMD_COLORS=0 command systemctl "--$manager" list-sockets --all -o json --no-pager |
    systemd::_json_rows unit listen activates |
    awk -F '\t' -v m="$manager" -v sort="${FZX_SORT:-name}" -v hl=$'\e['"${FZX_COLORS[sorted]:-4}m" \
      "$(systemd::_awk_lib)"'
      $1 == "" { next }
      !($1 in listen) { order[++n] = $1; act[$1] = $3 }
      { listen[$1] = ($1 in listen) ? listen[$1] ", " $2 : $2 }
      END {
        for (i = 1; i <= n; i++) {
          u = order[i]
          icon = act[u] != "" ? "\033[32m●\033[0m" : "\033[38;5;240m○\033[0m"
          key = sort == "state" ? (act[u] != "" ? "0" : "1") : ""
          printf "%s%s\t%s:%s\t%s\t%s %s %s %s \033[38;5;244m%s\033[0m\n", key, tolower(u), m, u, u, icon,
            cell("\033[38;5;240m", m, 7, 0), cell("", u, 44, sort == "name"), cell("\033[38;5;110m", listen[u], 36, 0), act[u]
        }
      }'
}

# systemd::_both <fn>: a list of both managers, sorted together
systemd::_both() {
  {
    "$1" system
    "$1" user
  } | sort -s -t $'\t' -k1,1 | cut -f2-
}

# systemd::header: the header row (lib/header.sh) of the mode's list, when the view has one
systemd::header() {
  fzx::require header
  local state=STATE
  case "${FZX_MODE:-user}" in
    timers) state=NEXT ;;
    sockets) state=ACTIVATES ;;
  esac
  [[ "${FZX_SORT:-name}" == name ]] && state=UNIT
  case "${FZX_MODE:-user}" in
    timers) fzx::header_print 2 "$state" "" 1 0 MANAGER 7 0 UNIT 44 0 NEXT 9 0 LAST 10 0 ACTIVATES 0 0 ;;
    sockets) fzx::header_print 2 "$state" "" 1 0 MANAGER 7 0 UNIT 44 0 LISTEN 36 0 ACTIVATES 0 0 ;;
    *) fzx::header_print 2 "$state" "" 1 0 UNIT 48 0 STATE 8 0 DESCRIPTION 0 0 ;;
  esac
}

systemd::source() {
  systemd::header
  case "${FZX_MODE:-user}" in
    user) systemd::units user --all ;;
    system) systemd::units system --all ;;
    failed)
      systemd::units system --state=failed
      systemd::units user --state=failed
      ;;
    timers) systemd::_both systemd::timers ;;
    sockets) systemd::_both systemd::sockets ;;
    *)
      printf 'systemd: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" systemd
  systemd::source "$@"
}
