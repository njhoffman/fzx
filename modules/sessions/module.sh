#!/usr/bin/env bash
# sessions: every other fzx session tree, to pick up from this terminal. `fzx -m sessions`. Enter resumes a
# kept tree (--keep) whose owner is gone and opens a copy of a live one (same module, mode, arguments,
# toggles, sort and query, as a screen of this list: back returns here). alt-x deletes kept trees.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

sessions::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=1
    --no-sort
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,45%,wrap,nohidden"
  )
  if fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb transform enter '{1}')" \
      "resume a kept session; open a copy of a live one"
  fi
}

fzx::module_main "$@"
