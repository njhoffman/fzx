#!/usr/bin/env bash
# packages: installed packages of apt, snap, flatpak, pipx, cargo, pnpm and gem, and apt's available and
# upgradable ones, the snap and flatpak catalogs, and a search of crates.io, npm, rubygems.org and PyPI.
# `fzx -m packages[:MODE]`: apt, available, upgradable, snap, snap-available, flatpak, flatpak-available,
# pipx, cargo, pnpm, gem, search.
# Enter prints package names.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS*: read by lib/actions.sh
packages::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,50%,wrap,nohidden"
  )
  # copy the package names, not the manager:name ids
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
  # the header lists the action keys from the table, so it cannot drift from the bindings
  local _k name key hints=""
  while IFS=$'\t' read -r _k name key _ _; do
    [[ "$key" == - ]] || hints+="${hints:+  }$key $name"
  done < <(fzx::comp_rows action)
  if [[ "${FZX_MODE:-}" == search ]]; then
    # the registries answer the query: fzf does not filter, it reloads (debounced) as you type
    FZX_OPTS+=(--disabled --bind "change:reload:sleep 0.3; $(fzx::cb source)")
    hints="type to search; $hints"
  fi
  FZX_OPTS+=("--header=$hints")
}

fzx::module_main "$@"
