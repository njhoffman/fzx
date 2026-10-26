#!/usr/bin/env bash
# todos: open items of TODO.md files (todo-status's format) with priority, category, due date and the
# item's card in the preview; todo-fzf's picker. `fzx -m todos[:all] [--paste PANE] [QUERY...]`.
# Enter prints "TODO.md:LINE ☐  (Pn) [category] Title" per selected item; with --paste PANE it pastes
# those lines into that tmux pane instead (bracketed: nothing is submitted).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS*: read by lib/actions.sh
todos::opts() {
  local pane="" query=() i
  for ((i = 0; i < ${#FZX_ARGS[@]}; i++)); do
    if [[ "${FZX_ARGS[i]}" == --paste ]]; then
      pane="${FZX_ARGS[i + 1]:-}"
      ((i++))
    else
      query+=("${FZX_ARGS[i]}")
    fi
  done
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=3
    --multi
    --no-sort
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,40%,wrap,nohidden"
  )
  # the rest of the args seed the search ("p1" filters by priority, "bug" by category)
  ((${#query[@]})) && FZX_OPTS+=("--query=${query[*]}")
  FZX_ACTION_ARGS_FOR['copy']='{+4}'
  FZX_ACTION_ARGS_FOR['copy-line']='{+3}'
  if [[ -n "$pane" ]]; then
    FZX_ACTION_ARGS_FOR['paste']="$(printf '%q' "$pane") {+3}"
    fzx::bind enter "become:$(fzx::cb action paste "$(printf '%q' "$pane")" '{+3}')" "paste the lines into $pane"
  fi
  return 0
}

fzx::module_main "$@"
