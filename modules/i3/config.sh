#!/usr/bin/env bash
# i3 defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/i3/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󱂬"
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[workspaces]="󰕰"
FZX_ICON_MODES[scratchpad]="󰘸"
# the icon's color in the menu
FZX_COLORS[i3_icon]="38;5;110"

# the focused window or workspace; outputs; an urgent one
FZX_COLORS[i3_focused]="38;5;114"
FZX_COLORS[i3_dim]="38;5;244"
FZX_COLORS[i3_urgent]="38;5;203"

# windows open and close under the list: read the tree on every load
FZX_PERSIST=none

# short details: below until 150, then on the right
FZX_PREVIEW_LAYOUTS=("0:down,40%,border-top" "150:right,40%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
