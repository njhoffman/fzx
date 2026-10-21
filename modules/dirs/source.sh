#!/usr/bin/env bash
# dirs source. Lines are "absolute path<TAB>display", best match first.
# Mode from $FZX_MODE: frecent (zoxide), fasd (fasd frecency), recent (fasd, by last access),
# bookmarks (FZX_DIRS_BOOKMARKS). Module args are query words, passed to zoxide/fasd as keywords.

# dirs::format: "score<TAB>path" lines -> "path<TAB>display" (missing directories dropped)
dirs::format() {
  local dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m' in
  fzx::require pretty
  if fzx::pretty_on; then
    # prettypath decorates the paths; joined back to their scores by path, in the input's order
    in="$(cat)"
    [[ -n "$in" ]] || return 0
    awk -F'\t' -v dim="$dim" -v rst="$rst" 'NR == FNR { shown[$1] = $2; next }
      { path = $2; sub(/\/$/, "", path); if (path in shown) printf "%s\t%s%7s%s  %s\n", path, dim, $1, rst, shown[path] }' \
      <(cut -f2 <<< "$in" | fzx::pretty) - <<< "$in" |
      while IFS= read -r line; do
        [[ -d "${line%%$'\t'*}" ]] && printf '%s\n' "$line"
      done
    return 0
  fi
  awk -F'\t' -v home="$HOME" -v dim="$dim" -v rst="$rst" '
    { path = $2; shown = path
      if (index(shown, home) == 1) shown = "~" substr(shown, length(home) + 1)
      n = split(shown, parts, "/"); name = parts[n]; parent = substr(shown, 1, length(shown) - length(name))
      printf "%s\t%s%7s%s  %s%s%s%s\n", path, dim, $1, rst, dim, parent, rst, name }' |
    while IFS= read -r line; do
      [[ -d "${line%%$'\t'*}" ]] && printf '%s\n' "$line"
    done
}

# dirs::source [query words...]
dirs::source() {
  case "${FZX_MODE:-frecent}" in
    frecent)
      command zoxide query --list --score -- "$@" |
        awk '{ s = $1; sub(/^ *[^ ]+ +/, ""); printf "%s\t%s\n", (s < 10 ? sprintf("%.1f", s) : sprintf("%.0f", s)), $0 }'
      ;;
    fasd)
      command fasd -d -R -s "$@" | awk '{ s = $1; sub(/^[^ ]+ +/, ""); printf "%s\t%s\n", (s < 10 ? sprintf("%.1f", s) : sprintf("%.0f", s)), $0 }'
      ;;
    recent)
      command fasd -d -t -R -l "$@" | awk '{ printf "%d\t%s\n", NR, $0 }'
      ;;
    bookmarks)
      local name
      for name in "${!FZX_DIRS_BOOKMARKS[@]}"; do
        printf '%s\t%s\n' "$name" "${FZX_DIRS_BOOKMARKS[$name]/#\~/$HOME}"
      done | sort
      ;;
    *)
      printf 'dirs: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac | dirs::format
  # zoxide and fasd exit non-zero when nothing matches the query; an empty list is not an error
  return 0
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" dirs
  dirs::source "$@"
}
