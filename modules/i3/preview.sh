#!/usr/bin/env bash
# i3 preview: a window's properties from the tree (class, instance, title, workspace, size, floating, marks);
# a workspace's windows

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# i3::preview <id>
i3::preview() {
  local id="${1:-}"
  [[ -n "$id" ]] || return 0
  if [[ "${FZX_MODE:-windows}" == workspaces ]]; then
    printf 'workspace %s\n\n' "$id"
    # shellcheck disable=SC2119  # no fields: the whole text
    i3::tree_windows | awk -F'\037' -v w="$id" '$2 == w { printf "  %-16s %s\n", $4, $5 }' | fzx::glyphs_plain
    return 0
  fi
  [[ "$id" =~ ^[0-9]+$ ]] || return 0
  # shellcheck disable=SC2119  # no fields: the whole text
  command i3-msg -t get_tree 2> /dev/null | command jq -r --argjson id "$id" '
    .. | objects | select(.id == $id) |
    "title      \(.name // "")",
    "class      \(.window_properties.class // "")",
    "instance   \(.window_properties.instance // "")",
    "role       \(.window_properties.window_role // "-")",
    "window     \(.window)",
    "size       \(.rect.width)x\(.rect.height)+\(.rect.x)+\(.rect.y)",
    "floating   \(.floating // "")",
    "fullscreen \(if .fullscreen_mode == 1 then "yes" else "no" end)",
    "marks      \((.marks // []) | join(" "))",
    "urgent     \(.urgent)"' | fzx::glyphs_plain
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" i3
  i3::preview "$@"
}
