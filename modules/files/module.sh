#!/usr/bin/env bash
# files: find files and directories, or grep their contents. `fzx -m files[:dirs|:grep] [DIR]`.
# Enter prints absolute paths (path:line for grep).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS*: read by lib/actions.sh
files::opts() {
  files::base "${FZX_ARGS[0]:-}" || return
  FZX_OPTS+=(
    --delimiter=$'\t'
    "--preview-window=right,55%,nohidden"
    "--header=${FILES_BASE/#$HOME/\~}"
  )
  if [[ "$FZX_MODE" == grep ]]; then
    FZX_OPTS+=(
      --with-nth=3
      --accept-nth='{1}:{2}'
      --disabled
      --bind "change:reload:sleep 0.1; $(fzx::cb source)"
      --preview "$(fzx::cb preview '{1}' '{2}')"
    )
    FZX_ACTION_ARGS='{1} {2}'
  else
    FZX_OPTS+=(
      --with-nth=2
      --accept-nth=1
      --scheme=path
      --preview "$(fzx::cb preview '{1}')"
    )
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
