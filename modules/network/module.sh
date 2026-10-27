#!/usr/bin/env bash
# network: listening ports, connections, interfaces, routes, wifi networks and mDNS services; the open
# files of a process. `fzx -m network[:connections|:interfaces|:routes|:wifi|:services]`,
# `fzx -m network:files --pid PID`. Enter prints the addresses (interface names, SSIDs, file names).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
network::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    --header-lines=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,45%,wrap,nohidden"
  )
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
  if fzx::in_session && [[ "$FZX_MODE" != files ]]; then
    fzx::bind "${FZX_KEYS[network.files]}" "transform:$(fzx::cb nav goto network:files --pid '{1}')" \
      "ports, connections: the open files of the process"
  fi
}

fzx::module_main "$@"
