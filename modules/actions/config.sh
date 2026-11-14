#!/usr/bin/env bash
# actions defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/actions/config.sh

# shellcheck disable=SC2034  # read by lib/ and the module
# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=shell

declare -gA FZX_COLORS
# the rows: the module's action names, fzx's own (copy, copy-line, view), the enter row (what enter does
# when it is not a default action), the key, the default (enter) mark
FZX_COLORS[actions_name]='1;38;5;255'
FZX_COLORS[actions_builtin]='38;5;248'
FZX_COLORS[actions_enter]='1;38;5;114'
FZX_COLORS[actions_key]='38;5;180;48;5;236'
FZX_COLORS[actions_default]='38;5;114'
# the icon of how the action runs: in the terminal, in the background, in fzf's place, asking first; the
# reload mark; the preview's labels and the arguments the action runs on
FZX_COLORS[actions_run]='38;5;110'
FZX_COLORS[actions_silent]='38;5;244'
FZX_COLORS[actions_become]='38;5;213'
FZX_COLORS[actions_confirm]='38;5;203'
FZX_COLORS[actions_reload]='38;5;66'
FZX_COLORS[actions_label]='38;5;244'
FZX_COLORS[actions_arg]='38;5;152'
