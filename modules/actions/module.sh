#!/usr/bin/env bash
# actions: the actions menu (FZX_KEYS[actions]), opened as a child session of the screen it acts on.
# Lists that screen's action rows; enter runs one on the selection it was opened with, then goes back.
# Its arguments are groups of "names args... --fzx--" (lib/actions.sh builds them).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

actions::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,40%,wrap,nohidden"
  )
  fzx::in_session && fzx::bind enter "transform:$(fzx::cb transform run '{1}')" "run the action, then go back"
}

fzx::module_main "$@"
