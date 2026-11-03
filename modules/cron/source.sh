#!/usr/bin/env bash
# cron source: "id<TAB>command<TAB>display" per entry. ids are KIND:FILE:LINE (KIND user, system, anacron or
# script; FILE "-" for your crontab, LINE 0 for a script). Mode from $FZX_MODE: all (default: your crontab
# and the system's), user (your crontab, commented-out entries as disabled), system (FZX_CRON_SYSTEM_FILES:
# /etc/crontab and /etc/cron.d, then FZX_CRON_ANACRONTAB's jobs), scripts (the run-parts directories,
# FZX_CRON_SCRIPT_DIRS, with the next run of the job that runs them). $FZX_SORT: next (default) or file.
#
# Next runs: each entry becomes systemd OnCalendar expressions, all computed by one `systemd-analyze
# calendar` call. cron ORs day of month and day of week when both are restricted (neither starts with *)
# where systemd ANDs them, so such an entry is two expressions and the earlier run wins. anacron jobs run
# PERIOD days after their last run (the mtime of FZX_CRON_ANACRON_SPOOL/ID).

# cron::_parse <kind> <file label> [user]: the entries of a crontab on stdin, one record per line:
# id, kind, user, schedule, command, expr1, expr2, state ("", disabled, reboot, invalid,
# anacron:PERIOD:DELAY:JOB or anacron-off:PERIOD:DELAY:JOB). kind user is your crontab, spool another
# user's (user names them), system crontabs have a user field, anacrontab "PERIOD DELAY JOB COMMAND".
# Commented-out lines that parse as entries are disabled ones; in system files their user must exist (the
# example line "* * * * * user-name command" does not count). CRON_TZ= lines move the schedules that
# follow into that zone where cron honors it (cron::honors_tz)
cron::_parse() {
  local users="" tzok=0
  [[ "$1" == system ]] && users=" $(getent passwd 2> /dev/null | cut -d: -f1 | tr '\n' ' ') "
  cron::honors_tz && tzok=1
  awk -v kind="$1" -v file="$2" -v me="${3:-${USER:-$(id -un)}}" -v users="$users" -v tzok="$tzok" \
    -F '\t' -v OFS='\t' '
    BEGIN {
      split("jan feb mar apr may jun jul aug sep oct nov dec", m, " "); for (i = 1; i <= 12; i++) mon[m[i]] = i
      split("sun mon tue wed thu fri sat", d, " "); for (i = 1; i <= 7; i++) dow[d[i]] = i - 1
      split("Sun Mon Tue Wed Thu Fri Sat", dn, " ")
      at["@yearly"] = at["@annually"] = "0 0 1 1 *"; at["@monthly"] = "0 0 1 * *"; at["@weekly"] = "0 0 * * 0"
      at["@daily"] = at["@midnight"] = "0 0 * * *"; at["@hourly"] = "0 * * * *"
    }
    # num(s, names): a number or a name; -1 when it is neither
    function num(s, which) {
      s = tolower(s)
      if (s ~ /^[0-9]+$/) return s + 0
      if (which == "mon" && s in mon) return mon[s]
      if (which == "dow" && s in dow) return dow[s]
      return -1
    }
    # expand(field, lo, hi, which): "*" or the sorted comma list of the values; "" when invalid
    function expand(f, lo, hi, which,   parts, n, i, p, step, a, b, v, seen, out, k) {
      if (f == "*") return "*"
      n = split(f, parts, ",")
      delete seen
      for (i = 1; i <= n; i++) {
        p = parts[i]; step = 1
        if (p ~ /\//) { step = substr(p, index(p, "/") + 1); p = substr(p, 1, index(p, "/") - 1); if (step !~ /^[0-9]+$/ || step == 0) return "" }
        if (p == "*") { a = lo; b = hi }
        else if (p ~ /-/) { a = num(substr(p, 1, index(p, "-") - 1), which); b = num(substr(p, index(p, "-") + 1), which) }
        else { a = num(p, which); b = (step > 1 ? hi : a) }
        if (a < 0 || b < 0 || a > b || a < lo || b > hi) return ""
        for (v = a; v <= b; v += step) seen[(which == "dow" && v == 7) ? 0 : v] = 1
      }
      out = ""
      for (k = lo; k <= hi; k++) if (k in seen) out = out (out == "" ? "" : ",") (which == "dow" ? dn[k + 1] : k)
      return out
    }
    # cal(min, hour, dom, mon, dow): the OnCalendar expression
    function cal(mi, ho, dm, mo, dw) {
      return (dw == "*" ? "" : dw " ") "*-" mo "-" dm " " ho ":" mi ":00"
    }
    # entry(sched, user, cmd, state): one record, the schedule turned into expressions
    function entry(sched, user, cmd, state,   f, n, mi, ho, dm, mo, dw, e1, e2) {
      e1 = e2 = ""
      if (sched == "@reboot") state = (state == "" ? "reboot" : state)
      else {
        n = split(sched in at ? at[sched] : sched, f, " ")
        mi = expand(f[1], 0, 59, ""); ho = expand(f[2], 0, 23, ""); dm = expand(f[3], 1, 31, "")
        mo = expand(f[4], 1, 12, "mon"); dw = expand(f[5], 0, 7, "dow")
        if (n != 5 || mi == "" || ho == "" || dm == "" || mo == "" || dw == "") return 0
        if (f[3] !~ /^\*/ && f[5] !~ /^\*/) { e1 = cal(mi, ho, dm, mo, "*"); e2 = cal(mi, ho, "*", mo, dw) }
        else e1 = cal(mi, ho, dm, mo, dw)
        # systemd takes a zone after the time
        if (tzok && tz != "") { e1 = e1 " " tz; if (e2 != "") e2 = e2 " " tz }
      }
      gsub(/\t/, " ", cmd)
      print kind ":" file ":" NR, kind, user, sched, cmd, e1, e2, state
      return 1
    }
    {
      line = $0; gsub(/\t/, " ", line); sub(/^ +/, "", line)
      if (line == "") next
      off = ""
      if (line ~ /^#/) {
        # a commented-out entry is shown as disabled; other comments are skipped (they do not parse)
        off = "disabled"; sub(/^#+ */, "", line)
        if (line == "") next
      }
      # VAR=value lines (CRON_TZ: the zone of the entries after it)
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]* *=/) {
        if (off == "" && line ~ /^CRON_TZ *=/) { tz = line; sub(/^CRON_TZ *= */, "", tz); gsub(/^["\047]|["\047] *$/, "", tz); sub(/ +$/, "", tz) }
        next
      }
      if (kind == "anacron") {
        n = split(line, w, / +/)
        if (n < 4 || (w[1] !~ /^[0-9]+$/ && w[1] !~ /^@(daily|weekly|monthly|yearly|annually)$/) || w[2] !~ /^[0-9]+$/) next
        cmd = line; for (i = 1; i <= 3; i++) sub(/^[^ ]+ +/, "", cmd)
        gsub(/\t/, " ", cmd)
        print kind ":" file ":" NR, kind, "root", w[1], cmd, "", "", (off == "" ? "anacron:" : "anacron-off:") w[1] ":" w[2] ":" w[3]
        next
      }
      nf = (line ~ /^@/ ? 1 : 5) + (kind == "system" ? 1 : 0)
      n = split(line, w, / +/)
      if (n <= nf) next
      sched = w[1]; for (i = 2; i <= (line ~ /^@/ ? 1 : 5); i++) sched = sched " " w[i]
      user = (kind == "system" ? w[nf] : me)
      if (off != "" && kind == "system" && index(users, " " user " ") == 0) next
      cmd = line; for (i = 1; i <= nf; i++) sub(/^[^ ]+ +/, "", cmd)
      if (!entry(sched, user, cmd, off) && off == "") {
        # a broken line of a crontab cron would reject too: listed so it can be fixed
        print kind ":" file ":" NR, kind, user, sched, cmd, "", "", "invalid"
      }
    }'
}

