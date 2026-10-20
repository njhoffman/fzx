#!/usr/bin/env bash
# menu source: one line per applicable manifest entry, "id<TAB>display", with cached summaries.

[[ -n "${_FZX_CORE_LOADED:-}" ]] || source "${FZX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/core.sh"
fzx::require log session menu

menu::source() {
  fzx::menu_lines
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && menu::source "$@"
