#!/usr/bin/env bash
# firewall source (ufw): a header row, then "id<TAB>copy text<TAB>display" per row. Mode from $FZX_MODE:
# rules (default: `ufw status numbered`, ids the rule numbers), apps (the application profiles in
# FZX_FIREWALL_APPS_DIR, ids their names). ufw answers only root, so rules and the policies go through
# `sudo -n`: without a cached sudo the header row says so and shows whether ufw is on from ufw.conf
# (readable by everyone); the profiles are plain files and list either way.

# firewall::_sudo: FIREWALL_SUDO, the prefix that runs ufw (none as root; `sudo -n` when it is cached);
# FIREWALL_NOROOT=1 when sudo needs a password
firewall::_sudo() {
  FIREWALL_SUDO=(command) FIREWALL_NOROOT=""
  ((EUID == 0)) && return 0
  if command sudo -n true 2> /dev/null; then FIREWALL_SUDO=(command sudo -n); else FIREWALL_NOROOT=1; fi
}

# firewall::ufw <args...>: ufw through FIREWALL_SUDO (call firewall::_sudo first)
firewall::ufw() {
  "${FIREWALL_SUDO[@]}" ufw "$@"
}

# firewall::_conf_enabled: yes or no from ufw.conf's ENABLED (without root)
firewall::_conf_enabled() {
  awk -F= '$1 == "ENABLED" { gsub(/["[:space:]]/, "", $2); print $2; f = 1; exit } END { if (!f) print "no" }' \
    "${FZX_FIREWALL_CONF:-/etc/ufw/ufw.conf}" 2> /dev/null
}

# firewall::header <status verbose output|""> [added]: the header row: on or off, the default policies,
# logging; or what is missing. A non-empty added (ufw off, `ufw show added` lists rules) says they are not in
# effect.
firewall::header() {
  local out="$1" added="${2:+1}" b=$'\e[1m' on=$'\e['"${FZX_COLORS[firewall_allow]:-38;5;114}m" off=$'\e['"${FZX_COLORS[firewall_deny]:-38;5;203}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && b="" on="" off="" d="" r=""
  if [[ -z "$out" ]]; then
    local st
    st="$([[ "$(firewall::_conf_enabled)" == yes ]] && printf '%sactive%s' "$on" "$r" || printf '%sinactive%s' "$off" "$r")"
    printf -- '-\t-\t%sufw%s  %s %s(ufw.conf)  rules need root: run sudo -v, then ctrl-r%s\n' "$b" "$r" "$st" "$d" "$r"
    return
  fi
  awk -v b="$b" -v on="$on" -v off="$off" -v d="$d" -v r="$r" -v added="$added" '
    /^Status:/ { st = $2 }
    /^Default:/ { sub(/^Default: */, ""); pol = $0 }
    /^Logging:/ { sub(/^Logging: */, ""); lg = $0 }
    END {
      printf "-\t-\t%sufw%s  %s%s%s", b, r, (st == "active" ? on : off), st, r
      if (st == "inactive" && added != "") printf "  %srules added, not in effect%s", d, r
      if (pol != "") printf "  %s%s%s", d, pol, r
      if (lg != "") printf "  %slogging %s%s", d, lg, r
      printf "\n"
    }' <<< "$out"
}

