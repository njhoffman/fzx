#!/usr/bin/env bash
# audio defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/audio/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰕾"

# the menu's icons for modes that open different lists
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[sources]="󰍬"
FZX_ICON_MODES[streams]="󰎈"
FZX_ICON_MODES[players]="󰐊"
# the icon's color in the menu
FZX_COLORS[audio_icon]="38;5;114"
FZX_COLORS[audio_icon_sources]="38;5;180"
FZX_COLORS[audio_icon_streams]="38;5;75"
FZX_COLORS[audio_icon_players]="38;5;141"

# the default device (and a playing player), a muted one, a stream's application
FZX_COLORS[audio_default]="1;38;5;114"
FZX_COLORS[audio_muted]="38;5;203"
FZX_COLORS[audio_app]="1;38;5;180"

# volume steps (percent) and the most alt-up goes to
FZX_AUDIO_STEP="${FZX_AUDIO_STEP:-5}"
FZX_AUDIO_MAX="${FZX_AUDIO_MAX:-100}"

# devices and streams change under you: read them again on every load
FZX_PERSIST=none

# short metadata: a narrow preview to the right early
FZX_PREVIEW_LAYOUTS=("0:down,40%,border-top" "100:right,40%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
