#!/usr/bin/env bash
# ps: process viewer. Run through `fzx -m ps[:mode] [--ppid PID]` or directly as `modules/ps/module.sh`
# (mode from $FZX_MODE).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

ps::modes() {
  FZX_MODES=(user all tree)
}

ps::opts() {
  FZX_OPTS+=(
    --header-lines=1
    --accept-nth=1
    --preview "$(fzx::cb preview {1})"
    --preview-window=down,40%,wrap,nohidden
    --bind "${FZX_KEYS[ps.term]}:execute-silent($(fzx::cb action term {+1}))+reload($(fzx::cb source))"
  )
  # the forest only reads correctly in input order
  [[ "$FZX_MODE" == tree ]] && FZX_OPTS+=(--no-sort)
  if fzx::in_session; then
    FZX_OPTS+=(--bind "${FZX_KEYS[ps.children]}:transform:$(fzx::cb nav goto ps --ppid {1})")
  fi
}

# tree needs --no-sort, which fzf cannot toggle reliably while running: restart when entering or leaving it
ps::mode_restart() {
  [[ "$1" == tree || "$2" == tree ]]
}

fzx::module_main "$@"
