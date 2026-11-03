#!/usr/bin/env bash
# sessions defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/sessions/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰖯"
# the icon's color in the menu
FZX_COLORS[sessions_icon]="38;5;141"

# a kept tree (resumable), a live one (on screen elsewhere: enter copies it)
FZX_COLORS[sessions_kept]="38;5;114"
FZX_COLORS[sessions_live]="38;5;75"

# sessions come and go: read the directory on every load
FZX_PERSIST=none

# short details: a right preview early
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "120:right,45%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=terminal
