#!/usr/bin/env bash
# files source. Lines are "absolute path<TAB>display" (files, dirs) or
# "absolute path<TAB>line<TAB>display" (grep). Mode from $FZX_MODE: files (default), dirs, grep.
# grep searches for $FZF_QUERY, which fzf exports to the reload it runs on every query change.

# files::base [DIR]: absolute base directory into FILES_BASE; a file argument means its directory
files::base() {
  local dir="${1:-$PWD}"
  if [[ -f "$dir" ]]; then
    if [[ "$dir" == */* ]]; then dir="${dir%/*}"; else dir=.; fi
    dir="${dir:-/}"
  fi
  if [[ ! -d "$dir" ]]; then
    printf 'files: not a directory: %s\n' "$dir" >&2
    return 2
  fi
  # physical path: fd and rg report resolved paths, so a symlinked base would never prefix-match
  FILES_BASE="$(cd -- "$dir" && pwd -P)"
}

# fd is packaged as fdfind on Debian/Ubuntu
files::fd() {
  if command -v fd > /dev/null; then
    command fd "$@"
  else
    command fdfind "$@"
  fi
}

# files::source [DIR]
files::source() {
  local mode="${FZX_MODE:-files}" dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m'
  (($# <= 1)) || {
    printf 'files: at most one directory, got: %s\n' "$*" >&2
    return 2
  }
  files::base "${1:-}" || return
  case "$mode" in
    files | dirs)
      local type=f
      [[ "$mode" == dirs ]] && type=d
      fzx::require pretty
      if fzx::pretty_on; then
        files::fd --type "$type" --hidden --follow --exclude .git --color=never --absolute-path . "$FILES_BASE" |
          fzx::pretty "$FILES_BASE"
        return "${PIPESTATUS[0]}"
      fi
      files::fd --type "$type" --hidden --follow --exclude .git --color=never --absolute-path . "$FILES_BASE" |
        awk -v base="$FILES_BASE/" -v dim="$dim" -v rst="$rst" '
          { path = $0; sub(/\/$/, "", path); rel = substr(path, 1, length(base)) == base ? substr(path, length(base) + 1) : path
            n = split(rel, parts, "/"); dir = substr(rel, 1, length(rel) - length(parts[n]))
            printf "%s\t%s%s%s%s\n", path, dim, dir, rst, parts[n] }'
      return "${PIPESTATUS[0]}"
      ;;
    grep)
      local query="${FZF_QUERY:-}" rc
      [[ -n "$query" ]] || return 0
      command rg --line-number --no-heading --color=never --smart-case --hidden --glob '!.git' \
        -- "$query" "$FILES_BASE" |
        awk -v base="$FILES_BASE/" -v dim="$dim" -v rst="$rst" '
          { i = index($0, ":"); path = substr($0, 1, i - 1); rest = substr($0, i + 1)
            j = index(rest, ":"); line = substr(rest, 1, j - 1); text = substr(rest, j + 1)
            rel = substr(path, 1, length(base)) == base ? substr(path, length(base) + 1) : path
            printf "%s\t%s\t%s%s:%s:%s %s\n", path, line, dim, rel, line, rst, text }'
      rc="${PIPESTATUS[0]}"
      # rg exits 1 when nothing matches
      ((rc <= 1)) || return "$rc"
      return 0
      ;;
    *)
      printf 'files: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" files
  files::source "$@"
}
