#!/usr/bin/env bash
# kdeconnect defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/kdeconnect/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS FZX_ICON_MODES

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""
FZX_ICON_MODES[notifications]=""
FZX_ICON_MODES[commands]=""

# the icon's color in the menu
FZX_COLORS[kdeconnect_icon]="38;5;73"
FZX_COLORS[kdeconnect_icon_notifications]="38;5;110"
FZX_COLORS[kdeconnect_icon_commands]="38;5;79"

FZX_COLORS[kdeconnect_name]='1;38;5;111'
FZX_COLORS[kdeconnect_connected]='38;5;114'
FZX_COLORS[kdeconnect_away]='38;5;250'
FZX_COLORS[kdeconnect_low]='38;5;203'

# a battery at or below this percent is drawn in kdeconnect_low
FZX_KDECONNECT_BATTERY_LOW="${FZX_KDECONNECT_BATTERY_LOW:-20}"
# seconds to wait for kdeconnect-cli, whose requests go to the device
FZX_KDECONNECT_TIMEOUT="${FZX_KDECONNECT_TIMEOUT:-15}"

# devices come and go, and notifications are private: read on every load, kept nowhere
FZX_PERSIST=none

# short details, but a notification's text is read in the rows too: below until 120
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top" "120:right,45%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
