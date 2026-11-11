#!/usr/bin/env bash
# menu transforms: refresh stale entry summaries in the background.

[[ -n "${_FZX_CORE_LOADED:-}" ]] || source "${FZX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/core.sh"
fzx::require log session menu opts

# menu::transform refresh: bound as start:+bg-transform; prints one reload when any summary changed. The
# summaries run as refresh-run under setsid: a session and process group of their own, with no controlling
# terminal (none of them can change its modes under fzf) and stdin from /dev/null; the group is recorded in
# state/bg_pgid, so leaving the menu stops it (fzx::bg_stop) instead of leaving it to slow the next screen.
menu::transform() {
  case "${1:-}" in
    refresh)
      setsid -w "$FZX_BIN" _cb transform refresh-run < /dev/null
      ;;
    refresh-run)
      fzx::state_set bg_pgid "$$"
      local rc=0
      fzx::menu_refresh || rc=$?
      # done: forget the group, unless a later refresh recorded its own
      local g=""
      fzx::state_get bg_pgid g 2> /dev/null && [[ "$g" == "$$" ]] && rm -f -- "$FZX_SESSION_DIR/state/bg_pgid"
      ((rc == 0)) && printf 'reload:%s' "$(fzx::cb source)"
      return 0
      ;;
    *)
      printf 'menu: unknown transform: %s\n' "${1:-}" >&2
      return 2
      ;;
  esac
}
