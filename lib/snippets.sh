#!/usr/bin/env bash
# snippets: the paste history and the saved snippets the snippets module lists, under
# $FZX_STATE_DIR/snippets:
#   history/<ns time>.<source>   one file a paste fzx made (capture's paste and edit, the tmux module's buffer
#                                paste and edit): the text as it was pasted; newest last by name. The same
#                                text pasted again moves to the newest; FZX_SNIPPETS_HISTORY_MAX (200) kept;
#                                FZX_SNIPPETS_HISTORY=0 records nothing
#   saved/<id>/name, value       a named snippet; the id is the name's sha1, so a name can hold any character
#                                and saving under a name again replaces its text

# fzx::snippets_dir <var>: the snippets' directory
fzx::snippets_dir() { printf -v "$1" '%s/snippets' "$FZX_STATE_DIR"; }

# fzx::paste_record <source> <text>: add a paste to the history (see above); never fails the paste
fzx::paste_record() {
  [[ "${FZX_SNIPPETS_HISTORY:-1}" != 0 && -n "${2:-}" ]] || return 0
  local _pr_dir _pr_f _pr_tmp _pr_files=() _pr_max="${FZX_SNIPPETS_HISTORY_MAX:-200}" _pr_now
  fzx::snippets_dir _pr_dir
  _pr_dir+=/history
  mkdir -p -- "$_pr_dir" 2> /dev/null || return 0
  # the same text again: the older copy goes
  for _pr_f in "$_pr_dir"/*; do
    [[ -f "$_pr_f" ]] && [[ "$(command cat -- "$_pr_f"; printf x)" == "$2"x ]] && rm -f -- "$_pr_f"
  done
  _pr_now="$(date +%s%N)"
  _pr_tmp="$_pr_dir/.$_pr_now.$BASHPID"
  if ! printf '%s' "$2" > "$_pr_tmp" || ! mv -f -- "$_pr_tmp" "$_pr_dir/$_pr_now.${1//[^a-z0-9-]/}"; then
    rm -f -- "$_pr_tmp"
  fi
  mapfile -t _pr_files < <(command ls -1 -- "$_pr_dir" 2> /dev/null | LC_ALL=C sort)
  while ((${#_pr_files[@]} > _pr_max)); do
    rm -f -- "$_pr_dir/${_pr_files[0]}"
    _pr_files=("${_pr_files[@]:1}")
  done
  return 0
}

# fzx::snippet_id <name> <var>: a saved snippet's id (its name's sha1)
fzx::snippet_id() {
  local _si
  _si="$(printf '%s' "$1" | sha1sum)"
  printf -v "$2" '%s' "${_si%% *}"
}

# fzx::snippet_save <name> [text]: save (or replace) the named snippet; without a text, stdin as it is
fzx::snippet_save() {
  local _ss_dir _ss_id
  [[ -n "$1" ]] || return 1
  fzx::snippets_dir _ss_dir
  fzx::snippet_id "$1" _ss_id
  mkdir -p -- "$_ss_dir/saved/$_ss_id" || return 1
  printf '%s' "$1" > "$_ss_dir/saved/$_ss_id/name" || return 1
  if (($# > 1)); then printf '%s' "$2" > "$_ss_dir/saved/$_ss_id/value"; else command cat > "$_ss_dir/saved/$_ss_id/value"; fi
}
