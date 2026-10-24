#!/usr/bin/env bash
tmux::manifest() {
  fzx::entry tmux 'Tmux sessions (alt-s switches or attaches)'
  fzx::entry tmux:windows 'Tmux windows across all sessions'
  fzx::entry tmux:panes 'Tmux panes across all sessions'
  fzx::entry tmux:lines 'Capture lines from the current pane'
  fzx::entry tmux:urls 'Extract URLs from the current pane'
  fzx::entry tmux:paths 'Extract paths from the current pane'
  fzx::entry tmux:words 'Extract words and identifiers from the current pane'
  fzx::entry tmux:hashes 'Extract hashes from the current pane'
  fzx::entry tmux:ips 'Extract IPv4 addresses from the current pane'
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
