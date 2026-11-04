#!/usr/bin/env bash
# dirs actions: bookmark directories (alt-m, asks each a name) and remove bookmarks (alt-x). What they change is
# $FZX_STATE_DIR/dirs/bookmarks; FZX_DIRS_BOOKMARKS is the user's config and stays as it is.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :

# dirs::_write_bookmarks: stdin as the bookmarks file, whole or not at all
dirs::_write_bookmarks() {
  local file tmp
  file="$(dirs::bookmarks_file)"
  mkdir -p -- "${file%/*}"
  tmp="$file.$BASHPID"
  command cat > "$tmp" && mv -f -- "$tmp" "$file"
}

# dirs::_forget_views: the bookmarks views already read this session: they would show the old list
dirs::_forget_views() {
  [[ -n "${FZX_SESSION_DIR:-}" ]] && rm -f -- "$FZX_SESSION_DIR"/data/bookmarks* 2> /dev/null
  return 0
}

# dirs::mark <path>: ask a name (the directory's by default); the same name again moves the bookmark
dirs::mark() {
  local path="$1" name file
  [[ -d "$path" ]] || { printf 'dirs: not a directory: %s\n' "$path" >&2; return 1; }
  name="${path##*/}"
  fzx::tty_read -r -e -i "$name" -p $'\e[1mbookmark '"${path/#$HOME/\~}"$' as\e[0m ' name < "${FZX_TTY:-/dev/tty}" || return 0
  name="${name//$'\t'/ }"
  [[ -n "${name// /}" ]] || return 0
  file="$(dirs::bookmarks_file)"
  {
    [[ -f "$file" ]] && awk -F'\t' -v n="$name" '$1 != n' "$file"
    printf '%s\t%s\n' "$name" "$path"
  } | dirs::_write_bookmarks
}

# dirs::unmark <path...>: remove the file's bookmarks of these directories; config's can only go from config
dirs::unmark() {
  local file path name rc=0
  file="$(dirs::bookmarks_file)"
  if [[ -f "$file" ]]; then
    printf '%s\n' "$@" | awk -F'\t' 'NR == FNR { gone[$0] = 1; next } !($2 in gone)' - "$file" | dirs::_write_bookmarks
  fi
  for path; do
    for name in "${!FZX_DIRS_BOOKMARKS[@]}"; do
      if [[ "${FZX_DIRS_BOOKMARKS[$name]/#\~/$HOME}" == "$path" ]]; then
        printf 'dirs: %s is in FZX_DIRS_BOOKMARKS: remove it from your config\n' "$name" >&2
        rc=1
      fi
    done
  done
  return "$rc"
}

# dirs::action <mark|unmark> <path...>
dirs::action() {
  local action="${1:-}" path rc=0
  shift
  case "$action" in
    mark)
      for path; do dirs::mark "$path" || rc=1; done
      ;;
    unmark) dirs::unmark "$@" || rc=1 ;;
    *)
      printf 'dirs: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  dirs::_forget_views
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" dirs
  dirs::action "$@"
}
