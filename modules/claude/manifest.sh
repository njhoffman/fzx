#!/usr/bin/env bash
# claude menu entries

claude::manifest() {
  fzx::entry claude "Claude Code projects"
  fzx::entry claude:active "Claude Code projects in use"
}

claude::applicable() { command -v claude-projects > /dev/null; }

# from the last scan; the module refreshes it
claude::summary() {
  local cache="${FZX_CACHE_DIR}/claude/projects"
  [[ -f "$cache" ]] || return 0
  awk -F'\t' -v now="$(date +%s)" -v days="${FZX_CLAUDE_ACTIVE_DAYS:-7}" -v entry="$1" "$FZX_AWK_PLURAL"'
    NF >= 14 {
      n++; if ($14 == "own") own++
      if ($6 > 0 || $7 > 0 || ($12 > 0 && now - $12 < days * 86400)) act++
    }
    END {
      if (entry == "claude") printf "%s, %d yours\n", plural(n, "project"), own
      else printf "%d in use\n", act
    }' "$cache"
}
