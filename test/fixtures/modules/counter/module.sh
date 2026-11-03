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
  # the module's own enter (as tasks --paste binds it), over the default action's
  [[ -n "${COUNTER_BIND_ENTER:-}" ]] && fzx::bind enter accept "the module's own enter"
  [[ -n "${COUNTER_OPTS_FAIL:-}" ]] && return 1
  return 0
}

# the refresh hook, only with COUNTER_REFRESH (on, off or keep): the header follows the mode, and fzf's
# search turns on or off
# shellcheck disable=SC2034  # FZX_REFRESH_*: read by lib/nav.sh
counter::refresh() {
  [[ -n "${COUNTER_REFRESH:-}" ]] || return 0
  [[ "$COUNTER_REFRESH" == fail ]] && return 1
  FZX_REFRESH_HEADER="mode:$FZX_MODE${COUNTER_ARGS_IN_HEADER:+ ${FZX_ARGS[*]}}"
  [[ "$COUNTER_REFRESH" == keep ]] || FZX_REFRESH_SEARCH="$COUNTER_REFRESH"
}

fzx::module_main "$@"
