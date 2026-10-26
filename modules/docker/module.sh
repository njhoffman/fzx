#!/usr/bin/env bash
# docker: containers, images, volumes, networks and compose projects. `fzx -m docker[:images|:volumes
# |:networks|:compose]`. Enter prints the ids (volume and project names).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

docker::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --no-sort
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,55%,wrap,nohidden"
  )
}

fzx::module_main "$@"
