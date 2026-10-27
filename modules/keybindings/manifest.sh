#!/usr/bin/env bash
# keybindings menu entries

keybindings::manifest() {
  fzx::entry keybindings "zsh key bindings"
  fzx::entry keybindings:tmux "tmux key bindings"
  fzx::entry keybindings:fzf "fzf key bindings"
}

keybindings::applicable() {
  case "$1" in
    keybindings) command -v zsh > /dev/null ;;
    keybindings:tmux) command -v tmux > /dev/null && command tmux list-sessions > /dev/null 2>&1 ;;
    *) return 0 ;;
  esac
}
