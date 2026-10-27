#!/usr/bin/env bash
# recent: frecent files and directories, best first. `fzx -m recent[:MODE] [WORDS...]`; modes nvim, fasd
# (files), zlua, dirs, fasd-dirs, visited (directories). Words filter the list (files: each one, in order,
# anywhere in the path, ignoring case; directories: the tracker's own matching); with words, a single match
# is printed without the picker. Enter prints the paths (v opens files in $EDITOR, g/gg/alt-j cd).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

recent::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --no-sort
    --scheme=path
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,55%,nohidden"
  )
  ((${#FZX_ARGS[@]})) && FZX_OPTS+=(--select-1 --exit-0)
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[recent.dir]}" "transform:$(fzx::cb nav goto files '{1}')" "browse the file's directory"
  fi
}

fzx::module_main "$@"
