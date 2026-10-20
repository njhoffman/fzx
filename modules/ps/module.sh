#!/usr/bin/env bash
# ps: process viewer. Run through `fzx -m ps[:mode] [--ppid PID]` or directly as `modules/ps/module.sh`
# (mode from $FZX_MODE).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

ps::opts() {
  FZX_OPTS+=(
    --header-lines=1
    --accept-nth=1
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,40%,wrap,nohidden"
  )
  # the forest only reads correctly in input order
  [[ "$FZX_MODE" == tree ]] && FZX_OPTS+=(--no-sort)
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[ps.children]}" "transform:$(fzx::cb nav goto ps --ppid '{1}')" \
      "open the children of the process under the cursor"
  fi
}

fzx::module_main "$@"
