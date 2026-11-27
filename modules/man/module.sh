#!/usr/bin/env bash
# man: man pages (commands or every section), tldr pages and the zsh manual's entries (options, builtins,
# parameters, widgets), rendered in the preview. `fzx -m man[:all|:tldr|:zsh]`. Enter opens the page in the
# pager (zsh: less at the entry); alt-n in nvim.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

man::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    # a match at the line's start (the name), then the list's order (shorter names first) wins
    "--tiebreak=begin,index"
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,60%,nohidden"
  )
}

fzx::module_main "$@"
