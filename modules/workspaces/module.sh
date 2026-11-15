#!/usr/bin/env bash
# workspaces: tmux workspaces (~/.config/tmux/scripts/workspace): predefined sessions, the family's open
# sessions and recent directories, the picker tmux's alt-w opens. `fzx -m workspaces[:open|:recent|
# :predefined]`. Enter prints the KEY (what `workspace pick` reads and opens); alt-enter opens it from
# here; alt-R resets an open session, alt-x kills one, alt-d forgets a recent directory.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

workspaces::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=5
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{2}' '{3}' '{4}')"
    "--preview-window=right,50%,nohidden"
  )
  # shellcheck disable=SC2034  # read by lib/actions.sh (the actions menu's enter row)
  FZX_ENTER_DESC="print the workspace's key (workspace pick opens it)"
}

fzx::module_main "$@"
