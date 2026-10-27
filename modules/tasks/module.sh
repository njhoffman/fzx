#!/usr/bin/env bash
# tasks: project scripts (make targets, just recipes, package.json scripts, Taskfile tasks, cargo aliases,
# pdm/poe/hatch scripts) named project:task, run in their repository. `fzx -m tasks[:repos|:all|:projects]`.
# Enter runs the task (projects: chooses the repository); picks and chosen projects are kept in
# $FZX_STATE_DIR/tasks.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
tasks::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,45%,wrap,nohidden"
  )
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
}

fzx::module_main "$@"
