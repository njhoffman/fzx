#!/usr/bin/env bash
# files: find files and directories, or grep their contents. `fzx -m files[:dirs|:grep] [DIR]`.
# Enter prints absolute paths (path:line for grep).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

files::opts() {
  files::base "${FZX_ARGS[0]:-}" || return
  FZX_OPTS+=(
    --delimiter=$'\t'
    "--preview-window=right,55%,nohidden"
    "--header=${FILES_BASE/#$HOME/\~}"
  )
  local edit="${EDITOR:-vi}"
  if [[ "$FZX_MODE" == grep ]]; then
    FZX_OPTS+=(
      --with-nth=3
      --accept-nth='{1}:{2}'
      --disabled
      --bind "change:reload:sleep 0.1; $(fzx::cb source)"
      --preview "$(fzx::cb preview '{1}' '{2}')"
    )
    fzx::bind "${FZX_KEYS[files.edit]}" "execute($edit +{2} {1})" "open the file at the matching line in \$EDITOR"
  else
    FZX_OPTS+=(
      --with-nth=2
      --accept-nth=1
      --scheme=path
      --preview "$(fzx::cb preview '{1}')"
    )
    fzx::bind "${FZX_KEYS[files.edit]}" "execute($edit {+1})" "open the selected files in \$EDITOR"
  fi
  if fzx::in_session; then
    local parent="${FILES_BASE%/*}"
    fzx::bind "${FZX_KEYS[files.into]}" "transform:$(fzx::cb nav goto "files:$FZX_MODE" '{1}')" \
      "browse the directory under the cursor"
    fzx::bind "${FZX_KEYS[files.up]}" "transform:$(fzx::cb nav goto "files:$FZX_MODE" "$(printf '%q' "${parent:-/}")")" \
      "browse the parent directory"
  fi
}

fzx::module_main "$@"
