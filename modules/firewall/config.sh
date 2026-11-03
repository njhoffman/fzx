#!/usr/bin/env bash
# firewall defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/firewall/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󱨑"
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[apps]="󰞀"
# the icon's color in the menu
FZX_COLORS[firewall_icon]="38;5;209"
FZX_COLORS[firewall_icon_apps]="38;5;180"

# rule actions: allow, deny and reject, limit
FZX_COLORS[firewall_allow]="38;5;114"
FZX_COLORS[firewall_deny]="38;5;203"
FZX_COLORS[firewall_limit]="38;5;180"

# ufw's files read without root: its config (on or off) and the application profiles
FZX_FIREWALL_CONF="${FZX_FIREWALL_CONF:-/etc/ufw/ufw.conf}"
FZX_FIREWALL_APPS_DIR="${FZX_FIREWALL_APPS_DIR:-/etc/ufw/applications.d}"

# rules change with the actions and sudo comes and goes: read again on every load
FZX_PERSIST=none

# short rows and details: a right preview early
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top" "130:right,40%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
