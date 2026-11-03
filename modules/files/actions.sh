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

# files::wait: keep the outcome on screen until a key (foreground actions return to fzf at once). What the
# replace actions tell goes to stdout: an action's stderr goes to the log
files::wait() {
  [[ -t 1 ]] || return 0
  printf '\n\e[2m(press a key)\e[0m'
  read -rsn1 < /dev/tty || :
}

# files::_session_term: FILES_DIR and FILES_TERM from the session's arguments (the replace screen's)
files::_session_term() {
  fzx::require session
  fzx::session_args
  files::args "${FZX_ARGS[@]}" || return
  files::base "$FILES_DIR" || return
  [[ -n "$FILES_TERM" ]] || { printf 'files: no term to replace\n'; return 2; }
}

# files::_replace_file <file> <replacement> <lines...>: the file with the term replaced on those lines only,
# on stdout. ripgrep rewrites the whole file (--passthru), so its regex and capture groups ($1) are what the
# rows showed; the given lines come from its output, the others stay. Fails when the line count changed
files::_replace_file() {
  local file="$1" repl="$2" new
  shift 2
  new="$(mktemp)" || return
  command rg --no-config --passthru --no-line-number --no-filename --color=never --smart-case \
    --replace "$repl" -- "$FILES_TERM" "$file" > "$new"
  awk -v lines="$*" 'BEGIN { n = split(lines, l, " "); for (i = 1; i <= n; i++) want[l[i]] = 1 }
    NR == FNR { new[FNR] = $0; nn = FNR; next }
    { print (FNR in want && FNR <= nn) ? new[FNR] : $0; no = FNR }
    END { if (no != nn) exit 3 }' "$new" "$file"
  local rc=$?
  rm -f -- "$new"
  return "$rc"
}

