#!/usr/bin/env bash
# fonts actions: copy the families' font files, open the folder of each sample file

# shellcheck source=./preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/preview.sh"

# fonts::action <action> <family...> (folder: the sample files)
fonts::action() {
  local action="${1:-}" a out=() rc=0
  shift
  case "$action" in
    copy-files)
      fzx::require builtin
      for a; do
        [[ -n "$a" ]] || continue
        mapfile -t -O "${#out[@]}" out < <(command fc-list --format '%{file}\n' "$(fonts::_pattern "$a")" 2> /dev/null | sort)
      done
      ((${#out[@]})) || return 0
      printf '%s\n' "${out[@]}" | fzx::clip
      ;;
    folder)
      for a; do
        [[ -f "$a" ]] && { command setsid -f xdg-open "${a%/*}" > /dev/null 2>&1 < /dev/null || rc=1; }
      done
      return "$rc"
      ;;
    *)
      printf 'fonts: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" fonts
  fonts::action "$@"
}
