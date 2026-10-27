#!/usr/bin/env bash
# dirs source. Lines are "absolute path<TAB>display".
# Mode from $FZX_MODE: all (every directory under ~, by fd), bookmarks (FZX_DIRS_BOOKMARKS, by name).
# Frecent and recently visited directories are modes of the recent module. Module args are query words:
# they become the fzf query (all) or filter the bookmark names and paths (bookmarks).

# fd is packaged as fdfind on Debian/Ubuntu
dirs::has_fd() { command -v fd > /dev/null || command -v fdfind > /dev/null; }
dirs::fd() {
  if command -v fd > /dev/null; then command fd "$@"; else command fdfind "$@"; fi
}

# dirs::all: every directory under ~ as "path<TAB>display", streamed (fd found them: no existence check)
dirs::all() {
  local args=(--hidden --follow --one-file-system --type d --color=never) ex dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m'
  [[ -n "${FZX_DIRS_ALL_DEPTH:-}" ]] && args+=(--max-depth "$FZX_DIRS_ALL_DEPTH")
  for ex in "${FZX_DIRS_ALL_EXCLUDES[@]}"; do args+=(--exclude "$ex"); done
  fzx::require pretty
  if fzx::pretty_on; then
    dirs::fd "${args[@]}" . "$HOME" | fzx::pretty "$HOME"
  else
    dirs::fd "${args[@]}" . "$HOME" | awk -v home="$HOME/" -v dim="$dim" -v rst="$rst" '
      { path = $0; sub(/\/$/, "", path); rel = substr(path, 1, length(home)) == home ? substr(path, length(home) + 1) : path
        n = split(rel, parts, "/"); printf "%s\t%s%s%s%s\n", path, dim, substr(rel, 1, length(rel) - length(parts[n])), rst, parts[n] }'
  fi
  return "${PIPESTATUS[0]}"
}

# dirs::format: "name<TAB>path" lines -> "path<TAB>display" (missing directories dropped); the column
# FZX_SORT orders by (bookmarks: name or path) is drawn in FZX_COLORS[sorted] as well
dirs::format() {
  local dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m' in hl=$'\e['"${FZX_COLORS[sorted]:-4}m" hn="" hp=""
  case "${FZX_SORT:-}" in name) hn="$hl" ;; path) hp="$hl" ;; esac
  fzx::require pretty
  if fzx::pretty_on; then
    # prettypath decorates the paths; joined back to their scores by path, in the input's order (by path,
    # not by line: an older prettypath can drop lines)
    in="$(cat)"
    [[ -n "$in" ]] || return 0
    awk -F'\t' -v dim="$dim" -v rst="$rst" -v hn="$hn" -v hp="$hp" 'NR == FNR { shown[$1] = $2; next }
      { path = $2; sub(/\/$/, "", path)
        # a path prettypath did not return (an older version drops some) keeps a plain display
        disp = (path in shown) ? shown[path] : "  " path
        if (hp != "") { gsub(/\033\[0m/, "&" hp, disp); disp = hp disp rst }
        printf "%s\t%s%*s%s%s  %s\n", path, dim, 7 - length($1), "", hn $1, rst, disp }' \
      <(cut -f2 <<< "$in" | fzx::pretty --dirs) - <<< "$in" |
      while IFS= read -r line; do
        [[ -d "${line%%$'\t'*}" ]] && printf '%s\n' "$line"
      done
    return 0
  fi
  awk -F'\t' -v home="$HOME" -v dim="$dim" -v rst="$rst" -v hn="$hn" -v hp="$hp" '
    { path = $2; shown = path
      if (index(shown, home) == 1) shown = "~" substr(shown, length(home) + 1)
      n = split(shown, parts, "/"); name = parts[n]; parent = substr(shown, 1, length(shown) - length(name))
      printf "%s\t%s%*s%s%s  %s%s%s%s%s\n", path, dim, 7 - length($1), "", hn $1, rst, dim, hp parent, rst, hp name, rst }' |
    while IFS= read -r line; do
      [[ -d "${line%%$'\t'*}" ]] && printf '%s\n' "$line"
    done
}

# dirs::source [query words...]
dirs::source() {
  local name
  case "${FZX_MODE:-all}" in
    # already "path<TAB>display", and too long for dirs::format's existence check
    all) dirs::all ;;
    bookmarks)
      for name in "${!FZX_DIRS_BOOKMARKS[@]}"; do
        printf '%s\t%s\n' "$name" "${FZX_DIRS_BOOKMARKS[$name]/#\~/$HOME}"
      done | sort -t $'\t' -k"$([[ "${FZX_SORT:-name}" == path ]] && echo 2 || echo 1)" | awk -F'\t' -v words="$*" 'BEGIN { n = split(tolower(words), w, " ") }
        { s = tolower($0); for (i = 1; i <= n; i++) if (!index(s, w[i])) next; print }' | dirs::format
      ;;
    *)
      printf 'dirs: unknown mode: %s (frecent directories are in the recent module)\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" dirs
  dirs::source "$@"
}
