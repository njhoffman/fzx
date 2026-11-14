#!/usr/bin/env bash
# browser preview, from the row's fields: the title, the URL split into host and path, the browser and
# profile, and the visits and last visit (history), the folder and date added (bookmarks) or the window (tabs)

# browser::preview <src> <url> <title> <extra> <date> <label>
browser::preview() {
  local src="${1:-}" url="${2:-}" title="${3:-}" extra="${4:-}" date="${5:-}" label="${6:-}" host rest
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' c
  c=$'\e['"${FZX_COLORS[browser_chrome]:-38;5;75}m"
  [[ "$src" == firefox:* ]] && c=$'\e['"${FZX_COLORS[browser_firefox]:-38;5;209}m"
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r="" c=""
  # a profile whose tabs could not be read: its row says why
  [[ -n "$url" ]] || { [[ -n "$title" ]] && printf '%s\n' "$title"; return 0; }
  # shellcheck disable=SC2119  # no fields: the whole text
  printf '%s%s%s\n\n' "$b" "${title:-(no title)}" "$r" | fzx::glyphs_plain
  printf '%s\n' "$url"
  # scheme://host/path: the host on its own line
  if [[ "$url" =~ ^[a-z]+://([^/]+)(.*)$ ]]; then
    host="${BASH_REMATCH[1]}" rest="${BASH_REMATCH[2]}"
    printf '\n%shost%s     %s\n' "$d" "$r" "$host"
    [[ -n "$rest" && "$rest" != / ]] && printf '%spath%s     %s\n' "$d" "$r" "${rest%%\?*}"
  fi
  printf '%sprofile%s  %s%s%s\n' "$d" "$r" "$c" "$label" "$r"
  if [[ "${FZX_MODE:-history}" == bookmarks ]]; then
    printf '%sfolder%s   %s\n' "$d" "$r" "${extra:-(top)}"
    [[ -n "$date" ]] && printf '%sadded%s    %s\n' "$d" "$r" "$date"
  elif [[ "${FZX_MODE:-history}" == tabs ]]; then
    printf '%swindow%s   %s\n' "$d" "$r" "${extra#window }"
  else
    printf '%svisits%s   %s\n' "$d" "$r" "$extra"
    printf '%slast%s     %s\n' "$d" "$r" "$date"
  fi
  return 0
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" browser
  browser::preview "$@"
}
