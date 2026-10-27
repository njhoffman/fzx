#!/usr/bin/env bash
# dirs: every directory under ~ (all) and bookmarks. `fzx -m dirs[:all|:bookmarks] [WORDS...]`: words are
# the fzf query (all) or filter the bookmarks, where a single match is printed without opening fzf.
# Enter prints the directory. Frecent and recently visited directories: the recent module.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

dirs::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --scheme=path
    # after --scheme, which brings its own tiebreak: equal matches keep the list's order
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,50%,nohidden"
  )
  # query words given: bookmarks jump straight to a single match and quit quietly on none; all lists every
  # directory, so there the words are the fzf query instead (g's fallback picker)
  if ((${#FZX_ARGS[@]})); then
    if [[ "$FZX_MODE" == all ]]; then FZX_OPTS+=("--query=${FZX_ARGS[*]}"); else FZX_OPTS+=(--select-1 --exit-0); fi
  fi
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[dirs.files]}" "transform:$(fzx::cb nav goto files '{1}')" "browse the directory's files"
  fi
}

fzx::module_main "$@"
