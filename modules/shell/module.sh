#!/usr/bin/env bash
# shell: commands on PATH and zsh's builtins, aliases, functions and parameters (the environment fzx started
# in, and the zsh dump's), each with its man/tldr page, expansion, definition or value in the preview.
# `fzx -m shell[:aliases|:functions|:params|:completions]` (completions: zsh-complete's bindings); shell/fzx.zsh's shell widget (alt-s) dumps the shell first,
# so its local state shows, and inserts the names.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
shell::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=1
    --multi
    # a match at the name's start, then the list's order
    "--tiebreak=begin,index"
    --preview "$(fzx::cb preview '{1}' '{2}')"
    "--preview-window=right,55%,nohidden"
  )
  # rescan needs no row: an empty list (zsh-complete failed) still has the query
  FZX_ACTION_ARGS_FOR['rescan']='{q}'
  # the environment fzx started with, once per session: later callbacks run under fzf, which adds its own
  if [[ -n "${FZX_SESSION_DIR:-}" && ! -f "$FZX_SESSION_DIR/data/env" ]]; then
    shell::save_env "$FZX_SESSION_DIR/data/env"
  fi
}

fzx::module_main "$@"