# cron::split <id> <kind var> <file var> <line var>: KIND:FILE:LINE apart (FILE may hold colons)
cron::split() {
  local _id="$1" _rest
  printf -v "$2" '%s' "${_id%%:*}"
  _rest="${_id#*:}"
  printf -v "$4" '%s' "${_rest##*:}"
  printf -v "$3" '%s' "${_rest%:*}"
}

# cron::honors_tz: the cron daemon takes CRON_TZ (cronie does; Debian's cron runs every entry in its own
# zone): FZX_CRON_HONORS_TZ 1 or 0, else whether cronie's crond is installed
cron::honors_tz() {
  case "${FZX_CRON_HONORS_TZ:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  command -v crond > /dev/null 2>&1 || [[ -x /usr/sbin/crond ]]
}

# cron::_root: CRON_ROOT, the prefix that reads root's files (none as root, `sudo -n` when it is cached);
# fails when sudo would ask
cron::_root() {
  CRON_ROOT=(command)
  ((EUID == 0)) && return 0
  command sudo -n true 2> /dev/null || return 1
  CRON_ROOT=(command sudo -n)
}

# cron::spool_dir: where every user's crontab is kept (FZX_CRON_SPOOL_DIR; Debian's crontabs directory,
# else cronie's /var/spool/cron)
cron::spool_dir() {
  if [[ -n "${FZX_CRON_SPOOL_DIR:-}" ]]; then printf '%s\n' "$FZX_CRON_SPOOL_DIR"
  elif [[ -d /var/spool/cron/crontabs ]]; then printf '/var/spool/cron/crontabs\n'
  else printf '/var/spool/cron\n'; fi
}

