#!/usr/bin/env bash
# files: find files and directories, or grep their contents. `fzx -m files[:dirs|:grep] [DIR]`.
# Enter prints absolute paths (path:line for grep). In grep mode ctrl-t switches between grepping as you type
# and fzf filtering the matches (the grep term frozen), and back (files::transform).

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
    # trash takes the files of every selected match
    FZX_ACTION_ARGS_FOR['trash']='{+1}'
  else
    FZX_OPTS+=(
      --with-nth=2
      --accept-nth=1
      --scheme=path
      --preview "$(fzx::cb preview '{1}')"
    )
  fi
  if [[ "$FZX_MODE" == grep ]] && fzx::in_session; then
    # grep starts grepping: a filter left on by an earlier visit to the mode is dropped
    fzx::state_set files_grep_filter ""
    fzx::bind "${FZX_KEYS[files.filter]}" "transform:$(fzx::cb transform filter)" \
      "grep: filter the matches with fzf (the grep term frozen), and back to grepping"
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
