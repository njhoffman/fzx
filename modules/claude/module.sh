#!/usr/bin/env bash
# claude: Claude Code projects (claude-projects from ~/.shell): yours with a CLAUDE.md and every directory
# Claude has run in, with their git state, version, open TODO items and sessions. `fzx -m claude[:own
# |:active]`. Enter prints the path (the zsh widget cds into it); ctrl-o starts Claude Code there.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

claude::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --multi
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,50%,nohidden"
  )
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[claude.git]}" "transform:$(fzx::cb nav goto git '{1}')" "the git module on the project"
    fzx::bind "${FZX_KEYS[claude.todos]}" "transform:$(fzx::cb nav goto todos --dir '{1}')" "the project's TODO.md items"
    fzx::bind "${FZX_KEYS[claude.files]}" "transform:$(fzx::cb nav goto files '{1}')" "browse the project's files"
    # the scan runs after the list shows, and reloads it when anything changed
    FZX_OPTS+=(--bind "start:+bg-transform:$(fzx::cb transform refresh)")
  fi
}

fzx::module_main "$@"
