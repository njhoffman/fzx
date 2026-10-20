#!/usr/bin/env bash
# logs: log files, systemd unit journals and docker containers. `fzx -m logs[:units|:docker]`.
# Enter prints the file path, unit name or container id.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

logs::modes() {
  FZX_MODES=(files units docker)
}

logs::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    --no-sort
    --preview "$(fzx::cb preview {1} {2})"
    --preview-window=down,60%,follow,nowrap,nohidden
    --bind "${FZX_KEYS[logs.follow]}:execute($(fzx::cb action follow {1} {2}))"
  )
}

fzx::module_main "$@"
