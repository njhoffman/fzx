#!/usr/bin/env bash
# i3: windows, workspaces and the scratchpad (i3-msg). `fzx -m i3[:workspaces|:scratchpad]`. Enter focuses a
# window, switches to a workspace or shows a scratchpad window, then closes; alt-m moves windows to a
# workspace, alt-s sends them to the scratchpad, alt-t toggles floating, alt-x closes them; workspaces: alt-O
# moves one to another output, alt-R renames it.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

i3::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
  )
  fzx::in_session || return 0
  # enter: the mode's own action (standalone, enter prints)
  local name act flags
  case "$FZX_MODE" in
    workspaces) name=switch ;;
    scratchpad) name=show ;;
    *) name=focus ;;
  esac
  fzx::require actions
  fzx::comp_field action "$name" flags flags 2> /dev/null || flags=become
  fzx::_action_bind_string "$name" "$flags" act
  fzx::bind enter "$act" "$(case "$name" in switch) echo "switch to the workspace" ;; show) echo "show the window" ;; *) echo "focus the window" ;; esac), then close"
}

fzx::module_main "$@"
