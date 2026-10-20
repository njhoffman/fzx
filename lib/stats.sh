#!/usr/bin/env bash
# stats: append-only usage statistics, one TSV row per event, and the `fzx stats` summary.
#
# columns: ts_ms root sid module mode event duration_ms count detail
#   start   the owner launched a new tree             detail: module args
#   exit    the tree ended                            duration: whole run, sid/module/mode: where it ended,
#                                                     detail: rc:<n> <accept|nomatch|error|abort|rc>
#   source  the module source ran                     count: lines, detail: miss|reload|fail:<rc>
#   cache   data served from cache                    count: lines, detail: session|persistent
#   action  a module action ran                       count: items, detail: <action>:<rc>
#   mode    mode switch                               detail: <from>><to>[:restart]
#   nav     navigation                                detail: goto:<module>|back|back:none|resume|popout:<in|out>
# Callbacks do not load config, so FZX_STATS and FZX_STATS_FILE reach them through the environment.

FZX_STATS="${FZX_STATS:-1}"
FZX_STATS_FILE="${FZX_STATS_FILE:-$FZX_STATE_DIR/stats.tsv}"
export FZX_STATS FZX_STATS_FILE

# fzx::stat <event> <duration_ms> <count> <detail>; for the attached session, FZX_MODULE and FZX_MODE
fzx::stat() {
  [[ "$FZX_STATS" == 1 ]] || return 0
  local _root="" _now _detail="${4:--}"
  fzx::meta_get root _root || _root="${FZX_SESSION:--}"
  fzx::now_ms _now
  _detail="${_detail//[$'\t\n\r']/ }"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_now" "$_root" "${FZX_SESSION:--}" "${FZX_MODULE:--}" \
    "${FZX_MODE:--}" "$1" "${2:-0}" "${3:--}" "$_detail" >> "$FZX_STATS_FILE" 2> /dev/null
  return 0
}

