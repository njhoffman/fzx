#!/usr/bin/env bash
# colors defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/colors/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰏘"

# the icon's color in the menu
declare -gA FZX_COLORS
FZX_COLORS[colors_icon]="38;5;213"

# fzx mode reads the current config: no cache
FZX_PERSIST=none

# X11 color names (lines "R G B name")
FZX_COLORS_RGB_TXT="${FZX_COLORS_RGB_TXT:-/usr/share/X11/rgb.txt}"

# names and codes are short and the swatch fills any width: the preview moves right from 100 columns
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top" "100:right,50%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=terminal
