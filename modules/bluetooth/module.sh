#!/usr/bin/env bash
# bluetooth: paired devices (connected first) and every device bluez knows. `fzx -m bluetooth[:all]`.
# alt-c connects, alt-d disconnects, alt-p pairs, alt-t trusts, alt-x removes, alt-s keeps a scan running
# (all), alt-P powers the controller. Enter prints the addresses.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

bluetooth::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=1
    --header-lines=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,40%,nohidden"
  )
}

fzx::module_main "$@"
