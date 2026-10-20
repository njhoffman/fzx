#!/usr/bin/env bash
# actions preview: what the action is and what it will run with

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# actions::preview <name>
actions::preview() {
  local row k n key desc flags a b=$'\e[1m' r=$'\e[0m'
  actions::row "${1:-}" row || return
  IFS=$'\t' read -r k n key desc flags <<< "$row"
  fzx::session_args
  actions::argv "$n" "${FZX_ARGS[@]}" || :
  printf '%s%s%s  %s\n' "$b" "$n" "$r" "${desc#-}"
  printf 'key    %s\nflags  %s\n\nruns on:\n' "${key/#-/none}" "${flags/#-/none}"
  for a in "${ACTIONS_ARGV[@]}"; do
    printf '  %s\n' "$a"
  done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && actions::preview "$@"
