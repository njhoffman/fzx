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
    "--preview-window=down,50%,nohidden"
  )
  # copy the package names, not the manager:name ids
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
  local header
  packages::header header
  if [[ "${FZX_MODE:-}" == search ]]; then
    # the registries answer the query: fzf does not filter, it reloads (debounced) as you type
    FZX_OPTS+=(--disabled)
  fi
  if fzx::in_session; then
    # every mode binds the search's reload, unbound outside search, so switching to or from it needs no
    # restart (packages::refresh rebinds or unbinds it)
    FZX_OPTS+=(--bind "change:reload:sleep 0.3; $(fzx::cb search)")
    [[ "${FZX_MODE:-}" == search ]] || FZX_OPTS+=(--bind "start:+unbind(change)")
  elif [[ "${FZX_MODE:-}" == search ]]; then
    FZX_OPTS+=(--bind "change:reload:sleep 0.3; $(fzx::cb search)")
  fi
  FZX_OPTS+=("--header=$header")
}

# packages::header <var>: the action keys from the table (so it cannot drift from the bindings), after "type
# to search;" in search mode
packages::header() {
  local _k _name _key _hints=""
  while IFS=$'\t' read -r _k _name _key _ _; do
    [[ "$_key" == - ]] || _hints+="${_hints:+  }$_key $_name"
  done < <(fzx::comp_rows action)
  [[ "${FZX_MODE:-}" == search ]] && _hints="type to search; $_hints"
  printf -v "$1" '%s' "$_hints"
}

# packages::refresh: an in-place switch (lib/nav.sh): into search fzf stops filtering and reloads as you
# type; out of it, the other way round; the header follows
# shellcheck disable=SC2034  # FZX_REFRESH_*: read by lib/nav.sh
packages::refresh() {
  packages::header FZX_REFRESH_HEADER
  if [[ "${FZX_MODE:-}" == search ]]; then
    FZX_REFRESH_SEARCH=off FZX_REFRESH_CHANGE=on
  else
    FZX_REFRESH_SEARCH=on FZX_REFRESH_CHANGE=off
  fi
}

fzx::module_main "$@"
