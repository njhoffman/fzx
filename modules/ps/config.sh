#!/usr/bin/env bash
# ps defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/ps/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
FZX_COLORS[ps_icon]="38;5;167"

FZX_KEYS[ps.children]=ctrl-o # open the children of the process under the cursor
FZX_KEYS[ps.files]=alt-O     # the open files of the process under the cursor (the network module's files)

# seconds between refreshes in top mode (fractions work: 0.5)
FZX_PS_TOP_INTERVAL=2

# command lines are what the list is read for and the details are short: the preview stays below (the
# list keeps the whole width) until 220 columns
FZX_PREVIEW_LAYOUTS=("0:down,40%,border-top" "220:right,35%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
