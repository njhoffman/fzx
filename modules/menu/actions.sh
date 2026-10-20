#!/usr/bin/env bash
# menu transforms: refresh stale entry summaries in the background.

[[ -n "${_FZX_CORE_LOADED:-}" ]] || source "${FZX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/core.sh"
fzx::require log session menu opts

# menu::transform refresh: bound as start:+bg-transform; prints one reload when any summary changed
menu::transform() {
  case "${1:-}" in
    refresh)
      if fzx::menu_refresh; then
        printf 'reload:%s' "$(fzx::cb source)"
      fi
      ;;
    *)
      printf 'menu: unknown transform: %s\n' "${1:-}" >&2
      return 2
      ;;
  esac
}
