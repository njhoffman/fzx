#!/usr/bin/env bash
# bluetooth defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/bluetooth/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰂯"
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[all]="󰂰"
# the icon's color in the menu
FZX_COLORS[bluetooth_icon]="38;5;75"
FZX_COLORS[bluetooth_icon_all]="38;5;110"

# a connected device and a powered controller; a blocked device, a powered-off controller and a low battery
FZX_COLORS[bluetooth_connected]="38;5;114"
FZX_COLORS[bluetooth_off]="38;5;203"

# how long the scan action looks for devices (seconds)
FZX_BLUETOOTH_SCAN_SECONDS="${FZX_BLUETOOTH_SCAN_SECONDS:-5}"
# a battery at or below this percent is drawn in bluetooth_off (preview)
FZX_BLUETOOTH_BATTERY_LOW="${FZX_BLUETOOTH_BATTERY_LOW:-20}"

# devices connect and disconnect under you: read them again on every load (one D-Bus call)
FZX_PERSIST=none

# short details, but the rows are read whole (the address tells devices of one name apart): below until 150
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top" "150:right,40%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
