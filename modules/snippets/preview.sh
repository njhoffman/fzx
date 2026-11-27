#!/usr/bin/env bash
# snippets preview: the snippet's name, or when and from where the paste was, then the text as it is

# shellcheck source=./actions.sh
source "$(dirname "${BASH_SOURCE[0]}")/actions.sh"

# snippets::preview <id>
snippets::preview() {
  local id="${1:-}" f dir b=$'\e[1m' dim=$'\e['"${FZX_COLORS[snippets_dim]:-38;5;244}m" r=$'\e[0m' when
  [[ -n "${NO_COLOR:+x}" ]] && b="" dim="" r=""
  [[ -n "$id" ]] || return 0
  snippets::_file "$id" f 2> /dev/null || return 0
  if [[ "${FZX_MODE:-saved}" == history ]]; then
    when="$(date -d "@${id:0:10}" '+%F %T' 2> /dev/null)"
    printf '%spasted%s %s %sfrom%s %s\n\n' "$dim" "$r" "$when" "$dim" "$r" "${id#*.}"
  else
    printf '%s%s%s\n\n' "$b" "$(< "${f%/value}/name")" "$r"
  fi
  command cat -v -- "$f"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" snippets
  snippets::preview "$@"
}
