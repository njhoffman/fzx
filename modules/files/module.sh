#!/usr/bin/env bash
# files: find files and directories, or grep their contents. `fzx -m files[:dirs|:grep] [DIR]`.
# Enter prints absolute paths (path:line for grep).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

files::modes() {
  FZX_MODES=(files dirs grep)
}

files::opts() {
  files::base "${FZX_ARGS[0]:-}" || return
  FZX_OPTS+=(
    --delimiter=$'\t'
    --preview-window=right,55%,nohidden
    "--header=${FILES_BASE/#$HOME/\~}"
  )
  local edit="${EDITOR:-vi}"
  if [[ "$FZX_MODE" == grep ]]; then
    FZX_OPTS+=(
      --with-nth=3
      --accept-nth='{1}:{2}'
      --disabled
      --bind "change:reload:sleep 0.1; $(fzx::cb source)"
      --preview "$(fzx::cb preview {1} {2})"
      --bind "${FZX_KEYS[files.edit]}:execute($edit +{2} {1})"
    )
  else
    FZX_OPTS+=(
      --with-nth=2
      --accept-nth=1
      --scheme=path
      --preview "$(fzx::cb preview {1})"
      --bind "${FZX_KEYS[files.edit]}:execute($edit {+1})"
    )
  fi
  if fzx::in_session; then
    local parent="${FILES_BASE%/*}"
    FZX_OPTS+=(
      --bind "${FZX_KEYS[files.into]}:transform:$(fzx::cb nav goto "files:$FZX_MODE" {1})"
      --bind "${FZX_KEYS[files.up]}:transform:$(fzx::cb nav goto "files:$FZX_MODE" "$(printf '%q' "${parent:-/}")")"
    )
  fi
}

# grep searches as you type (--disabled plus change:reload), which cannot be toggled while fzf runs
files::mode_restart() {
  [[ "$1" == grep || "$2" == grep ]]
}

fzx::module_main "$@"
