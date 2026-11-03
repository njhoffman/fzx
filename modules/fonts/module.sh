#!/usr/bin/env bash
# fonts: fontconfig's font families with a sample drawn in each (ImageMagick and chafa; sharpest with
# FZX_PREVIEW_IMAGE_FORMAT=kitty or sixels), its styles and files. `fzx -m fonts`. alt-m: monospace only;
# ctrl-y copies the names, alt-y the files, alt-O opens the folder. Enter prints the family names.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
fonts::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=1
    "--tiebreak=begin,index"
    --preview "$(fzx::cb preview '{1}' '{2}')"
    "--preview-window=right,55%,nohidden"
  )
  FZX_ACTION_ARGS_FOR['folder']='{+2}'
}

fzx::module_main "$@"