# firewall::rules: `ufw status numbered` as rows: number, to, action (colored), from, comment
firewall::rules() {
  local out verbose
  local a=$'\e['"${FZX_COLORS[firewall_allow]:-38;5;114}m" x=$'\e['"${FZX_COLORS[firewall_deny]:-38;5;203}m"
  local l=$'\e['"${FZX_COLORS[firewall_limit]:-38;5;180}m" d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && a="" x="" l="" d="" r=""
  firewall::_sudo
  if [[ -n "$FIREWALL_NOROOT" ]] || ! verbose="$(firewall::ufw status verbose 2> /dev/null)"; then
    firewall::header ""
    return 0
  fi
  if [[ "$verbose" == "Status: inactive"* ]]; then
    local added
    added="$(firewall::added)"
    firewall::header "$verbose" "$added"
    [[ -z "$added" ]] || printf '%s\n' "$added"
    return 0
  fi
  firewall::header "$verbose"
  out="$(firewall::ufw status numbered 2> /dev/null)" || return 0
  awk -v a="$a" -v x="$x" -v l="$l" -v d="$d" -v r="$r" '
    function pad(t, w) { return length(t) > w ? substr(t, 1, w - 1) "…" : sprintf("%-" w "s", t) }
    /^\[ *[0-9]+\]/ {
      n = $0; sub(/^\[ */, "", n); sub(/\].*/, "", n)
      rest = $0; sub(/^\[ *[0-9]+\] /, "", rest)
      cm = ""
      if (match(rest, / +# /)) { cm = substr(rest, RSTART + RLENGTH); rest = substr(rest, 1, RSTART - 1) }
      if (!match(rest, / +(ALLOW|DENY|REJECT|LIMIT)( (IN|OUT|FWD))? +/)) next
      to = substr(rest, 1, RSTART - 1); act = substr(rest, RSTART, RLENGTH); from = substr(rest, RSTART + RLENGTH)
      gsub(/^ +| +$/, "", act); sub(/ +$/, "", from)
      c = (act ~ /^ALLOW/ ? a : act ~ /^LIMIT/ ? l : x)
      printf "%s\t%s\t%s%3s%s  %s  %s%s%s  %s%s\n", n, to " " act " " from, d, n, r, pad(to, 28), c, pad(act, 10), r, pad(from, 26),
        (cm == "" ? "" : "  " d "# " cm r)
    }' <<< "$out"
}

# firewall::added: while ufw is off `ufw status` lists no rules, so the rules added (`ufw show added`, the
# commands that made them) are listed instead, ids "added:SPEC" (delete takes the rule itself: there are
# no numbers while ufw is off)
firewall::added() {
  local a=$'\e['"${FZX_COLORS[firewall_allow]:-38;5;114}m" x=$'\e['"${FZX_COLORS[firewall_deny]:-38;5;203}m"
  local l=$'\e['"${FZX_COLORS[firewall_limit]:-38;5;180}m" d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && a="" x="" l="" d="" r=""
  firewall::ufw show added 2> /dev/null | awk -v a="$a" -v x="$x" -v l="$l" -v d="$d" -v r="$r" '
    /^ufw / {
      spec = substr($0, 5); act = $2; rest = spec; sub(/^[^ ]+ */, "", rest)
      c = (act == "allow" ? a : act == "limit" ? l : x)
      printf "added:%s\t%s\t%s  -%s  %s%-10s%s  %s  %s(not in effect)%s\n", spec, spec, d, r, c, toupper(act), r, rest, d, r
    }'
}

# firewall::profiles: every application profile in FZX_FIREWALL_APPS_DIR, one "name<TAB>title<TAB>ports" line
# per section (a file may hold several), sorted by name
firewall::profiles() {
  local dir="${FZX_FIREWALL_APPS_DIR:-/etc/ufw/applications.d}"
  [[ -d "$dir" ]] || return 0
  awk '
    function flush() { if (name != "") print name "\t" t "\t" p; name = "" }
    FNR == 1 { flush() }
    /^[[:space:]]*[#;]/ { next }
    /^\[.*\][[:space:]]*$/ { flush(); name = $0; sub(/^\[/, "", name); sub(/\][[:space:]]*$/, "", name); t = p = ""; next }
    name != "" && /^title=/ { t = substr($0, 7) }
    name != "" && /^ports=/ { p = substr($0, 7) }
    END { flush() }
  ' "$dir"/* 2> /dev/null | sort -t $'\t' -k1,1 -f
}

# firewall::apps: the header row, then the profiles: name, ports, title, and the rules that name it (root)
firewall::apps() {
  local verbose="" rules="" shown=""
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" a=$'\e['"${FZX_COLORS[firewall_allow]:-38;5;114}m"
  local x=$'\e['"${FZX_COLORS[firewall_deny]:-38;5;203}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && d="" a="" x="" r=""
  firewall::_sudo
  if [[ -z "$FIREWALL_NOROOT" ]] && verbose="$(firewall::ufw status verbose 2> /dev/null)"; then
    if [[ "$verbose" == "Status: inactive"* ]]; then
      # ufw off: the added rules that name a profile ("allow OpenSSH", "allow 'Postfix SMTPS'"), as
      # status would list them, marked off
      shown="$(firewall::ufw show added 2> /dev/null | awk '/^ufw /')"
      rules="$(awk '
        /^ufw (allow|deny|reject|limit)( (in|out))? / {
          act = toupper($2); name = $0; sub(/^ufw [a-z]+ ((in|out) )?/, "", name); sub(/ comment .*/, "", name)
          gsub(/^\047|\047$|^"|"$/, "", name)
          if (name ~ /^[A-Za-z]/) printf "%s %s off\n", name, act
        }' <<< "$shown")"
      [[ -n "$rules" ]] || rules=" "
    else
      rules="$(firewall::ufw status 2> /dev/null)"
    fi
  else
    verbose=""
  fi
  firewall::header "$verbose" "$shown"
  firewall::profiles | awk -F '\t' -v rules="$rules" -v d="$d" -v a="$a" -v x="$x" -v r="$r" '
    function pad(t, w) { return length(t) > w ? substr(t, 1, w - 1) "…" : sprintf("%-" w "s", t) }
    BEGIN {
      n = split(rules, L, "\n")
      for (i = 1; i <= n; i++) {
        if (L[i] ~ / (ALLOW|DENY|REJECT|LIMIT) off$/) {
          to = L[i]; sub(/ [A-Z]+ off$/, "", to); act = L[i]; sub(/ off$/, "", act); sub(/.* /, "", act)
          if (!(to in st)) st[to] = act " off"
          continue
        }
        if (!match(L[i], / +(ALLOW|DENY|REJECT|LIMIT)( (IN|OUT|FWD))? +/)) continue
        to = substr(L[i], 1, RSTART - 1); act = substr(L[i], RSTART, RLENGTH); gsub(/^ +| +$/, "", act)
        sub(/ \(v6\)$/, "", to)
        if (!(to in st)) st[to] = act
      }
    }
    {
      # the rule column only when ufw could be read
      s = rules == "" ? "" : (($1 in st) ? ((st[$1] ~ / off$/ ? d : st[$1] ~ /^(ALLOW|LIMIT)/ ? a : x) pad(st[$1], 10) r) : pad("", 10)) "  "
      printf "%s\t%s\t%s  %s%s%s%s  %s\n", $1, $1, pad($1, 24), s, d, pad($3, 26), r, $2
    }'
}

firewall::source() {
  case "${FZX_MODE:-rules}" in
    rules) firewall::rules ;;
    apps) firewall::apps ;;
    *)
      printf 'firewall: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" firewall
  firewall::source "$@"
}
