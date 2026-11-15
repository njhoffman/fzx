#!/usr/bin/env bash
# workspaces defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/workspaces/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=$'\U000f056e'
FZX_COLORS[workspaces_icon]="38;5;111"

# each type's icon (Nerd Font, as escapes; FZX_ICONS other than nerd shows none) and color: claude, git, generic
# (layouts/NN-TYPE.sh), session (made by hand) and predefined (layouts/NAME.sh, and any other type)
declare -gA FZX_WORKSPACES_ICONS
FZX_WORKSPACES_ICONS[claude]=$'\U000f06a9'
FZX_WORKSPACES_ICONS[git]=$'\ue702'
FZX_WORKSPACES_ICONS[generic]=$'\uf07b'
FZX_WORKSPACES_ICONS[session]=$'\uf120'
FZX_WORKSPACES_ICONS[predefined]=$'\uf013'
FZX_COLORS[workspaces_claude]="38;5;180"
FZX_COLORS[workspaces_git]="38;5;173"
FZX_COLORS[workspaces_generic]="38;5;110"
FZX_COLORS[workspaces_session]="38;5;245"
FZX_COLORS[workspaces_predefined]="38;5;176"
# the open mark
FZX_COLORS[workspaces_open]="38;5;114"

# sessions open and close under you; `workspace list` is quick: read it on every load
FZX_PERSIST=none

# short details: a right preview early
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "110:right,50%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=terminal
