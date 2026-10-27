#!/usr/bin/env bash
# recent actions

# recent::action edit <path...>: open in $EDITOR (foreground)
# recent::action remove <path...>: forget the paths in the current mode's database
recent::action() {
  local action="${1:-}" path zl
  shift
  case "$action:${FZX_MODE:-nvim}" in
    edit:*)
      (($#)) || return 0
      "${EDITOR:-vi}" -- "$@"
      ;;
    remove:nvim) printf 'recent: telescope-frecency keeps its own database; remove entries from nvim\n' >&2 ;;
    remove:fasd | remove:fasd-dirs | remove:visited) command fasd -D "$@" ;;
    remove:dirs) for path in "$@"; do command zoxide remove -- "$path"; done ;;
    remove:zlua)
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
      recent::zlua zl || return 2
      for path in "$@"; do command "$FZX_RECENT_ZLUA_LUA" "$zl" -x "$path"; done
      ;;
    *)
      printf 'recent: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && recent::action "$@"
