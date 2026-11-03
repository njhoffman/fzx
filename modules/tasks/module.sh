#!/usr/bin/env bash
# tasks: project scripts (make targets, just recipes, package.json scripts, Taskfile tasks, cargo aliases,
# pdm/poe/hatch scripts) named project:task, run in their repository.
# `fzx -m tasks[:repos|:all|:projects] [--paste PANE]`.
# Enter runs the task (projects: chooses the repository); picks and chosen projects are kept in
# $FZX_STATE_DIR/tasks. With --paste PANE (the tmux popup) enter pastes the command line into that pane
# instead, without submitting it ("cd DIR && CMD" for another repository's task), and alt-x runs it here.

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
    "--preview-window=down,45%,nohidden"
  )
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
  local i pane="" run
  for ((i = 0; i < ${#FZX_ARGS[@]}; i++)); do
    [[ "${FZX_ARGS[i]}" == --paste ]] && pane="${FZX_ARGS[i + 1]:-}"
  done
  if [[ -n "$pane" ]]; then
    # enter is the module's: the default action (run) does not take it over (lib/actions.sh)
    fzx::bind enter "become:$(fzx::cb action paste "$(printf '%q' "$pane")" '{+1}')" "paste the command line into $pane"
    fzx::require actions
    fzx::_action_bind_string run foreground,reload run
    fzx::bind alt-x "$run" "run the task here (projects: choose the repository)"
  fi
  return 0
}

fzx::module_main "$@"
