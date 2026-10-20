#!/usr/bin/env bash
# counter: test fixture module

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../../../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

counter::opts() {
  FZX_OPTS+=(
    --preview "$(fzx::cb preview '{1}')"
    --bind "ctrl-x:execute-silent($(fzx::cb action mark '{+1}'))"
    "--header=mode:$FZX_MODE"
  )
  [[ -n "${COUNTER_OPTS_FAIL:-}" ]] && return 1
  return 0
}

fzx::module_main "$@"
