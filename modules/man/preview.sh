#!/usr/bin/env bash
# man preview: the page rendered at the preview's width (lib/render.sh: bat when installed), or the tldr page

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
# shellcheck source=../../lib/render.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/render.sh"

# man::split <id> <name var> <section var>: "name(section)" apart; a bare name has no section
man::split() {
  local _id="$1"
  if [[ "$_id" =~ ^(.+)\(([^\(\)]+)\)$ ]]; then
    printf -v "$2" '%s' "${BASH_REMATCH[1]}"
    printf -v "$3" '%s' "${BASH_REMATCH[2]}"
  else
    printf -v "$2" '%s' "$_id"
    printf -v "$3" ''
  fi
}

# man::page <id>: the page as plain text, MANWIDTH wide
man::page() {
  local name sec
  man::split "$1" name sec
  command man ${sec:+"$sec"} -- "$name" 2> /dev/null | command col -bx
}

# man::preview <id>
man::preview() {
  local id="${1:-}" cols="${FZF_PREVIEW_COLUMNS:-80}"
  [[ -n "$id" ]] || return 0
  if [[ "${FZX_MODE:-commands}" == tldr ]]; then
    command tldr --color always -- "$id" 2> /dev/null || printf 'no tldr page: %s\n' "$id"
    return 0
  fi
  MANWIDTH="$cols" man::page "$id" | fzx::render_text --language man --style plain
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && man::preview "$@"
