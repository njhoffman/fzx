#!/usr/bin/env bash
# go: the go built-in (config/components.tsv: a module opts in with its own "go" row, flagged default), what
# enter does on a screen of paths. Each target is a text file (opened in $EDITOR, at its line), a directory
# (the shell goes there) or anything else (xdg-open, detached).
#
# A target is a path, "path:line[:col]" (grep matches), or what the module's <module>::go_targets prints for
# the selection (its actions.sh; one "PATH<tab>LINE" or "URL" per line, the todos module's items). Relative
# paths are the callback's directory's, which is fzf's.
#
# Anything else opens at once. Files and directories need the terminal fzx was started from, and under fzx
# fzf may be in a popup or another pane: the action records them in the root session's state/go and the
# owner carries them out once fzf is gone (fzx::go_pending). Standalone, the action does so itself.
#
# Where they go (fzx::go_dispatch):
#   FZX_ORIGIN_PANE (the tmux M-o popup, fzx-popup.sh, names the pane it was opened from): when that pane is a
#     zsh at its prompt that sources shell/fzx.zsh (its pane option @fzx_zsh holds the key, in hex, of the
#     widget that runs @fzx_go), the command line goes there: `cd -- DIR && $EDITOR +LINE -- FILE...`, with what
#     was typed set aside by push-line. Otherwise a new tmux window after the pane's, in the directory, or in
#     the first file's directory running the editor.
#   inline: the editor runs on the terminal (/dev/tty, FZX_TTY in tests). A process cannot change its shell's
#     directory: shell/fzx.zsh's fzx function passes FZX_GO_FILE and goes where fzx writes there; without
#     it the directory is printed, as enter printed it before.
# Several directories: the first one. Several files: all of them, at the first one's line.

