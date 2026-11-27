#!/usr/bin/env bash
# tasks: project scripts (make targets, just recipes, package.json scripts, Taskfile tasks, cargo aliases,
# pdm/poe/hatch scripts) named project:task, run in their repository.
# `fzx -m tasks[:repos|:all|:projects] [--paste PANE]`.
# Enter runs the task (projects: chooses the repository); picks and chosen projects are kept in
# $FZX_STATE_DIR/tasks. With fzx's --to PANE (--paste PANE is the same; the tmux popup passes it) enter
# pastes the command line into that pane instead, without submitting it ("cd DIR && CMD" for another
# repository's task; --submit runs it there, --loop stays open), and alt-x runs it here.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR, FZX_OUTPUT_*: read by lib/actions.sh, lib/output.sh
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
    if [[ "$pane" =~ ^%[0-9]+$ ]]; then
      export FZX_OUTPUT_PANE="$pane"
    else
      fzx::log warn "tasks: --paste needs a tmux pane id (%N): $pane"
    fi
  fi
  # into a pane goes the command line (the line action), not project:task, and no newline after it, so the
  # cursor stays on the line; lib/output.sh binds enter
  if [[ -n "${FZX_OUTPUT_PANE:-}" ]]; then
    FZX_OUTPUT_ACTION=line
    FZX_ACTION_ARGS_FOR['line']='{+1}'
    FZX_OUTPUT_NEWLINE=0
    fzx::require actions
    fzx::_action_bind_string run foreground,reload run
    fzx::bind alt-x "$run" "run the task here (projects: choose the repository)"
  fi
  return 0
}

fzx::module_main "$@"
