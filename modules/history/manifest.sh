#!/usr/bin/env bash
# history menu entries

history::manifest() {
  fzx::entry history:directory "Command history in this directory (histdb)"
  fzx::entry history "Command history on this machine (histdb)"
}

history::applicable() {
  command -v sqlite3 > /dev/null && [[ -r "${FZX_HISTDB_FILE:-$HOME/.histdb/zsh-history.db}" ]]
}

history::summary() {
  local db="${FZX_HISTDB_FILE:-$HOME/.histdb/zsh-history.db}" dir="${PWD//\'/\'\'}"
  case "$1" in
    history:directory)
      printf '%s commands\n' "$(command sqlite3 -readonly "$db" "select count(distinct command_id) from history
        join places on places.id = history.place_id where places.dir = '$dir'" 2> /dev/null)"
      ;;
    *) printf '%s commands\n' "$(command sqlite3 -readonly "$db" "select count(*) from commands" 2> /dev/null)" ;;
  esac
}
