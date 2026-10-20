#!/usr/bin/env bash
# systemd: services of the user and system managers. `fzx -m systemd[:system|:failed]`.
# Enter prints unit names.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS*: read by lib/actions.sh
systemd::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,50%,nowrap,nohidden"
  )
  # copy the unit names, not the manager:unit ids
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
  # the header lists the action keys from the table, so it cannot drift from the bindings
  local _k name key hints=""
  while IFS=$'\t' read -r _k name key _ _; do
    [[ "$key" == - ]] || hints+="${hints:+  }$key $name"
  done < <(fzx::comp_rows action)
  FZX_OPTS+=("--header=$hints")
}

fzx::module_main "$@"
