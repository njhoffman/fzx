#!/usr/bin/env bash
# tmux: object navigation, buffers and reference browsers (extraction from panes: the capture module,
# which ctrl-o opens on the pane under the cursor).
FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # consumed by lib/actions.sh
tmux::opts() {
  # fzf's popup/split can change TMUX_PANE; preserve the invoking pane for callbacks.
  export FZX_TMUX_PANE="${FZX_TMUX_PANE:-${TMUX_PANE:-}}"
  tmux::args "${FZX_ARGS[@]}" || return
  local args=""
  ((${#FZX_ARGS[@]})) && printf -v args '%q ' "${FZX_ARGS[@]}"
  args+="--"
  FZX_OPTS+=(
    --delimiter=$'\t' --with-nth=2 --accept-nth=1 --no-sort --multi
    --preview "$(fzx::cb preview "$args" '{1}' '{2}' '{3}')"
    '--preview-window=right,60%,wrap,nohidden'
  )
  FZX_ACTION_ARGS="$args {+1}"
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[tmux.capture]}" "transform:$(fzx::cb transform capture "$args" '{1}')" 'open capture from this session, window or pane'
  fi
}

fzx::module_main "$@"
