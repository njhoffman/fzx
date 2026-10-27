#!/usr/bin/env bash
# files source. Lines are "absolute path<TAB>display" (files, dirs), sorted by path, or
# "absolute path<TAB>line<TAB>display" (grep). Mode from $FZX_MODE: files (default), dirs, grep.
# grep searches for $FZF_QUERY, which fzf exports to the reload it runs on every query change, with ripgrep,
# else grep. Toggles: hidden (on at start), ignored, follow (symbolic links listed, not entered, while off).
# Sorts: path, recent.

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

# files::on <toggle>: that toggle is on (hidden is on at start, ignored and follow off)
files::on() { [[ " ${FZX_TOGGLES-hidden} " == *" $1 "* ]]; }

# files::sort: paths in the order of the sort: path (component by component: "a/b" before "a-b", "fzf/"
# before "fzf-rsc/") or recent (newest modification first)
files::sort() {
  if [[ "${FZX_SORT:-path}" == recent ]]; then
    # %Y of the link itself when it is broken (stat -L fails); -- keeps "-" names as paths
    xargs -r -d '\n' stat -L -c $'%Y\t%n' -- 2> /dev/null | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 | cut -f2-
  else
    awk '{ k = $0; sub(/\/$/, "", k); gsub(/\//, "\001", k); print k "\t" $0 }' | LC_ALL=C sort -t $'\t' -k1,1 | cut -f2-
  fi
}

# files::fd_args <var>: fd's options for the toggles and FZX_FILES_EXCLUDES
files::fd_args() {
  local -n _args="$1"
  local _ex
  _args=(--color=never --absolute-path)
  files::on hidden && _args+=(--hidden)
  files::on ignored && _args+=(--no-ignore)
  for _ex in "${FZX_FILES_EXCLUDES[@]}"; do _args+=(--exclude "$_ex"); done
}

# files::list <f|d>: absolute paths under FILES_BASE, directories with a trailing "/", in sort order. With
# follow off, symbolic links are listed by what they point to (a link to a directory in dirs, to a file in
# files; broken ones dropped) but never descended into.
files::list() {
  local type="$1" args link rc
  files::fd_args args
  if files::on follow; then
    files::fd --type "$type" --follow "${args[@]}" . "$FILES_BASE" | files::sort
    return "${PIPESTATUS[0]}"
  fi
  {
    files::fd --type "$type" "${args[@]}" . "$FILES_BASE"
    rc=$?
    files::fd --type l "${args[@]}" . "$FILES_BASE" | while IFS= read -r link; do
      if [[ -d "$link" ]]; then
        [[ "$type" == d ]] && printf '%s/\n' "$link"
      elif [[ -e "$link" && "$type" == f ]]; then
        printf '%s\n' "$link"
      fi
    done
    return "$rc"
  } | files::sort
  return "${PIPESTATUS[0]}"
}

# files::grep <pattern>: "path:line:text" for every match under FILES_BASE. ripgrep (smart case); without it
# grep -E (case-insensitive unless the pattern has a capital, binary files skipped). The toggles apply to
# both, except that grep has no ignore files: it searches what .gitignore excludes too. Both exit 1 when
# nothing matches.
files::grep() {
  local args ex
  if command -v rg > /dev/null; then
    args=(--line-number --no-heading --color=never --smart-case)
    files::on hidden && args+=(--hidden)
    files::on ignored && args+=(--no-ignore)
    files::on follow && args+=(--follow)
    for ex in "${FZX_FILES_EXCLUDES[@]}"; do args+=(--glob "!$ex"); done
    command rg "${args[@]}" -- "$1" "$FILES_BASE"
  else
    args=(--line-number --color=never --binary-files=without-match -E)
    if files::on follow; then args+=(-R); else args+=(-r); fi
    [[ "$1" == *[[:upper:]]* ]] || args+=(-i)
    # '.?*', not '.*': grep matches --exclude-dir against the "." it is given too
    files::on hidden || args+=(--exclude='.*' --exclude-dir='.?*')
    for ex in "${FZX_FILES_EXCLUDES[@]}"; do args+=(--exclude-dir="$ex"); done
    # from inside the base: --exclude-dir would skip a base like ~/.config given by its path
    (cd -- "$FILES_BASE" && command grep "${args[@]}" -- "$1" .) | awk -v base="$FILES_BASE/" '{ sub(/^\.\//, ""); print base $0 }'
    return "${PIPESTATUS[0]}"
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
        files::list "$type" | fzx::pretty "$FILES_BASE"
        return "${PIPESTATUS[0]}"
      fi
      files::list "$type" |
        awk -v base="$FILES_BASE/" -v dim="$dim" -v rst="$rst" '
          { path = $0; sub(/\/$/, "", path); rel = substr(path, 1, length(base)) == base ? substr(path, length(base) + 1) : path
            n = split(rel, parts, "/"); dir = substr(rel, 1, length(rel) - length(parts[n]))
            printf "%s\t%s%s%s%s\n", path, dim, dir, rst, parts[n] }'
      return "${PIPESTATUS[0]}"
      ;;
    grep)
      local query="${FZF_QUERY:-}" rc
      [[ -n "$query" ]] || return 0
      files::grep "$query" |
        awk -v base="$FILES_BASE/" -v dim="$dim" -v rst="$rst" '
          { i = index($0, ":"); path = substr($0, 1, i - 1); rest = substr($0, i + 1)
            j = index(rest, ":"); line = substr(rest, 1, j - 1); text = substr(rest, j + 1)
            rel = substr(path, 1, length(base)) == base ? substr(path, length(base) + 1) : path
            printf "%s\t%s\t%s%s:%s:%s %s\n", path, line, dim, rel, line, rst, text }'
      rc="${PIPESTATUS[0]}"
      # rg and grep exit 1 when nothing matches
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
