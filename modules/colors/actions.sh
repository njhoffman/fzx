#!/usr/bin/env bash
# colors actions: copy the selection's hex values, SGR parameters or escape sequences

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# colors::action <hex|sgr|escape> <values...> (hex: the hex fields; sgr, escape: the sgr fields)
colors::action() {
  local action="${1:-}" v out=()
  shift
  fzx::require builtin
  case "$action" in
    hex | sgr) for v; do [[ -n "$v" ]] && out+=("$v"); done ;;
    escape) for v; do [[ -n "$v" ]] && out+=("\\e[${v}m"); done ;;
    *)
      printf 'colors: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  ((${#out[@]})) || return 0
  printf '%s\n' "${out[@]}" | fzx::clip
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log
  colors::action "$@"
}
