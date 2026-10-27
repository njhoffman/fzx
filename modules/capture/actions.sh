#!/usr/bin/env bash
# capture actions: paste values into the origin pane; the transforms that move to another pane of the
# window and redraw the header
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# capture::header <var>: which pane is read, its place among the window's panes, how much it holds and the
# keys that move on: "pane 2/3  %14  nvim  ~/src  ·  1840 lines, 41 on screen  ·  alt-. alt-, other panes"
capture::header() {
  local _panes _n=0 _i=0 _p _cmd _path _keys=""
  _panes="$(command tmux list-panes -t "$CAPTURE_PANE" -F '#{pane_id}' 2> /dev/null)"
  while IFS= read -r _p; do
    ((++_n))
    [[ "$_p" == "$CAPTURE_PANE" ]] && _i="$_n"
  done <<< "$_panes"
  IFS=$'\t' read -r _cmd _path < <(command tmux display-message -p -t "$CAPTURE_PANE" $'#{pane_current_command}\t#{pane_current_path}')
  capture::geometry "$CAPTURE_PANE"
  ((_n > 1)) && _keys="  ·  ${FZX_KEYS[capture.next]:-alt-.} ${FZX_KEYS[capture.prev]:-alt-,} other panes"
  printf -v "$1" 'pane %s/%s  %s  %s  %s  ·  %s lines, %s on screen%s' "$_i" "$_n" "$CAPTURE_PANE" "$_cmd" \
    "${_path/#$HOME/\~}" "$((CAPTURE_HISTORY + CAPTURE_HEIGHT))" "$CAPTURE_HEIGHT" "$_keys"
}

# capture::transform pane <next|prev> [args...] -- : read the window's next/previous pane (wrapping),
# remembered for the session; then redraw the header and reload
# capture::transform header [args...] -- : the header text (through transform-header)
capture::transform() {
  local verb="${1:-}" dir panes=() i n reload
  shift
  case "$verb" in
    pane)
      dir="${1:-next}"
      shift
      capture::args "$@" || return
      mapfile -t panes < <(command tmux list-panes -t "$CAPTURE_PANE" -F '#{pane_id}')
      n="${#panes[@]}"
      ((n > 1)) || return 0
      for ((i = 0; i < n; i++)); do [[ "${panes[i]}" == "$CAPTURE_PANE" ]] && break; done
      if [[ "$dir" == prev ]]; then i=$(((i - 1 + n) % n)); else i=$(((i + 1) % n)); fi
      fzx::state_set capture_pane "${panes[i]}"
      fzx::require opts
      fzx::reload_action "$(fzx::cb load)" reload
      printf 'transform-header(%s)+%s' "$(fzx::cb transform header "$@")" "$reload"
      ;;
    header)
      local h
      capture::args "$@" || return
      capture::header h
      # with the component line in the header, it stays above the module's header
      if [[ "${FZX_HEADER_POSITION:-footer}" == header ]]; then
        fzx::meta_set header "$h"
        fzx::require nav
        fzx::nav_header
      else
        printf '%s\n' "$h"
      fi
      ;;
    *) return 2 ;;
  esac
}

# capture::action paste [args...] -- <values...>: the values, one per line, into the origin pane as a
# bracketed paste through a private buffer (nothing typed as keys, no Enter)
capture::action() {
  local action="${1:-}" args=() buffer rc
  shift
  [[ "$action" == paste ]] || { printf 'capture: unknown action: %s\n' "$action" >&2; return 2; }
  while (($#)) && [[ "$1" != -- ]]; do args+=("$1"); shift; done
  shift
  (($#)) || return 0
  capture::args "${args[@]}" || return
  buffer="fzx-capture-$BASHPID"
  # one value per line, no newline after the last
  (
    IFS=$'\n'
    printf '%s' "$*"
  ) | command tmux load-buffer -b "$buffer" - || return
  command tmux paste-buffer -p -d -b "$buffer" -t "$CAPTURE_ORIGIN"
  rc=$?
  ((rc == 0)) || command tmux delete-buffer -b "$buffer" 2> /dev/null
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" capture
  capture::action "$@"
}