# files::replace_apply <replacement> <paths...> -- <lines...>: the replacement into the selected matches
# (FZF_SELECT_COUNT 0: every match of the term), after a question naming how many lines in how many files.
# Each changed file is copied first into a new backup under $FZX_STATE_DIR/files/replace (undo puts the
# newest back), then written in place (cat >, so its mode, owner and links stay); a file whose last line had
# no newline keeps it that way
files::replace_apply() {
  local repl="${1-}" paths=() lines=() p i n=0 rc=0
  shift
  files::_session_term || { files::wait; return 2; }
  while (($#)) && [[ "$1" != -- ]]; do paths+=("$1"); shift; done
  (($#)) && shift
  lines=("$@")
  if [[ "${FZF_SELECT_COUNT:-0}" == 0 ]]; then
    paths=() lines=()
    while IFS=$'\t' read -r p i; do paths+=("$p") lines+=("$i"); done < <(files::replace_matches "$FILES_TERM")
  fi
  ((${#paths[@]})) || { printf 'files: nothing to replace\n'; files::wait; return 0; }
  ((${#paths[@]} == ${#lines[@]})) || { printf 'files: replace: paths and lines do not pair up\n' >&2; return 2; }
  local -A per=()
  local order=()
  for ((i = 0; i < ${#paths[@]}; i++)); do
    [[ -n "${per[${paths[i]}]+x}" ]] || order+=("${paths[i]}")
    per[${paths[i]}]+="${lines[i]} "
  done
  fzx::require builtin
  local what="replace ${FILES_TERM@Q} with ${repl@Q}"
  [[ -z "$repl" ]] && what="delete ${FILES_TERM@Q} (the replacement is empty)"
  fzx::confirm "$what" "in ${#paths[@]} lines of ${#order[@]} files?" || return 0
  local dir out k=0 old
  # names sort by time (glob order): the newest is the last
  dir="${FZX_STATE_DIR}/files/replace/$(date +%Y%m%d-%H%M%S.%N)"
  mkdir -p -- "$dir" || return
  printf '%s\t%s\n' "$FILES_TERM" "$repl" > "$dir/what"
  for p in "${order[@]}"; do
    out="$(mktemp)" || return
    # shellcheck disable=SC2086  # the line numbers as words
    if ! files::_replace_file "$p" "$repl" ${per[$p]} > "$out"; then
      printf 'files: %s: the replacement changes its line count; left as it was\n' "$p"
      rm -f -- "$out"
      rc=1
      continue
    fi
    # the file had no newline at its end: neither does the result
    [[ -s "$p" && -n "$(tail -c1 -- "$p")" ]] && truncate -s -1 -- "$out"
    if cmp -s -- "$out" "$p"; then rm -f -- "$out"; continue; fi
    k=$((k + 1))
    cp -p -- "$p" "$dir/$k" || { rm -f -- "$out"; rc=1; continue; }
    cat -- "$out" > "$p" || rc=1
    rm -f -- "$out"
    printf '%s\t%s\t%s\n' "$k" "$(sha256sum < "$p" | cut -d' ' -f1)" "$p" >> "$dir/files"
    n=$((n + $(wc -w <<< "${per[$p]}")))
  done
  if ((k == 0)); then
    rm -rf -- "$dir"
    printf 'nothing changed\n'
  else
    printf 'replaced %s lines in %s files (the undo action puts them back)\n' "$n" "$k"
    # keep the newest FZX_FILES_REPLACE_KEEP backups
    old=("${FZX_STATE_DIR}"/files/replace/*/)
    while ((${#old[@]} > ${FZX_FILES_REPLACE_KEEP:-20})); do
      rm -rf -- "${old[0]}"
      old=("${old[@]:1}")
    done
  fi
  ((rc)) && files::wait
  return "$rc"
}

# files::replace_undo: put back the files the newest replacement changed, after a question naming it, each
# only while it is as the replacement left it (else it is named and left alone); the backup goes once used
files::replace_undo() {
  local dir k sum p cur put=0 kept=0
  local all=()
  shopt -s nullglob
  all=("${FZX_STATE_DIR}"/files/replace/*/)
  shopt -u nullglob
  ((${#all[@]})) && dir="${all[-1]}"
  [[ -n "$dir" && -f "$dir/files" ]] || { printf 'files: no replacement to undo\n'; files::wait; return 0; }
  dir="${dir%/}"
  local term="" repl="" n
  IFS=$'\t' read -r term repl < "$dir/what" || :
  n="$(wc -l < "$dir/files")"
  fzx::require builtin
  fzx::confirm "undo: replace ${term@Q} with ${repl@Q}" "put back $n files?" || return 0
  while IFS=$'\t' read -r k sum p; do
    cur="$(sha256sum < "$p" 2> /dev/null | cut -d' ' -f1)"
    if [[ "$cur" != "$sum" ]]; then
      printf 'files: %s changed since the replacement: left as it is\n' "$p"
      kept=$((kept + 1))
      continue
    fi
    cat -- "$dir/$k" > "$p" && put=$((put + 1))
  done < "$dir/files"
  rm -rf -- "$dir"
  printf 'put back %s files%s\n' "$put" "$( ((kept)) && printf ', %s changed since and left alone' "$kept")"
  ((kept)) && files::wait
  return 0
}

# files::action edit <path...> | (grep mode) edit <path> <line>: open in $EDITOR (foreground);
# files::action trash <path...>: files::trash
files::action() {
  local action="${1:-}"
  shift
  case "$action:${FZX_MODE:-files}" in
    trash:*) files::trash "$@" ;;
    edit:grep | edit:replace) "${EDITOR:-vi}" "+${2:-1}" -- "$1" ;;
    apply:replace) files::replace_apply "$@" ;;
    apply:*) printf 'files: apply is the replace screen'"'"'s (alt-s in grep)\n' >&2; return 2 ;;
    undo:grep | undo:replace) files::replace_undo ;;
    undo:*) printf 'files: undo puts back a replacement: from grep or its replace screen\n' >&2; return 2 ;;
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

# files::transform replace: in grep mode, alt-s: the replace screen for the term (the frozen one while fzf
# filters the matches, else the query), a child session: back returns to grep
files::_transform_replace() {
  local term="${FZF_QUERY:-}"
  [[ "${FZX_MODE:-}" == grep ]] || return 0
  fzx::session_args
  files::args "${FZX_ARGS[@]}" || return
  files::base "$FILES_DIR" || return
  files::grep_term term
  [[ -n "$term" ]] || { printf 'bell'; return 0; }
  fzx::require nav
  fzx::nav goto files:replace "$FILES_BASE" --term "$term"
}

# files::transform filter: in grep mode, ctrl-t. Grepping, fzf takes over: the query's term is frozen (the
# source keeps grepping it on reloads and toggles) and the header shows it; filtering, the term returns to
# the query and grepping resumes. fzf keeps its filtered matches when search goes off: the reload restores
# them all.
files::transform() {
  local on="" term="" text header q reload
  [[ "${1:-}" == replace ]] && { files::_transform_replace; return; }
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
