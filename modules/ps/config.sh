#!/usr/bin/env bash
# ps defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/ps/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
FZX_COLORS[ps_icon]="38;5;167"

FZX_KEYS[ps.children]=ctrl-o # open the children of the process under the cursor
FZX_KEYS[ps.files]=alt-o     # the open files of the process under the cursor (the network module's files)

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