# cron::content <kind> <file>: the crontab's text: yours through crontab -l, another user's through sudo,
# a system file as it is
cron::content() {
  case "$1" in
    user) command crontab -l 2> /dev/null ;;
    spool) cron::_root && "${CRON_ROOT[@]}" cat -- "$2" 2> /dev/null ;;
    *) cat -- "$2" 2> /dev/null ;;
  esac
}

# cron::record <id>: the entry's record (cron::_parse's fields), read again from its file now; nothing when
# the line no longer holds an entry
cron::record() {
  local _k _f _l
  cron::split "$1" _k _f _l
  [[ "$_l" =~ ^[1-9][0-9]*$ ]] || return 1
  # the zone of a CRON_TZ line before it counts: the lines up to the entry, only its own record kept
  cron::content "$_k" "$_f" | sed -n "1,${_l}p" | cron::_parse "$_k" "$_f" "$([[ "$_k" == spool ]] && printf '%s' "${_f##*/}")" |
    awk -F '\t' -v OFS='\t' -v id="$1" -v want="$_k:$_f:$_l" '$1 == want { $1 = id; print; exit }'
}

# cron::env <id>: the VAR=value lines of the entry's crontab before it, as NAME=VALUE (quotes around the
# value removed), in order: cron hands them to the command
cron::env() {
  local _k _f _l
  cron::split "$1" _k _f _l
  cron::content "$_k" "$_f" | awk -v n="$_l" '
    NR >= n { exit }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ {
      line = $0; sub(/^[[:space:]]+/, "", line)
      name = line; sub(/[[:space:]]*=.*/, "", name)
      val = line; sub(/^[^=]*=[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
      if (val ~ /^".*"$/ || val ~ /^\047.*\047$/) val = substr(val, 2, length(val) - 2)
      print name "=" val
    }'
}

# cron::_ignored <name>: run-parts and cron skip file names outside [A-Za-z0-9_-] (*.dpkg-new, backups)
cron::_ignored() {
  [[ ! "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

# shellcheck disable=SC2094  # the file is the label and the input: _parse only reads
# cron::entries: every record of the mode's crontabs (scripts: the system's, to find each directory's runner)
cron::entries() {
  local mode="${FZX_MODE:-all}" f
  if [[ "$mode" == all || "$mode" == user ]]; then
    command crontab -l 2> /dev/null | cron::_parse user -
  fi
  if [[ "$mode" == all || "$mode" == system ]]; then
    # the other users' crontabs, readable with a cached sudo
    local spool me="${USER:-$(id -un)}" u
    spool="$(cron::spool_dir)"
    if cron::_root && [[ -n "$("${CRON_ROOT[@]}" ls -A -- "$spool" 2> /dev/null)" ]]; then
      while IFS= read -r u; do
        [[ -n "$u" && "$u" != "$me" && "$u" != .* ]] || continue
        "${CRON_ROOT[@]}" cat -- "$spool/$u" 2> /dev/null | cron::_parse spool "$spool/$u" "$u"
      done < <("${CRON_ROOT[@]}" ls -1 -- "$spool" 2> /dev/null)
    fi
  fi
  if [[ "$mode" != user ]]; then
    for f in ${FZX_CRON_SYSTEM_FILES:-/etc/crontab /etc/cron.d}; do
      if [[ -d "$f" ]]; then
        local g
        for g in "$f"/*; do
          [[ -f "$g" && -r "$g" ]] && ! cron::_ignored "${g##*/}" && cron::_parse system "$g" < "$g"
        done
      elif [[ -r "$f" ]]; then
        cron::_parse system "$f" < "$f"
      fi
    done
    f="${FZX_CRON_ANACRONTAB:-/etc/anacrontab}"
    [[ -r "$f" ]] && cron::_parse anacron "$f" < "$f"
  fi
  return 0
}

# cron::_next <records file>: the records with the next run's epoch appended (field 9; "" for none): one
# systemd-analyze call for every expression, one per expression when that fails (an expression it rejects
# would shift the answers). anacron jobs from their spool file's mtime
cron::_next() {
  local records="$1" exprs=() e out times spool="${FZX_CRON_ANACRON_SPOOL:-/var/spool/anacron}"
  mapfile -t exprs < <(awk -F '\t' '{ if ($6 != "") print $6; if ($7 != "") print $7 }' "$records" | sort -u)
  out=""
  if ((${#exprs[@]})); then
    if ! out="$(command systemd-analyze calendar --iterations=1 "${exprs[@]}" 2> /dev/null)"; then
      out=""
      for e in "${exprs[@]}"; do
        out+="$(command systemd-analyze calendar --iterations=1 "$e" 2> /dev/null || printf 'Normalized form: -\n    Next elapse: never')"$'\n'
      done
    fi
  fi
  # per expression, in order: its UTC time, or "never"
  times="$(awk '/Normalized form:/ { if (n++) print t; t = "never" } /\(in UTC\):/ { sub(/.*\(in UTC\): /, ""); t = $0 } END { if (n) print t }' <<< "$out" |
    while IFS= read -r t; do
      if [[ "$t" == never ]]; then echo never; else command date -d "$t" +%s 2> /dev/null || echo never; fi
    done)"
  awk -F '\t' -v OFS='\t' -v spool="$spool" -v now="${FZX_CRON_NOW:-$(date +%s)}" -v tz="$(date +%z)" '
    BEGIN { off = (substr(tz, 1, 1) == "-" ? -1 : 1) * (substr(tz, 2, 2) * 3600 + substr(tz, 4, 2) * 60) }
    function q(s) { gsub(/\047/, "\047\\\047\047", s); return "\047" s "\047" }
    NR == FNR { t[$1] = $2; next }
    {
      nx = ""
      if ($8 ~ /^anacron:/) {
        split($8, a, ":"); p = a[2]
        days = (p ~ /^[0-9]+$/ ? p : p == "@daily" ? 1 : p == "@weekly" ? 7 : p == "@monthly" ? 30 : 365)
        cmd = "stat -c %Y " q(spool "/" a[4]) " 2> /dev/null"; last = ""
        cmd | getline last; close(cmd)
        # anacron counts local days: the day after PERIOD days, at its local midnight
        nx = (last == "" ? now : int((last + off) / 86400) * 86400 - off + days * 86400)
        if (nx < now) nx = now
        $8 = $8 ":" last
      } else if ($8 == "") {
        for (i = 6; i <= 7; i++) if ($i != "" && t[$i] != "never" && t[$i] != "" && (nx == "" || t[$i] + 0 < nx + 0)) nx = t[$i]
      }
      print $0, nx
    }' <(paste <(printf '%s\n' "${exprs[@]}") <(printf '%s\n' "$times")) "$records"
}

# cron::_in <seconds from now> <var>: "in 25m", "in 7h 12m", "in 5d" ("due" when it has passed)
cron::_in() {
  local _s="$1" _o
  if ((_s <= 0)); then _o=due
  elif ((_s < 3600)); then _o="in $(((_s + 59) / 60))m"
  elif ((_s < 86400)); then _o="in $((_s / 3600))h $((_s % 3600 / 60))m"
  else _o="in $((_s / 86400))d $((_s % 86400 / 3600))h"; fi
  printf -v "$2" '%s' "$_o"
}

# cron::_rows <records with next>: the display rows, sorted
cron::_rows() {
  local mode="${FZX_MODE:-all}" sort="${FZX_SORT:-next}" now="${FZX_CRON_NOW:-$(date +%s)}"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" s=$'\e['"${FZX_COLORS[cron_schedule]:-38;5;110}m"
  local u=$'\e['"${FZX_COLORS[cron_user]:-38;5;180}m" x=$'\e['"${FZX_COLORS[cron_invalid]:-38;5;203}m"
  local hl=$'\e['"${FZX_COLORS[sorted]:-4}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && d="" s="" u="" x="" hl="" r=""
  # the header row (lib/header.sh); the command is not padded, so its source is left unnamed
  fzx::require header
  fzx::header_print 2 "$([[ "$sort" == next ]] && echo NEXT)" NEXT 12 0 "" 0 0 SCHEDULE 18 0 "" 0 0 USER 8 0 "" 0 0 COMMAND 0 0
  awk -F '\t' -v OFS='\t' -v now="$now" -v sort="$sort" -v d="$d" -v s="$s" -v u="$u" -v x="$x" -v hl="$hl" -v r="$r" '
    function rel(t,   n) {
      n = t - now
      if (n <= 0) return "due"
      if (n < 3600) return "in " int((n + 59) / 60) "m"
      if (n < 86400) return "in " int(n / 3600) "h " int(n % 3600 / 60) "m"
      return "in " int(n / 86400) "d " int(n % 86400 / 3600) "h"
    }
    function pad(t, w) { return length(t) > w ? substr(t, 1, w - 1) "…" : sprintf("%-" w "s", t) }
    {
      split($1, id, ":"); f = $1; sub(/^[^:]+:/, "", f); line = f; sub(/.*:/, "", line); sub(/:[0-9]+$/, "", f)
      src = (f == "-" ? "crontab" : $2 == "spool" ? $3 "\047s crontab" : f) (line > 0 ? ":" line : "")
      sched = $4
      if ($8 ~ /^anacron(-off)?:/) { split($8, a, ":"); sched = (a[2] ~ /^[0-9]+$/ ? "every " a[2] "d" : a[2]) }
      off = ($8 == "disabled" || $8 ~ /^anacron-off:/)
      if (off) nx = "disabled"
      else if ($8 == "reboot") nx = "at boot"
      else if ($8 == "invalid") nx = "invalid"
      else if ($9 == "") nx = "never"
      else nx = rel($9)
      nc = (nx == "invalid" ? x : (nx == "disabled" || nx == "at boot" || nx == "never") ? d : "")
      nxs = (sort == "next" ? nc hl pad(nx, 12) r : nc pad(nx, 12) r)
      srt = (sort == "next" ? ($9 == "" ? 9999999999 : $9) : sprintf("%s %06d", f, line))
      disp = nxs "  " s pad(sched, 18) r "  " u pad($3, 8) r "  " (off ? d $5 r : $5) "  " d src r
      print srt, $1, $5, disp
    }' "$1" | sort -t $'\t' -k1,1 -s | cut -f2-
}

# cron::scripts <records with next>: the run-parts directories' scripts, each with the next run of the job
# that runs its directory (an anacron job before a crontab line: /etc/crontab defers to anacron)
cron::scripts() {
  local recs="$1" dir f period nx job now="${FZX_CRON_NOW:-$(date +%s)}" when name
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" s=$'\e['"${FZX_COLORS[cron_schedule]:-38;5;110}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && d="" s="" r=""
  for dir in ${FZX_CRON_SCRIPT_DIRS:-/etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.yearly}; do
    [[ -d "$dir" ]] || continue
    period="${dir##*/}" period="${period#cron.}"
    IFS=$'\t' read -r nx job < <(awk -F '\t' -v dir="$dir" '
      index($5, dir) && $8 != "disabled" && $8 !~ /^anacron-off:/ { k = ($2 == "anacron" ? 0 : 1); if (!(k in best) || $9 < nx[k]) { best[k] = $1; nx[k] = $9 } }
      END { if (0 in best) print nx[0] "\t" best[0]; else if (1 in best) print nx[1] "\t" best[1] }' "$recs")
    if [[ -z "$job" ]]; then when="no job runs it"
    elif [[ -z "$nx" ]]; then when=never
    else cron::_in $((nx - now)) when; fi
    for f in "$dir"/*; do
      [[ -f "$f" ]] || continue
      name="${f##*/}"
      if cron::_ignored "$name"; then
        printf 'script:%s:0\t%s\t%s%-12s  %-18s  %s  (skipped: run-parts ignores the name)%s\n' "$f" "$f" "$d" "$when" "$period" "$name" "$r"
      elif [[ ! -x "$f" ]]; then
        printf 'script:%s:0\t%s\t%s%-12s  %-18s  %s  (not executable: skipped)%s\n' "$f" "$f" "$d" "$when" "$period" "$name" "$r"
      else
        printf 'script:%s:0\t%s\t%-12s  %s%-18s%s  %s  %s%s%s\n' "$f" "$f" "$when" "$s" "$period" "$r" "$name" "$d" "$dir" "$r"
      fi
    done
  done
}

cron::source() {
  local mode="${FZX_MODE:-all}" tmp
  case "$mode" in
    all | user | system | scripts) ;;
    *)
      printf 'cron: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
  tmp="$(mktemp)" || return
  # shellcheck disable=SC2064  # the path now
  trap "rm -f '$tmp' '$tmp.next'" RETURN
  if [[ "$mode" == scripts ]]; then FZX_MODE=system cron::entries > "$tmp"; else cron::entries > "$tmp"; fi
  cron::_next "$tmp" > "$tmp.next"
  if [[ "$mode" == scripts ]]; then cron::scripts "$tmp.next"; else cron::_rows "$tmp.next"; fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" cron
  cron::source "$@"
}
