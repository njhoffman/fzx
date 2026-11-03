#!/usr/bin/env bash
# claude source: Claude Code projects from `claude-projects --tsv` (~/.shell): your own projects with a
# CLAUDE.md, and every other directory Claude has sessions for. The scan takes seconds, so it is kept in
# $FZX_CACHE_DIR/claude/projects (claude::refresh, bound to start in the background); only an open with no
# cache at all waits for it. Rows are "path<TAB>display".
# Modes: all, own (your projects with a CLAUDE.md), active (uncommitted, unpushed, or a session in the last
# FZX_CLAUDE_ACTIVE_DAYS days). Sort: recent (last session, newest first) or name.
#
# The cached columns are claude-projects' own: 1 path, 2 name, 3 mode, 4 version, 5 branch, 6 dirty,
# 7 ahead, 8 behind, 9 open, 10 p1, 11 overdue, 12 last session (epoch, 0 = none), 13 sessions, 14 source.

claude::cache_file() { printf '%s/claude/projects' "$FZX_CACHE_DIR"; }

# claude::scan: the rows claude-projects prints now
claude::scan() {
  command -v claude-projects > /dev/null || { printf 'claude: claude-projects is not on PATH\n' >&2; return 127; }
  claude-projects --tsv --plain
}

# claude::lock / claude::unlock: one scan at a time (a lock older than 10 minutes is a dead scan's)
claude::lock() {
  local lock="${1%/*}/scan.lock"
  mkdir -p -- "${1%/*}"
  if [[ -d "$lock" ]] && (($(date +%s) - $(stat -c %Y "$lock") > 600)); then rmdir -- "$lock" 2> /dev/null; fi
  mkdir -- "$lock" 2> /dev/null
}
claude::unlock() { rmdir -- "${1%/*}/scan.lock" 2> /dev/null || :; }

# claude::refresh [force]: scan into the cache unless it is younger than FZX_CLAUDE_TTL; true when the cache
# changed. A failed scan leaves the cache as it was.
claude::refresh() {
  local cache tmp
  cache="$(claude::cache_file)"
  if [[ "${1:-}" != force && -f "$cache" ]] && (($(date +%s) - $(stat -c %Y "$cache") < ${FZX_CLAUDE_TTL:-120})); then
    return 1
  fi
  claude::lock "$cache" || return 1
  tmp="$cache.$BASHPID"
  if ! claude::scan > "$tmp" || [[ ! -s "$tmp" ]]; then
    rm -f -- "$tmp"
    claude::unlock "$cache"
    return 1
  fi
  claude::unlock "$cache"
  if [[ -f "$cache" ]] && cmp -s -- "$tmp" "$cache"; then
    rm -f -- "$tmp"
    touch -- "$cache"
    return 1
  fi
  mv -f -- "$tmp" "$cache"
}

claude::source() {
  local cache
  cache="$(claude::cache_file)"
  # the first open ever waits for the scan; later ones show the cache and refresh behind it
  [[ -f "$cache" ]] || claude::refresh force || :
  [[ -f "$cache" ]] || return 0
  fzx::require icons
  fzx::icon_vars branch changed ahead behind todo
  awk -F'\t' -v OFS='\t' "${FZX_ICON_VARS[@]}" -v mode="${FZX_MODE:-all}" -v sort="${FZX_SORT:-recent}" \
    -v now="$(date +%s)" -v active_days="${FZX_CLAUDE_ACTIVE_DAYS:-7}" \
    -v c_name=$'\e['"${FZX_COLORS[claude_name]:-1;38;5;111}m" -v c_dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" \
    -v c_git=$'\e['"${FZX_COLORS[claude_mode_git]:-38;5;110}m" \
    -v c_dotbare=$'\e['"${FZX_COLORS[claude_mode_dotbare]:-38;5;140}m" \
    -v c_plain=$'\e['"${FZX_COLORS[claude_mode_plain]:-38;5;180}m" \
    -v c_branch=$'\e['"${FZX_COLORS[claude_branch]:-38;5;81}m" \
    -v c_changed=$'\e['"${FZX_COLORS[claude_changed]:-38;5;255}m" \
    -v c_ahead=$'\e['"${FZX_COLORS[claude_ahead]:-38;5;114}m" -v c_behind=$'\e['"${FZX_COLORS[claude_behind]:-38;5;203}m" \
    -v c_todo=$'\e['"${FZX_COLORS[claude_todo]:-38;5;117}m" -v c_p1=$'\e['"${FZX_COLORS[claude_p1]:-38;5;203}m" \
    -v rst=$'\e[0m' -v hl=$'\e['"${FZX_COLORS[sorted]:-4}m" '
    function age(t,   s) {
      if (t + 0 == 0) return ""
      s = now - t
      if (s < 3600) return int(s / 60) "m"
      if (s < 86400) return int(s / 3600) "h"
      if (s < 86400 * 14) return int(s / 86400) "d"
      if (s < 86400 * 60) return int(s / 604800) "w"
      if (s < 86400 * 365) return int(s / 2592000) "mo"
      return int(s / 31536000) "y"
    }
    function pad(s, w,   n) { n = w - length(s); return n > 0 ? sprintf("%" n "s", "") : " " }
    NF >= 14 {
      dir = $1; name = $2; kind = $3; version = $4; branch = $5
      dirty = $6 + 0; ahead = $7 + 0; behind = $8 + 0; open = $9 + 0; p1 = $10 + 0; last = $12 + 0
      sessions = $13 + 0; src = $14
      if (mode == "own" && src != "own") next
      if (mode == "active" && !dirty && !ahead && !(last && now - last < active_days * 86400)) next
      # a dim * marks a directory found only through its sessions (no CLAUDE.md of yours)
      star = (src == "own") ? " " : "*"
      kc = (kind == "git") ? c_git : (kind == "dotbare") ? c_dotbare : (kind == "plain") ? c_plain : c_dim
      flags = (dirty ? c_changed icon_changed " " dirty rst " " : "") (ahead ? c_ahead icon_ahead " " ahead rst " " : "") \
        (behind ? c_behind icon_behind " " behind rst " " : "") \
        (open ? c_todo icon_todo " " open rst (p1 ? c_p1 " !" p1 rst : "") " " : "")
      bicon = (branch != "" && icon_branch != "") ? icon_branch " " : (icon_branch != "" ? "  " : "")
      a = age(last)
      line = dir "\t" c_name (sort == "name" ? hl : "") name rst c_dim star rst pad(name star, 22) \
        kc kind rst pad(kind, 9) c_dim version rst pad(version, 9) c_branch bicon branch rst pad(branch, 16) \
        sprintf("%" (4 - length(a)) "s", "") c_dim (sort == "name" ? "" : hl) a rst " " c_dim sprintf("%4s", sessions ? sessions : "") rst "  " flags
      key = (sort == "name") ? tolower(name) : sprintf("%012d", 999999999999 - last)
      print key "\t" line
    }' "$cache" | sort -t $'\t' -k1,1 | cut -f2-
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" claude
  claude::source "$@"
}
