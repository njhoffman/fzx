#!/usr/bin/env bash
# history actions on history ids: insert and run print the commands (run exits 10, which the zsh widget
# reads as "accept the line"), cd prints them after a cd into the directory they ran in, copy puts them on
# the clipboard, delete forgets every run of them
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# the exit status of the run action: the zsh widget runs the printed command instead of inserting it
HISTORY_RUN_STATUS=10

# history::print <id...>: the commands, one after another (newline-separated)
history::print() {
  local argv first=1
  while IFS= read -r -d '' argv; do
    ((first)) || printf '\n'
    printf '%s' "$argv"
    first=0
  done < <(history::argv "$@")
  printf '\n'
}

# history::print_cd <id...>: "cd DIR && COMMAND" for each run, the directory it ran in (~ for $HOME); a
# run whose directory is unknown prints the command alone
history::print_cd() {
  local id dir argv first=1 rest
  for id in "$@"; do
    dir="$(history::sql "select ifnull(places.dir, '') from history join places on places.id = history.place_id
      where history.id = $id")" || return
    argv="$(history::argv "$id" | tr -d '\0')"
    ((first)) || printf '\n'
    first=0
    if [[ -z "$dir" ]]; then
      printf '%s' "$argv"
    elif [[ "$dir" == "$HOME" ]]; then
      printf 'cd ~ && %s' "$argv"
    elif [[ "$dir" == "$HOME"/* ]]; then
      rest="${dir#"$HOME"/}"
      printf 'cd ~/%q && %s' "$rest" "$argv"
    else
      printf 'cd %q && %s' "$dir" "$argv"
    fi
  done
  printf '\n'
}

# history::action <insert|run|cd|copy|delete> <history id...>
history::action() {
  local action="${1:-}" ids=()
  shift
  local id
  for id in "$@"; do
    [[ "$id" =~ ^[0-9]+$ ]] || { printf 'history: not a history id: %s\n' "$id" >&2; return 2; }
    ids+=("$id")
  done
  ((${#ids[@]})) || return 0
  case "$action" in
    insert) history::print "${ids[@]}" ;;
    cd) history::print_cd "${ids[@]}" ;;
    run)
      history::print "${ids[@]}"
      return "$HISTORY_RUN_STATUS"
      ;;
    copy)
      fzx::require builtin
      history::print "${ids[@]}" | fzx::clip
      ;;
    delete)
      local list
      list="$(IFS=,; printf '%s' "${ids[*]}")"
      # every run of these commands, then the commands themselves (histdb's own --forget does the same)
      command sqlite3 -cmd ".timeout 5000" "$FZX_HISTDB_FILE" "
        create temp table forget as select distinct command_id as id from history where id in ($list);
        delete from history where command_id in (select id from forget);
        delete from commands where id in (select id from forget);" || return
      # the cached rows still hold them
      history::cache_clear
      ;;
    *)
      printf 'history: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" history
  history::action "$@"
}
