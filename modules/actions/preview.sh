#!/usr/bin/env bash
# actions preview: what the action is, how it runs and what it will run with

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# actions::flag_meaning <flag> <var>: what the flag does (lib/actions.sh lists them)
actions::flag_meaning() {
  local _m
  case "$1" in
    foreground) _m="gets the terminal (editors, sudo, followers)" ;;
    silent) _m="runs in the background; the screen does not change" ;;
    notify) _m="runs in the background; the footer says it ran, or why it failed" ;;
    become) _m="replaces fzf; its output is fzx's result" ;;
    print) _m="replaces fzf and prints a value" ;;
    reload) _m="the list reloads afterwards" ;;
    restart) _m="the screen restarts with fresh data afterwards" ;;
    confirm) _m="asks on the terminal first" ;;
    default) _m="bound to enter as well" ;;
    builtin) _m="one of fzx's own, not the module's" ;;
    *) _m="" ;;
  esac
  printf -v "$2" '%s' "$_m"
}

# actions::preview <name>
actions::preview() {
  local row k n key desc flags how a f icon label out cap mean
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
  # each flag on its own line in the color of what it does, with what it means
  actions::sgr actions_label '38;5;244' 'flags' label
  if [[ -z "$flags" || "$flags" == - ]]; then printf '%s none\n' "$label"; else printf '%s\n' "$label"; fi
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
    printf -v out '%-10s' "$f"
    actions::sgr "$how" '' "$out" out
    actions::flag_meaning "$f" mean
    actions::sgr dim '38;5;244' "$mean" mean
    printf '  %s  %s\n' "$out" "$mean"
  done
  printf '\n'
  actions::sgr actions_label '38;5;244' 'runs on:' label
  printf '%s\n' "$label"
  for a in "${ACTIONS_ARGV[@]}"; do
    actions::sgr actions_arg '38;5;152' "$a" out
    printf '  %s\n' "$out"
  done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && actions::preview "$@"
