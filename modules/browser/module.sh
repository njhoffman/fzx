#!/usr/bin/env bash
# browser: history and bookmarks of every Chromium-family (Chrome, Chromium, Brave, Vivaldi) and Firefox
# profile. `fzx -m browser[:bookmarks]`. Enter opens the URLs in the browser and profile each came from
# and closes; ctrl-o opens them and stays, alt-o uses xdg-open. The databases are copied before reading
# (a running browser locks them) and cached for five minutes: ctrl-r reads them again.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
browser::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{2}' '{4}' '{5}' '{6}' '{8}')"
    "--preview-window=right,35%,nohidden"
  )
  # opening needs each row's profile with its URL: "src<TAB>url" per row
  FZX_ACTION_ARGS_FOR['open']='{+1..2}'
  FZX_ACTION_ARGS_FOR['open-stay']='{+1..2}'
  FZX_ACTION_ARGS_FOR['xdg']='{+2}'
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
  FZX_ACTION_ARGS_FOR['copy-title']='{+4}'
}

fzx::module_main "$@"
