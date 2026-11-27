#!/usr/bin/env bash
# snippets: named snippets you keep, and the paste history (what capture's and the tmux module's paste
# actions sent; lib/snippets.sh). `fzx -m snippets[:history]`. Enter prints the text (from the M-o popup,
# pastes it into the pane), ctrl-y copies it, ctrl-e edits it, alt-n adds a snippet, alt-S keeps a history
# entry as one, alt-R renames, alt-x removes.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS*: read by lib/actions.sh
snippets::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
  )
  # new takes no rows: fzf runs no command naming one ({+1}) on an empty list
  FZX_ACTION_ARGS_FOR['new']='{q}'
}

fzx::module_main "$@"
