#!/usr/bin/env bash
# capture: URLs, paths, words, hashes, IPs or lines out of a tmux pane, the visible screen first, then the
# scrollback, each row marked with where it was. `fzx -m capture[:mode] [--pane %N]`. alt-. / alt-, read
# the window's next or previous pane; enter prints the values, alt-p pastes them into the origin pane.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"
# shellcheck source=./actions.sh
source "$FZX_MODULE_DIR/actions.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS*: read by lib/actions.sh
capture::opts() {
  # fzf's popup or split changes TMUX_PANE: keep the pane fzx was opened from for the callbacks
  export FZX_TMUX_PANE="${FZX_TMUX_PANE:-${TMUX_PANE:-}}"
  capture::args "${FZX_ARGS[@]}" || return
  local cb_args="" header
  ((${#FZX_ARGS[@]})) && printf -v cb_args '%q ' "${FZX_ARGS[@]}"
  cb_args+="--"
  # the origin pane as it is before fzf draws (inline, fzf takes over that very pane)
  fzx::in_session && capture::snapshot
  capture::header header
  FZX_OPTS+=(
    --delimiter=$'\t' --with-nth=2 --accept-nth=1 --no-sort --multi
    --preview "$(fzx::cb preview "$cb_args" '{1}' '{3}')"
    '--preview-window=right,50%,wrap,nohidden'
    "--header=$header"
  )
  FZX_ACTION_ARGS="$cb_args {+1}"
  FZX_ACTION_ARGS_FOR['copy']='{+1}'
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[capture.next]}" "transform:$(fzx::cb transform pane next "$cb_args")" "capture the window's next pane"
    fzx::bind "${FZX_KEYS[capture.prev]}" "transform:$(fzx::cb transform pane prev "$cb_args")" "capture the window's previous pane"
  fi
}

fzx::module_main "$@"
