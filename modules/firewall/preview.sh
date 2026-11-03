#!/usr/bin/env bash
# firewall preview: the header row: ufw's verbose status (or why it cannot be read); a rule: its fields and
# the profile it names; a profile: its title, description, ports, file and the rules that name it

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# firewall::_profile <name>: the profile's section as "key=value" lines and its file (file=...)
firewall::_profile() {
  local dir="${FZX_FIREWALL_APPS_DIR:-/etc/ufw/applications.d}"
  awk -v n="$1" '
    /^\[.*\][[:space:]]*$/ { s = $0; sub(/^\[/, "", s); sub(/\][[:space:]]*$/, "", s); on = (s == n); if (on) print "file=" FILENAME; next }
    on && /^[a-z]+=/ { print }' "$dir"/* 2> /dev/null
}

# firewall::preview <id>
firewall::preview() {
  local id="${1:-}" out line
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  [[ -n "$id" ]] || return 0
  firewall::_sudo
  if [[ "$id" == - ]]; then
    if [[ -z "$FIREWALL_NOROOT" ]] && out="$(firewall::ufw status verbose 2>&1)"; then
      printf '%s\n' "$out"
    else
      printf 'ufw answers only root: run sudo -v, then ctrl-r.\n\n%s%s%s\n' "$d" "${FZX_FIREWALL_CONF:-/etc/ufw/ufw.conf}" "$r"
      grep -v '^#' "${FZX_FIREWALL_CONF:-/etc/ufw/ufw.conf}" 2> /dev/null | grep .
    fi
    return 0
  fi
  case "${FZX_MODE:-rules}" in
    rules)
      [[ -z "$FIREWALL_NOROOT" ]] || { echo "needs root: run sudo -v"; return 0; }
      if [[ "$id" == added:* ]]; then
        local spec="${id#added:}" name
        printf '%sufw %s%s\n\n' "$b" "$spec" "$r"
        printf '%snot in effect: ufw is off (enable turns it on, with every added rule)%s\n' "$d" "$r"
        name="$(sed -E "s/^[a-z]+ ((in|out) )?//; s/ comment .*//; s/^'(.*)'\$/\\1/; s/^\"(.*)\"\$/\\1/" <<< "$spec")"
        out="$(firewall::_profile "$name")"
        [[ -n "$out" ]] && printf '\n%sprofile%s  %s\n' "$d" "$r" "$(sed -n 's/^ports=//p' <<< "$out")"
        return 0
      fi
      line="$(firewall::ufw status numbered 2> /dev/null | grep -E "^\[ *$id\] ")"
      [[ -n "$line" ]] || { printf 'no rule %s (any more)\n' "$id"; return 0; }
      awk -v b="$b" -v d="$d" -v r="$r" '{
        n = $0; sub(/^\[ */, "", n); sub(/\].*/, "", n); rest = $0; sub(/^\[ *[0-9]+\] /, "", rest); cm = ""
        if (match(rest, / +# /)) { cm = substr(rest, RSTART + RLENGTH); rest = substr(rest, 1, RSTART - 1) }
        match(rest, / +(ALLOW|DENY|REJECT|LIMIT)( (IN|OUT|FWD))? +/)
        to = substr(rest, 1, RSTART - 1); act = substr(rest, RSTART, RLENGTH); from = substr(rest, RSTART + RLENGTH)
        gsub(/^ +| +$/, "", act); sub(/ +$/, "", from)
        printf "%srule %s%s\n\n", b, n, r
        printf "%s%-8s%s %s\n%s%-8s%s %s\n%s%-8s%s %s\n", d, "to", r, to, d, "action", r, act, d, "from", r, from
        if (cm != "") printf "%s%-8s%s %s\n", d, "comment", r, cm
        if (to ~ / \(v6\)$/) printf "%s%-8s%s %s\n", d, "family", r, "IPv6"
      }' <<< "$line"
      local to
      to="$(sed -E 's/^\[ *[0-9]+\] //; s/ +(ALLOW|DENY|REJECT|LIMIT)( (IN|OUT|FWD))? +.*//; s/ \(v6\)$//' <<< "$line")"
      out="$(firewall::_profile "$to")"
      [[ -n "$out" ]] && printf '\n%sprofile%s  %s\n' "$d" "$r" "$(sed -n 's/^ports=//p' <<< "$out")"
      ;;
    apps)
      out="$(firewall::_profile "$id")"
      [[ -n "$out" ]] || { printf 'no profile %s\n' "$id"; return 0; }
      printf '%s%s%s\n' "$b" "$id" "$r"
      sed -n 's/^title=//p' <<< "$out"
      echo
      sed -n 's/^description=//p' <<< "$out" | fold -s -w "${FZF_PREVIEW_COLUMNS:-80}"
      printf '\n%sports%s  %s\n' "$d" "$r" "$(sed -n 's/^ports=//p' <<< "$out")"
      printf '%sfile%s   %s\n' "$d" "$r" "$(sed -n 's/^file=//p' <<< "$out")"
      if [[ -z "$FIREWALL_NOROOT" ]]; then
        out="$(firewall::ufw status numbered 2> /dev/null | grep -E "^\[ *[0-9]+\] $(sed 's/[][\.*^$+?(){}|/]/\\&/g' <<< "$id")( \(v6\))? +(ALLOW|DENY|REJECT|LIMIT)")"
        if [[ -n "$out" ]]; then printf '\n%srules%s\n%s\n' "$d" "$r" "$out"; else printf '\n%sno rule names it%s\n' "$d" "$r"; fi
      fi
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" firewall
  firewall::preview "$@"
}
