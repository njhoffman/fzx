#!/usr/bin/env bash
# Global defaults. User and module config files override these by reassigning them.
# fzf also reads the user's FZF_DEFAULT_OPTS / FZF_DEFAULT_OPTS_FILE; options here are passed on the
# command line and take precedence where they overlap.

# keys handled by fzx itself in every module
declare -gA FZX_KEYS=(
  [reload_hard]=ctrl-r
  [reload_soft]=alt-r
  [mode_next]=alt-0
  [mode_prev]=alt-9
  [back]=alt-left
)

# SGR parameters (the part between ESC[ and m)
declare -gA FZX_COLORS=(
  [mode_active]="38;5;45;1"
  [mode_inactive]="38;5;240"
)

# base fzf options for every module
FZX_FZF_OPTS=(
  --ansi
  "--with-shell=bash -c"
)
