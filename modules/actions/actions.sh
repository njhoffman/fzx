#!/usr/bin/env bash
# actions actions: run one of the parent screen's actions, then return to it.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# actions::transform run <name>: actions that replace fzf (become, print) take over; the others run in
# the foreground, then the menu goes back to the screen it was opened from
actions::transform() {
  local row flags cmd
  [[ "${1:-}" == run ]] || {
    printf 'actions: unknown transform: %s\n' "${1:-}" >&2
    return 2
  }
  actions::row "${2:-}" row || return
  fzx::require opts
  flags=",${row##*$'\t'},"
  cmd="$(fzx::cb action run "$2")"
  if [[ "$flags" == *,become,* || "$flags" == *,print,* ]]; then
    printf 'become(%s)' "$cmd"
  else
    printf 'execute(%s)+transform(%s)' "$cmd" "$(fzx::cb nav back)"
  fi
}

# actions::action run <name>: the parent's action with the arguments the menu was opened with
actions::action() {
  local dir row flags
  [[ "${1:-}" == run ]] || {
    printf 'actions: unknown action: %s\n' "${1:-}" >&2
    return 2
  }
  actions::parent dir || return
  actions::row "${2:-}" row || {
    printf 'actions: no action %s\n' "${2:-}" >&2
    return 2
  }
  flags=",${row##*$'\t'},"
  fzx::session_args
  actions::argv "$2" "${FZX_ARGS[@]}" || :
  # the parent reloads when it comes back: its next load runs the source instead of the cache
  [[ "$flags" == *,reload,* || "$flags" == *,restart,* ]] && fzx::_kv_set "$dir/state/fresh" 1
  env -u FZX_MODE -u FZX_TOGGLES -u FZX_SORT FZX_SESSION="${dir##*/}" \
    "$FZX_BIN" _cb action "$2" "${ACTIONS_ARGV[@]}"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && actions::action "$@"
