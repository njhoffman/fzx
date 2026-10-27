#!/usr/bin/env bash
# keybindings: zsh bindings in every keymap (with zle's descriptions), tmux bindings (the tmux module's
# keys) and fzf bindings (yours and fzf's defaults). `fzx -m keybindings[:tmux|:fzf]`. Enter prints the
# bindkey / bind-key lines, or the fzf keys.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

keybindings::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --multi
    --preview "$(fzx::cb preview '{1}' '{2}' '{3}')"
    "--preview-window=right,50%,wrap,nohidden"
  )
}

fzx::module_main "$@"
