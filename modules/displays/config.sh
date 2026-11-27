#!/usr/bin/env bash
# displays defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/displays/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰍹"
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[profiles]="󰕮"
# the icon's color in the menu
FZX_COLORS[displays_icon]="38;5;110"
FZX_COLORS[displays_icon_profiles]="38;5;140"

# an output on screen (and the mode it shows); disconnected outputs and profiles that do not fit
FZX_COLORS[displays_on]="38;5;114"
FZX_COLORS[displays_dim]="38;5;244"

# how many of an output's modes its preview lists (enter lists them all)
FZX_DISPLAYS_PREVIEW_MODES="${FZX_DISPLAYS_PREVIEW_MODES:-12}"

# monitors come and go and every action changes the layout: read xrandr on every load
FZX_PERSIST=none

# short details: below until 150, then on the right
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top" "150:right,45%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system

# displayd (~/git/displayd), for the profiles mode, monitor names and the header; empty or missing: xrandr alone
FZX_DISPLAYS_DISPLAYD="${FZX_DISPLAYS_DISPLAYD-displayd}"