# fzx::stats [--since DURATION] [--module NAME] [--raw]
fzx::stats() {
  local since="" since_s=0 module="" raw=0 cutoff=0
  while (($#)); do
    case "$1" in
      --since)
        since="${2:-}"
        shift
        ;;
      --since=*) since="${1#*=}" ;;
      --module)
        module="${2:-}"
        shift
        ;;
      --module=*) module="${1#*=}" ;;
      --raw) raw=1 ;;
      *)
        printf 'usage: fzx stats [--since 90s|5m|2h|7d] [--module NAME] [--raw]\n' >&2
        return 2
        ;;
    esac
    shift
  done
  if [[ -n "$since" ]]; then
    fzx::parse_duration "$since" since_s || fzx::die 2 "invalid --since: $since (e.g. 90s, 5m, 2h, 7d)"
    cutoff=$(((EPOCHSECONDS - since_s) * 1000))
  fi
  if [[ ! -s "$FZX_STATS_FILE" ]]; then
    printf 'no stats recorded yet (%s)\n' "$FZX_STATS_FILE"
    return 0
  fi

  if ((raw)); then
    printf 'ts_ms\troot\tsid\tmodule\tmode\tevent\tduration_ms\tcount\tdetail\n'
    awk -F'\t' -v cutoff="$cutoff" -v module="$module" \
      '$1 >= cutoff && (module == "" || $4 == module)' "$FZX_STATS_FILE"
    return 0
  fi

  awk -F'\t' -v cutoff="$cutoff" -v module="$module" '
    function dur(ms) {
      if (ms < 1000) return sprintf("%dms", ms)
      if (ms < 60000) return sprintf("%.1fs", ms / 1000)
      if (ms < 3600000) return sprintf("%dm%02ds", ms / 60000, (ms % 60000) / 1000)
      return sprintf("%dh%02dm", ms / 3600000, (ms % 3600000) / 60000)
    }
    function avg(sum, n) { return n ? sum / n : 0 }
    $1 < cutoff || (module != "" && $4 != module) { next }
    {
      m = $4; seen[m] = 1
      if ($1 > last[m]) last[m] = $1
    }
    $6 == "start"  { runs[m]++ }
    # an exit is credited to the module the tree started in
    $6 == "exit"   { rm = startmod[$2] != "" ? startmod[$2] : m
                     exits[rm]++; tsum[rm] += $7; if ($7 > tmax[rm]) tmax[rm] = $7
                     split($9, ex, " "); kind[rm, ex[2]]++ }
    $6 == "start"  { startmod[$2] = m }
    $6 == "source" && $9 !~ /^fail/ { src[m]++; ssum[m] += $7; if ($7 > smax[m]) smax[m] = $7
                                      if ($8 != "-") { isum[m] += $8; in_[m]++ }
                                      if ($9 == "miss") miss[m]++ }
    $6 == "source" && $9 ~ /^fail/  { fail[m]++ }
    $6 == "cache"  { hit[m]++ }
    $6 == "action" { act[m]++ }
    $6 == "mode" || $6 == "nav" { nav[m]++ }
    END {
      n = 0
      for (m in seen) order[++n] = m
      # most runs first, then name
      for (i = 2; i <= n; i++) for (j = i; j > 1; j--) {
        a = order[j - 1]; b = order[j]
        if (runs[b] > runs[a] || (runs[b] == runs[a] && b < a)) { order[j - 1] = b; order[j] = a } else break
      }
      fmt = "%-12s %5s  %-16s  %-15s  %-22s  %6s  %6s  %-15s  %7s  %4s\n"
      printf fmt, "MODULE", "RUNS", "LAST USED", "RUN avg/max", "SOURCE n avg/max", "ITEMS", "CACHE", "ACCEPT/ABORT", "ACTIONS", "NAV"
      for (i = 1; i <= n; i++) {
        m = order[i]
        loads = hit[m] + miss[m]
        printf fmt, m, runs[m] + 0, strftime("%Y-%m-%d %H:%M", int(last[m] / 1000)),
          exits[m] ? dur(avg(tsum[m], exits[m])) "/" dur(tmax[m]) : "-",
          src[m] ? sprintf("%d %s/%s", src[m], dur(avg(ssum[m], src[m])), dur(smax[m])) (fail[m] ? sprintf(" (%d failed)", fail[m]) : "") : (fail[m] ? sprintf("0 (%d failed)", fail[m]) : "-"),
          in_[m] ? sprintf("%d", avg(isum[m], in_[m])) : "-",
          loads ? sprintf("%d%%", 100 * hit[m] / loads) : "-",
          exits[m] ? sprintf("%d/%d", kind[m, "accept"], kind[m, "abort"]) : "-",
          act[m] + 0, nav[m] + 0
      }
    }' "$FZX_STATS_FILE"
}

# keep the stats file bounded: once it exceeds 1 MiB, drop rows older than FZX_STATS_MAX_AGE_DAYS.
# Rows appended while the file is rewritten can be lost; acceptable for usage statistics.
fzx::stats_prune() {
  local size cutoff tmp="$FZX_STATS_FILE.$BASHPID"
  [[ -f "$FZX_STATS_FILE" ]] || return 0
  size="$(stat -c %s -- "$FZX_STATS_FILE")" || return 0
  ((size > 1048576)) || return 0
  cutoff=$(((EPOCHSECONDS - ${FZX_STATS_MAX_AGE_DAYS:-90} * 86400) * 1000))
  # (a variable, not $BASHPID in the redirection: that would expand in the forked awk)
  awk -F'\t' -v cutoff="$cutoff" '$1 >= cutoff' "$FZX_STATS_FILE" > "$tmp" && mv -f -- "$tmp" "$FZX_STATS_FILE"
  fzx::log info "stats: pruned rows older than ${FZX_STATS_MAX_AGE_DAYS:-90} days"
}
