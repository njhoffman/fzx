#!/usr/bin/env bash
# menu: what `fzx` opens without arguments. Lists the entries of every module's manifest.sh that apply
# here; enter opens one as a child session, so alt-left comes back to the menu. Mode groups (default) puts
# the most used entries first, then the rest under group headers; mode list keeps module order.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

menu::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    "--with-nth=2,3"
    --nth=1
    --tabstop=1
    --accept-nth=1
    --no-multi
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=right,40%,wrap"
  )
  # grouped, the first row is a header: start on the entry under it, unless a saved place is restored
  local _pos="" _query=""
  if [[ "${FZX_MODE:-}" == groups ]] && fzx::in_session; then
    fzx::state_get pos _pos
    fzx::state_get query _query
    if [[ ! "$_pos" =~ ^[0-9]+$ || "$_pos" -le 1 ]] && [[ -z "$_query" ]]; then
      FZX_OPTS+=(--bind "result-final:pos(2)+unbind(result-final)")
    fi
  fi
  if fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb nav entry '{1}')" "open the entry (alt-left comes back to the menu)"
    FZX_OPTS+=(--bind "start:+bg-transform:$(fzx::cb transform refresh)")
  fi
}

fzx::module_main "$@"
