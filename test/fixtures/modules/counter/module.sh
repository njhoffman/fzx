#!/usr/bin/env bash
# counter: test fixture module

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../../../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# COUNTER_MODES overrides the mode list (space-separated); empty string means no modes hook result
# shellcheck disable=SC2034  # FZX_MODES is read by lib/run.sh
counter::modes() {
  read -r -a FZX_MODES <<< "${COUNTER_MODES-one two three}"
}

# switching to or from "three" restarts fzf
counter::mode_restart() {
  [[ "$1" == three || "$2" == three ]]
}

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
