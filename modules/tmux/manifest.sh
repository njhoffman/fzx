#!/usr/bin/env bash
tmux::manifest() {
  fzx::entry tmux 'Tmux sessions (alt-s switches or attaches)'
  fzx::entry tmux:windows 'Tmux windows across all sessions'
  fzx::entry tmux:panes 'Tmux panes across all sessions'
  fzx::entry tmux:buffers 'Tmux paste buffers'
  fzx::entry tmux:keys 'Tmux key bindings'
  fzx::entry tmux:commands 'Tmux command signatures'
  fzx::entry tmux:options 'Tmux options and values'
  fzx::entry tmux:variables 'Tmux format variables and values'
  fzx::entry tmux:styles 'Tmux styles'
  fzx::entry tmux:formats 'Tmux format templates and rendered samples'
  fzx::entry tmux:status 'Tmux status line samples'
  fzx::entry tmux:hooks 'Tmux hooks by scope'
}

tmux::applicable() { command -v tmux > /dev/null && command -v python3 > /dev/null; }
