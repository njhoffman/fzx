#!/usr/bin/env bash
# kdeconnect defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/kdeconnect/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS FZX_ICON_MODES

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""
FZX_ICON_MODES[notifications]=""
FZX_ICON_MODES[commands]=""
FZX_ICON_MODES[sms]=""

# the icon's color in the menu
FZX_COLORS[kdeconnect_icon]="38;5;73"
FZX_COLORS[kdeconnect_icon_notifications]="38;5;110"
FZX_COLORS[kdeconnect_icon_commands]="38;5;79"
FZX_COLORS[kdeconnect_icon_sms]="38;5;117"

FZX_COLORS[kdeconnect_name]='1;38;5;111'
FZX_COLORS[kdeconnect_connected]='38;5;114'
FZX_COLORS[kdeconnect_away]='38;5;250'
FZX_COLORS[kdeconnect_low]='38;5;203'

# a battery at or below this percent is drawn in kdeconnect_low
FZX_KDECONNECT_BATTERY_LOW="${FZX_KDECONNECT_BATTERY_LOW:-20}"
# seconds to wait for kdeconnect-cli, whose requests go to the device
FZX_KDECONNECT_TIMEOUT="${FZX_KDECONNECT_TIMEOUT:-15}"

# messages shown in a conversation's preview, newest first
FZX_KDECONNECT_SMS_MESSAGES="${FZX_KDECONNECT_SMS_MESSAGES:-30}"
# seconds to wait for the phone: a conversation's messages, or the first sync of the list
FZX_KDECONNECT_SMS_WAIT="${FZX_KDECONNECT_SMS_WAIT:-8}"

# devices come and go, and notifications and messages are private: read on every load, kept nowhere
FZX_PERSIST=none
# nor in the log, where callbacks' arguments would name them
FZX_LOG_ARGS=0

# short details, but a notification's or a message's text is read in the rows too: below until 120; long lines wrap
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top,wrap" "120:right,45%,wrap")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
