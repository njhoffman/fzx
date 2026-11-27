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

# man::zsh_pattern <name> <var>: a less search for the entry's line: the name at man's 7-column indent, then a
# word boundary (a name ending in a word character), else a blank (. and -); its regex characters escaped. No
# $: in a + command less takes it for the end of the option string
man::zsh_pattern() {
  # shellcheck disable=SC2016  # the regex characters, not an expansion
  local _zp_e="$1" _zp_c _zp_out="" _zp_i _zp_special='\.[]*?+^$(){}|' _zp_end=' '
  for ((_zp_i = 0; _zp_i < ${#_zp_e}; _zp_i++)); do
    _zp_c="${_zp_e:_zp_i:1}"
    [[ "$_zp_special" == *"$_zp_c"* ]] && _zp_out+="\\"
    _zp_out+="$_zp_c"
  done
  [[ "${_zp_e: -1}" == [[:alnum:]_] ]] && _zp_end='\b'
  printf -v "$2" '^ {7}%s%s' "$_zp_out" "$_zp_end"
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
    open:zsh)
      # less opens each page at its entry: man's output piped into it at the terminal's width (man's -P splits
      # its pager on blanks, which the pattern holds); without less, man and its own pager
      local pat cols
      cols="$(tput cols 2> /dev/null < /dev/tty)" || cols=80
      for id; do
        if command -v less > /dev/null; then
          man::zsh_pattern "${id#*:}" pat
          MANWIDTH="$cols" command man -- "${id%%:*}" 2> /dev/null | command less -R -j3 "+/$pat"
        else
          command man -- "${id%%:*}"
        fi
      done
      ;;
    nvim:zsh)
      # the entry's line: the name at the 7-column indent, then a word's end (\>) or a blank, as for less
      local vname="${1#*:}" vend=' ' vpat
      [[ "${vname: -1}" == [[:alnum:]_] ]] && vend='\>'
      vname="${vname//\\/\\\\}"
      vname="${vname//\'/\'\'}"
      vpat='^\s\{7}\V'"$vname"'\m'"$vend"
      # at VimEnter: the -c commands run before something at startup puts the cursor back on the first line
      command nvim -c "Man ${1%%:*}" -c only -c "autocmd VimEnter * ++once call search('$vpat')"
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
