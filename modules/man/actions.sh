#!/usr/bin/env bash
# man actions on the selected pages: open (the pager, one after another), nvim (the first one)

# shellcheck source=./preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/preview.sh"

# man::tldr_file <name> <var>: the tldr page's markdown file (common first), or fail
man::tldr_file() {
  local _dir _p
  man::tldr_dir _dir
  [[ -n "$_dir" ]] || return 1
  for _p in common "${FZX_MAN_TLDR_PLATFORMS[@]}"; do
    [[ -f "$_dir/pages.en/$_p/$1.md" ]] && { printf -v "$2" '%s' "$_dir/pages.en/$_p/$1.md"; return 0; }
  done
  return 1
}

# man::action <open|nvim> <ids...>
man::action() {
  local action="${1:-}" id name sec file
  shift
  (($#)) || return 0
  case "$action:${FZX_MODE:-commands}" in
    open:tldr)
      for id; do command tldr --color always -- "$id"; done | ${PAGER:-less -R}
      ;;
    open:*)
      for id; do
        man::split "$id" name sec
        command man ${sec:+"$sec"} -- "$name"
      done
      ;;
    nvim:tldr)
      if man::tldr_file "$1" file; then
        command nvim -R -- "$file"
      else
        command tldr -- "$1" | command nvim -R -
      fi
      ;;
    nvim:*)
      man::split "$1" name sec
      command nvim -c "Man ${sec:+$sec }$name" -c only
      ;;
    *)
      printf 'man: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" man
  man::action "$@"
}
