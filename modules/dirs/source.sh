#!/usr/bin/env bash
# dirs source. Lines are "absolute path<TAB>display", best match first.
# Mode from $FZX_MODE: zlua (z.lua frecency), frecent (zoxide), fasd (fasd frecency), recent (fasd, by
# last access), bookmarks (FZX_DIRS_BOOKMARKS), all (every directory under ~, by fd). Module args are query
# words, passed to z.lua/zoxide/fasd as keywords (the all mode ignores them; they become the fzf query).

# dirs::zlua <var>: the z.lua script (FZX_DIRS_ZLUA, or found in the usual places), or fail
dirs::zlua() {
  local _s="${FZX_DIRS_ZLUA:-}" _c
  [[ "$_s" == none ]] && return 1
  if [[ -z "$_s" ]]; then
    for _c in "${ZLUA_SCRIPT:-}" "$HOME"/.zinit/plugins/*z.lua/z.lua "$HOME"/.local/share/zinit/plugins/*z.lua/z.lua \
      "$HOME/.local/share/z.lua/z.lua"; do
      [[ -n "$_c" && -f "$_c" ]] && { _s="$_c"; break; }
    done
  fi
  [[ -n "$_s" && -f "$_s" ]] || return 1
  printf -v "$1" '%s' "$_s"
}

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

# dirs::format: "score<TAB>path" lines -> "path<TAB>display" (missing directories dropped)
dirs::format() {
  local dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m' in
  fzx::require pretty
  if fzx::pretty_on; then
    # prettypath decorates the paths; joined back to their scores by path, in the input's order (by path,
    # not by line: an older prettypath can drop lines)
    in="$(cat)"
    [[ -n "$in" ]] || return 0
    awk -F'\t' -v dim="$dim" -v rst="$rst" 'NR == FNR { shown[$1] = $2; next }
      { path = $2; sub(/\/$/, "", path)
        # a path prettypath did not return (an older version drops some) keeps a plain display
        disp = (path in shown) ? shown[path] : "  " path
        printf "%s\t%s%7s%s  %s\n", path, dim, $1, rst, disp }' \
      <(cut -f2 <<< "$in" | fzx::pretty --dirs) - <<< "$in" |
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
  local zl
  # already "path<TAB>display", and too long for the existence check below
  if [[ "${FZX_MODE:-}" == all ]]; then
    dirs::all
    return
  fi
  case "${FZX_MODE:-frecent}" in
    zlua)
      if ! dirs::zlua zl; then
        printf 'dirs: z.lua not found (set FZX_DIRS_ZLUA)\n' >&2
        return 2
      fi
      # z.lua lists the best match last
      command "$FZX_DIRS_ZLUA_LUA" "$zl" -l "$@" | tac |
        awk '{ s = $1; sub(/^ *[^ ]+ +/, ""); printf "%s\t%s\n", (s < 10 ? sprintf("%.1f", s) : sprintf("%.0f", s)), $0 }'
      ;;
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
