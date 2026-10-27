#!/usr/bin/env bash
# colors: the 256-color palette, X11 color names and fzx's own FZX_COLORS, with swatches and samples.
# `fzx -m colors[:names|:fzx]`. Enter prints numbers, names or keys; alt-h/alt-s/alt-e copy codes.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
colors::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{3}' '{4}')"
    "--preview-window=right,50%,nohidden"
  )
  FZX_ACTION_ARGS_FOR['hex']='{+3}'
  FZX_ACTION_ARGS_FOR['sgr']='{+4}'
  FZX_ACTION_ARGS_FOR['escape']='{+4}'
}

fzx::module_main "$@"
