#!/usr/bin/env bash
# files actions, and grep mode's filter transform

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# files::trash <path...>: into the trash through trash-put, else gio trash; each path once (grep mode passes
# one per match). / and $HOME are refused.
files::trash() {
  local p tool
  local -a paths=()
  local -A seen=()
  if command -v trash-put > /dev/null; then
    tool=trash-put
  elif command -v gio > /dev/null; then
    tool=gio
  else
    printf 'files: trash: neither trash-put nor gio is installed\n' >&2
    return 1
  fi
  for p in "$@"; do
    [[ -n "$p" && -z "${seen[$p]:-}" ]] || continue
    seen[$p]=1
    if [[ "$p" == / || "${p%/}" == "${HOME%/}" ]]; then
      printf 'files: trash: refusing %s\n' "$p" >&2
      return 2
    fi
    paths+=("$p")
  done
  ((${#paths[@]})) || return 0
  if [[ "$tool" == trash-put ]]; then
    command trash-put -- "${paths[@]}"
  else
    command gio trash -- "${paths[@]}"
  fi
}

# files::action edit <path...> | (grep mode) edit <path> <line>: open in $EDITOR (foreground);
# files::action trash <path...>: files::trash
files::action() {
  local action="${1:-}"
  shift
  case "$action:${FZX_MODE:-files}" in
    trash:*) files::trash "$@" ;;
    edit:grep) "${EDITOR:-vi}" "+${2:-1}" -- "$1" ;;
    edit:*)
      (($#)) || return 0
      "${EDITOR:-vi}" -- "$@"
      ;;
    *)
      printf 'files: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

# files::_header <text> <var>: the action that makes text the module's header. In the footer position
# change-header; in the header position the component line sits above it and in-place refreshes rebuild
# both from meta/header, so the text goes there and the header callback draws them.
files::_header() {
  if [[ "${FZX_HEADER_POSITION:-footer}" == header ]]; then
    fzx::meta_set header "$1"
    printf -v "$2" 'transform-header(%s)' "$(fzx::cb header)"
  else
    fzx::action_arg change-header "$1" "$2" || printf -v "$2" '%s' "change-header()"
  fi
}

# files::transform filter: in grep mode, ctrl-t. Grepping, fzf takes over: the query's term is frozen (the
# source keeps grepping it on reloads and toggles) and the header shows it; filtering, the term returns to
# the query and grepping resumes. fzf keeps its filtered matches when search goes off: the reload restores
# them all.
files::transform() {
  local on="" term="" text header q reload
  [[ "${1:-}" == filter ]] || {
    printf 'files: unknown transform: %s\n' "${1:-}" >&2
    return 2
  }
  [[ "${FZX_MODE:-}" == grep ]] || return 0
  # the base directory for the header: the session's arguments, which transforms are not given
  fzx::session_args
  files::base "${FZX_ARGS[0]:-}" || return
  text="${FILES_BASE/#$HOME/\~}"
  fzx::require opts
  fzx::state_get files_grep_filter on 2> /dev/null || on=""
  if [[ -z "$on" ]]; then
    term="${FZF_QUERY:-}"
    fzx::state_set files_grep_term "$term"
    fzx::state_set files_grep_filter 1
    files::_header "$text  grep: $term  (${FZX_KEYS[files.filter]:-ctrl-t} greps again)" header
    printf 'unbind(change)+enable-search+change-query()+%s' "$header"
  else
    fzx::state_get files_grep_term term 2> /dev/null || term=""
    fzx::state_set files_grep_filter ""
    fzx::action_arg change-query "$term" q || q="change-query()"
    files::_header "$text" header
    fzx::reload_action "$(fzx::cb source)" reload
    printf 'rebind(change)+disable-search+%s+%s+%s' "$q" "$header" "$reload"
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && files::action "$@"
