#!/usr/bin/env bash
# snippets actions on the selected ids (a saved snippet's, or a history entry's file name):
#   insert (print the texts; from the M-o popup, paste them into its pane), copy (to the clipboard), edit ($EDITOR), rename (saved), remove, save (history: as
#   a named snippet), new (a snippet typed in $EDITOR)

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# snippets::_file <id> <var>: the text's file for an id of the current mode; fails for none
snippets::_file() {
  local _f_dir
  fzx::require snippets
  fzx::snippets_dir _f_dir
  if [[ "${FZX_MODE:-saved}" == history ]]; then
    [[ "$1" != */* && -f "$_f_dir/history/$1" ]] && printf -v "$2" '%s' "$_f_dir/history/$1" && return 0
  else
    [[ "$1" != */* && -f "$_f_dir/saved/$1/value" ]] && printf -v "$2" '%s' "$_f_dir/saved/$1/value" && return 0
  fi
  printf 'snippets: no snippet %s\n' "$1" >&2
  return 1
}

# snippets::texts <ids...>: the texts, one after another, a newline between them
snippets::texts() {
  local id f first=1
  for id; do
    snippets::_file "$id" f || continue
    ((first)) || printf '\n'
    first=0
    command cat -- "$f"
  done
}

# snippets::action <name> [ids...]
snippets::action() {
  local action="${1:-}" id f text name dir
  shift
  fzx::require snippets
  fzx::snippets_dir dir
  case "$action" in
    insert)
      # from tmux's M-o popup (FZX_ORIGIN_PANE) the texts go into its pane as they are, a bracketed paste the
      # server makes once the popup is gone (fzx-popup.sh would quote what is printed as shell words);
      # elsewhere they are printed (the zsh widget inserts them)
      if [[ -n "${FZX_ORIGIN_PANE:-}" && -n "${TMUX:-}" ]]; then
        snippets::texts "$@" | command tmux load-buffer -b fzx-snippets - &&
          command tmux run-shell -b -d 0.3 "tmux paste-buffer -p -d -b fzx-snippets -t $FZX_ORIGIN_PANE"
      else
        snippets::texts "$@"
      fi
      ;;
    copy)
      (($#)) || return 0
      fzx::require builtin
      snippets::texts "$@" | fzx::clip
      ;;
    edit)
      snippets::_file "${1:-}" f || return
      fzx::require builtin
      fzx::edit_text text < "$f" || return 0
      printf '%s' "$text" > "$f"
      ;;
    new)
      fzx::require ask builtin
      fzx::ask "$FZX_STATE_DIR/snippets/.names" "a new snippet's name:" name || return 0
      fzx::edit_text text < /dev/null || return 0
      fzx::snippet_save "$name" "$text"
      ;;
    save)
      snippets::_file "${1:-}" f || return
      fzx::require ask
      fzx::ask "$FZX_STATE_DIR/snippets/.names" "keep it as the snippet named:" name || return 0
      fzx::snippet_save "$name" < "$f"
      ;;
    rename)
      [[ "${FZX_MODE:-saved}" == saved ]] || { printf 'snippets: rename is for saved snippets\n' >&2; return 2; }
      snippets::_file "${1:-}" f || return
      fzx::require ask
      fzx::ask "$FZX_STATE_DIR/snippets/.names" "rename $(< "${f%/value}/name") to:" name || return 0
      fzx::snippet_id "$name" id
      [[ "$id" == "$1" ]] && return 0
      fzx::snippet_save "$name" < "$f" && rm -rf -- "${f%/value}"
      ;;
    remove)
      for id; do
        snippets::_file "$id" f || continue
        if [[ "${FZX_MODE:-saved}" == history ]]; then rm -f -- "$f"; else rm -rf -- "${f%/value}"; fi
      done
      ;;
    *)
      printf 'snippets: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" snippets
  snippets::action "$@"
}