# fzx::go [args...]: the built-in action
fzx::go() {
  local -a _kinds=() _paths=() _lines=()
  fzx::go_targets "$@" || return
  local i rc=0 req=""
  for ((i = 0; i < ${#_kinds[@]}; i++)); do
    case "${_kinds[i]}" in
      open) fzx::go_open "${_paths[i]}" || rc=1 ;;
      *) req+="${_kinds[i]}"$'\t'"${_paths[i]}"$'\t'"${_lines[i]}"$'\n' ;;
    esac
  done
  [[ -n "$req" ]] || return "$rc"
  if [[ -n "${FZX_SESSION_DIR:-}" ]]; then
    local root=""
    fzx::meta_get root root 2> /dev/null || root="${FZX_SESSION_DIR##*/}"
    printf '%s' "$req" >> "$FZX_SESSIONS_DIR/$root/state/go" || return 1
    fzx::log info "go: recorded for the owner: ${req//$'\n'/; }"
    return "$rc"
  fi
  fzx::go_dispatch <<< "${req%$'\n'}" || rc=$?
  return "$rc"
}

# fzx::go_targets [args...]: classify the selection into the caller's _kinds (edit, cd or open), _paths
# (absolute) and _lines (edit: the line, else empty); a path that does not exist is skipped with a message
fzx::go_targets() {
  local _gt_a _gt_p _gt_l _gt_hook="${FZX_MODULE:-}::go_targets" _gt_list=()
  if [[ -n "${FZX_MODULE_DIR:-}" && -f "$FZX_MODULE_DIR/actions.sh" ]] && ! declare -F "$_gt_hook" > /dev/null &&
    grep -q "^$_gt_hook()" "$FZX_MODULE_DIR/actions.sh"; then
    # shellcheck source=/dev/null
    source "$FZX_MODULE_DIR/actions.sh" || :
  fi
  if declare -F "$_gt_hook" > /dev/null; then
    while IFS= read -r _gt_a; do
      [[ -n "$_gt_a" ]] && _gt_list+=("$_gt_a")
    done < <("$_gt_hook" "$@")
  else
    for _gt_a in "$@"; do _gt_list+=("$_gt_a"); done
  fi
  for _gt_a in "${_gt_list[@]}"; do
    [[ -n "$_gt_a" ]] || continue
    _gt_l=""
    if [[ "$_gt_a" == *$'\t'* ]]; then
      _gt_p="${_gt_a%%$'\t'*}"
      _gt_l="${_gt_a#*$'\t'}"
    else
      _gt_p="$_gt_a"
      # path:line or path:line:col, unless the whole thing is a path (a colon in a file name)
      if [[ ! -e "$_gt_p" && "$_gt_p" =~ ^(.+):([0-9]+):[0-9]+$ && -e "${BASH_REMATCH[1]}" ]]; then
        _gt_p="${BASH_REMATCH[1]}"
        _gt_l="${BASH_REMATCH[2]}"
      elif [[ ! -e "$_gt_p" && "$_gt_p" =~ ^(.+):([0-9]+)$ ]]; then
        _gt_p="${BASH_REMATCH[1]}"
        _gt_l="${BASH_REMATCH[2]}"
      fi
    fi
    [[ "$_gt_l" =~ ^[0-9]+$ ]] || _gt_l=""
    # a ~ the selection kept as text
    # shellcheck disable=SC2088
    [[ "$_gt_p" == "~" || "$_gt_p" == "~/"* ]] && _gt_p="$HOME${_gt_p#\~}"
    if [[ "$_gt_p" == *://* && ! -e "$_gt_p" ]]; then
      _kinds+=(open) _paths+=("$_gt_p") _lines+=("")
      continue
    fi
    if [[ ! -e "$_gt_p" ]]; then
      printf 'fzx: go: no such file or directory: %s\n' "$_gt_p" >&2
      continue
    fi
    [[ "$_gt_p" == /* ]] || _gt_p="$PWD/${_gt_p#./}"
    if [[ -d "$_gt_p" ]]; then
      _kinds+=(cd) _paths+=("$_gt_p") _lines+=("")
    elif fzx::go_is_text "$_gt_p"; then
      _kinds+=(edit) _paths+=("$_gt_p") _lines+=("$_gt_l")
    else
      _kinds+=(open) _paths+=("$_gt_p") _lines+=("")
    fi
  done
}

# fzx::go_is_text <file>: an empty file, or one grep reads as text (no NUL bytes where it looks)
fzx::go_is_text() {
  [[ -s "$1" ]] || return 0
  LC_ALL=C grep -qI . -- "$1" 2> /dev/null
}

# fzx::go_open <path or URL>: xdg-open (macOS: open), detached, so it outlives a popup
fzx::go_open() {
  local opener
  if command -v xdg-open > /dev/null; then
    opener=xdg-open
  elif command -v open > /dev/null; then
    opener=open
  else
    printf 'fzx: go: no opener found (xdg-open or open) for %s\n' "$1" >&2
    return 1
  fi
  if command -v setsid > /dev/null; then
    command setsid -f "$opener" "$1" > /dev/null 2>&1 < /dev/null
  else
    nohup "$opener" "$1" > /dev/null 2>&1 < /dev/null &
  fi
}

# fzx::go_editor <var>: $VISUAL or $EDITOR as words (a shell function's name falls back to nvim, then vi)
fzx::go_editor() {
  local -n _ge_out="$1"
  read -ra _ge_out <<< "${VISUAL:-${EDITOR:-vi}}"
  ((${#_ge_out[@]})) && type -P "${_ge_out[0]}" > /dev/null || _ge_out=("$(type -P nvim || echo vi)")
}

# fzx::go_pending: the owner, once fzf is gone: carry out the go requests of its tree (or of the tree it
# adopted, which the sessions list resumed here)
fzx::go_pending() {
  local root f a=""
  fzx::_kv_get "$FZX_SESSIONS_DIR/$_FZX_ROOT_SESSION/state/adopt" a 2> /dev/null || a=""
  for root in "$_FZX_ROOT_SESSION" ${a:+"$a"}; do
    f="$FZX_SESSIONS_DIR/$root/state/go"
    [[ -s "$f" ]] || continue
    fzx::go_dispatch < "$f"
    rm -f -- "$f"
    return
  done
  return 0
}

# fzx::go_dispatch: requests on stdin ("KIND<tab>PATH<tab>LINE", KIND edit or cd), to the origin pane or here
fzx::go_dispatch() {
  local kind path line dir="" files=() first_line=""
  while IFS=$'\t' read -r kind path line; do
    case "$kind" in
      cd) [[ -n "$dir" ]] || dir="$path" ;;
      edit)
        ((${#files[@]})) || first_line="$line"
        files+=("$path")
        ;;
    esac
  done
  [[ -n "$dir" ]] || ((${#files[@]})) || return 0
  local editor=() cmd=()
  if ((${#files[@]})); then
    fzx::go_editor editor
    cmd=("${editor[@]}" ${first_line:+"+$first_line"} -- "${files[@]}")
  fi
  if [[ -n "${FZX_ORIGIN_PANE:-}" && -n "${TMUX:-}" ]]; then
    fzx::_go_pane "$FZX_ORIGIN_PANE" "$dir" "${cmd[@]}"
    return
  fi
  if ((${#cmd[@]})); then
    fzx::log info "go: ${cmd[*]}"
    "${cmd[@]}" <> "${FZX_TTY:-/dev/tty}" >&0 2>&0 || return
  fi
  [[ -n "$dir" ]] || return 0
  if [[ -n "${FZX_GO_FILE:-}" ]]; then
    printf '%s\n' "$dir" > "$FZX_GO_FILE"
  else
    printf '%s\n' "$dir"
  fi
}

# fzx::_go_pane <pane> <dir> [editor command...]: the shell at the pane's prompt runs it (its widget), else
# a new window after the pane's
fzx::_go_pane() {
  local pane="$1" dir="$2" info cur key line q keys=()
  shift 2
  info="$(tmux display-message -p -t "$pane" '#{pane_current_command}	#{@fzx_zsh}' 2> /dev/null)" || {
    printf 'fzx: go: no tmux pane %s\n' "$pane" >&2
    return 1
  }
  cur="${info%%$'\t'*}"
  key="${info#*$'\t'}"
  if [[ "$cur" == zsh && "$key" =~ ^[0-9a-fA-F]{2}( [0-9a-fA-F]{2})*$ ]]; then
    line=""
    if [[ -n "$dir" ]]; then
      printf -v q '%q' "$dir"
      line="builtin cd -- $q"
    fi
    if (($#)); then
      printf -v q '%q ' "$@"
      line+="${line:+ && }${q% }"
    fi
    fzx::log info "go: $pane runs: $line"
    read -ra keys <<< "$key"
    tmux set-option -p -t "$pane" @fzx_go "$line" && tmux send-keys -t "$pane" -H "${keys[@]}"
    return
  fi
  local wdir="$dir"
  if [[ -z "$wdir" ]]; then
    wdir="${*: -1}"
    wdir="${wdir%/*}"
  fi
  fzx::log info "go: $pane runs $cur: a new window in $wdir${1:+ running $*}"
  tmux new-window -a -t "$pane" -c "$wdir" "$@"
}
