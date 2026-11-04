#!/usr/bin/env bash
# kdeconnect: KDE Connect devices, their notifications and SMS conversations, and the commands they offer. `fzx -m
# kdeconnect[:notifications|:commands|:sms]`. Enter prints the ids.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

kdeconnect::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{3}' '{4}')"
    "--preview-window=down,45%,nohidden"
  )
  # ctrl-y: what the row is called, not the id the commands take
  # shellcheck disable=SC2034  # read by lib/actions.sh
  FZX_ACTION_ARGS_FOR['copy']='{+3}'
}

fzx::module_main "$@"
