#!/usr/bin/env bash
# applications: desktop entries (yours and the system's) by name with their icon, command and categories.
# `fzx -m applications`. Enter launches the selection detached and closes, so `fzx -m applications --popup`
# bound in the window manager works as a launcher; ctrl-o launches and stays, alt-e edits the file.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
applications::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    "--tiebreak=begin,index"
    --preview "$(fzx::cb preview '{1}' '{2}')"
    "--preview-window=right,45%,nohidden"
  )
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
}

fzx::module_main "$@"
