#!/usr/bin/env bash
# dirs: frecent and recent directories (zoxide, fasd) and bookmarks. `fzx -m dirs[:mode] [WORDS...]`:
# words filter through zoxide/fasd; with words, a single match is printed without opening fzf.
# Enter prints the directory (the zsh widget and fzx-cd cd into it).

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
    --no-sort
    --scheme=path
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,50%,nohidden"
  )
  # query words given: jump straight to a single match, quit quietly on none (the old g/gg idea)
  ((${#FZX_ARGS[@]})) && FZX_OPTS+=(--select-1 --exit-0)
  fzx::bind "${FZX_KEYS[dirs.remove]}" "execute-silent($(fzx::cb action remove '{+1}'))+reload($(fzx::cb source))" \
    "forget the selected directories"
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[dirs.files]}" "transform:$(fzx::cb nav goto files '{1}')" "browse the directory's files"
  fi
}

fzx::module_main "$@"
