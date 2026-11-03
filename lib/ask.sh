#!/usr/bin/env bash
# ask: a line typed on the terminal with readline and a history of earlier answers, for actions that take
# free text (docker's typed commands, firewall rules). Each history is a file, newest answer last.

# fzx::ask_remember <history file> <line> [max]: add the line as the newest (once; max kept, default 200)
fzx::ask_remember() {
  local file="$1" tmp
  mkdir -p -- "${file%/*}"
  tmp="$file.$BASHPID"
  { [[ -f "$file" ]] && grep -vxF -- "$2" "$file"; printf '%s\n' "$2"; } | tail -n "${3:-200}" > "$tmp"
  mv -f -- "$tmp" "$file"
}

# fzx::ask <history file> <prompt> <var> [max]: read a line from the terminal (up and down: the history);
# fails on end of input or a blank line, else remembers it and sets var
fzx::ask() {
  local _file="$1" _prompt="$2" _line
  set -o history
  history -c
  [[ -f "$_file" ]] && history -r "$_file"
  read -r -e -p $'\e[1m'"$_prompt"$'\e[0m ' _line < /dev/tty || { set +o history; return 1; }
  set +o history
  [[ -n "${_line// /}" ]] || return 1
  fzx::ask_remember "$_file" "$_line" "${4:-200}"
  printf -v "$3" '%s' "$_line"
}
