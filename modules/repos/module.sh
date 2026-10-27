#!/usr/bin/env bash
# repos: git repositories (ghq's, plus FZX_REPOS_ROOTS) with their branch, changes, ahead/behind, open TODO
# items and last commit, from a scan that runs in the background. `fzx -m repos[:mine|:changed|:unsynced
# |:todos]`. Enter prints the path (the zsh widget cds into it).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

repos::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,45%,nohidden"
  )
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[repos.git]}" "transform:$(fzx::cb nav goto git '{1}')" "the git module on the repository"
    fzx::bind "${FZX_KEYS[repos.files]}" "transform:$(fzx::cb nav goto files '{1}')" "browse the repository's files"
    # the scan runs after the list shows, and reloads it when anything changed
    FZX_OPTS+=(--bind "start:+bg-transform:$(fzx::cb transform refresh)")
  fi
}

fzx::module_main "$@"
