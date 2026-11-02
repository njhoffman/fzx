#!/usr/bin/env bash
# actions preview: what the action is, how it runs and what it will run with

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# actions::preview <name>
actions::preview() {
  local row k n key desc flags how a f icon label out cap tags="" sep=""
  actions::row "${1:-}" row || return
  IFS=$'\t' read -r k n key desc flags <<< "$row"
  fzx::session_args
  actions::argv "$n" "${FZX_ARGS[@]}" || :
  actions::how_icon "$flags" icon
  actions::sgr actions_name '1' "$n" out
  printf '%s%s  %s\n\n' "$icon" "$out" "${desc#-}"
  actions::sgr actions_label '38;5;244' 'key  ' label
  if [[ "$key" == - ]]; then
    actions::sgr dim '38;5;244' none cap
  else
    actions::sgr actions_key '38;5;180;48;5;236' " $key " cap
  fi
  printf '%s %s\n' "$label" "$cap"
  # each flag in the color of what it does
  for f in ${flags//,/ }; do
    [[ "$f" == - ]] && continue
    case "$f" in
      confirm) how=actions_confirm ;;
      become | print) how=actions_become ;;
      silent | notify) how=actions_silent ;;
      reload | restart) how=actions_reload ;;
      default) how=actions_default ;;
      builtin) how=actions_builtin ;;
      *) how=actions_run ;;
    esac
    actions::sgr "$how" '' "$f" out
    tags+="$sep$out" sep=" "
  done
  actions::sgr actions_label '38;5;244' 'flags' label
  printf '%s %s\n\n' "$label" "${tags:-none}"
  actions::sgr actions_label '38;5;244' 'runs on:' label
  printf '%s\n' "$label"
  for a in "${ACTIONS_ARGV[@]}"; do
    actions::sgr actions_arg '38;5;152' "$a" out
    printf '  %s\n' "$out"
  done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && actions::preview "$@"
