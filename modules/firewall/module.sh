#!/usr/bin/env bash
# firewall: ufw's rules and application profiles. `fzx -m firewall[:apps]`. Rules need root: through
# `sudo -n`, so run `sudo -v` first (or let an action ask, then the list shows them). alt-x deletes rules,
# alt-a and alt-D allow and deny profiles, alt-e and alt-d turn ufw on and off. Enter prints the rules or
# profile names.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
firewall::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    --header-lines=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,40%,wrap,nohidden"
  )
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
}

fzx::module_main "$@"
