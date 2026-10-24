#!/usr/bin/env bash
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

tmux::preview() {
  tmux::args "$@" || return
  local id="${TMUX_IDS[0]:-}" display="${TMUX_IDS[1]:-}" metadata="${TMUX_IDS[2]:-}" pane
  [[ -n "$id" ]] || return 0
  case "${FZX_MODE:-sessions}" in
    sessions | windows | panes)
      printf '%s\n\n' "$display"
      pane="$(command tmux display-message -p -t "$id" '#{pane_id}')" || return
      tmux::capture "$pane"
      ;;
    buffers) command tmux show-buffer -b "$id" ;;
    lines | urls | paths | words | hashes | ips)
      printf '%s\n\nCaptured from %s; alt-p pastes without pressing Enter.\n' "$id" "${TMUX_TARGET_PANE:-the current pane}"
      ;;
    keys | commands | options | variables | styles | formats | status | hooks)
      tmux::reference preview "$FZX_MODE" --identifier "$id" --metadata "${metadata:-\{\}}"
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && tmux::preview "$@"
