#!/usr/bin/env bash
# shellcheck disable=SC2034
FZX_ICON=""
# shellcheck disable=SC2034
declare -gA FZX_KEYS
FZX_KEYS[tmux.capture]=ctrl-o
FZX_PERSIST=none
# Optional installed helpers used by the tmux.* aliases. Override for another layout.
FZX_TMUX_HELPERS="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts"
# shellcheck disable=SC2034
declare -gA FZX_COLORS
# the icon's color in the menu
FZX_COLORS[tmux_icon]='38;5;34'
FZX_COLORS[tmux_name]='38;5;81'
FZX_COLORS[tmux_value]='38;5;152'
FZX_COLORS[tmux_scope]='38;5;250'
FZX_COLORS[tmux_key]='1;38;5;255'
FZX_COLORS[tmux_changed]='1;38;5;159'
FZX_COLORS[tmux_dim]='38;5;245'
FZX_COLORS[tmux_title]='1;38;5;111'
FZX_COLORS[tmux_flag]='38;5;176'

# a pane's capture is as wide as the pane: below until 160 columns, then a wide preview on the right
FZX_PREVIEW_LAYOUTS=("0:down,55%,border-top" "160:right,60%")
# wide content: a larger popup than the default
FZX_POPUP_LAYOUTS=("0:center,100%" "140:center,95%,90%" "220:center,90%,85%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=terminal
