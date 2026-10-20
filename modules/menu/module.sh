#!/usr/bin/env bash
# menu: what `fzx` opens without arguments. Lists the entries of every module's manifest.sh that apply
# here; enter opens one as a child session, so alt-left comes back to the menu.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

menu::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --no-multi
    --preview "$(fzx::cb preview {1})"
    --preview-window=right,40%,wrap
  )
  if fzx::in_session; then
    FZX_OPTS+=(
      --bind "enter:transform:$(fzx::cb nav entry {1})"
      --bind "start:+bg-transform:$(fzx::cb transform refresh)"
    )
  fi
}

fzx::module_main "$@"
