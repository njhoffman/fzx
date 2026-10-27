#!/usr/bin/env bash
# network defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/network/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰛳"

# the menu's icons for modes that open different lists
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[wifi]="󰖩"
FZX_ICON_MODES[services]="󰑩"
# the icon's color in the menu
FZX_COLORS[network_icon]="38;5;81"
FZX_COLORS[network_icon_wifi]="38;5;114"

FZX_COLORS[network_name]='1;38;5;255'
FZX_COLORS[network_up]='38;5;114'
FZX_COLORS[network_down]='38;5;203'
FZX_COLORS[network_port]='1;38;5;141'
FZX_COLORS[network_addr]='38;5;152'

FZX_KEYS[network.files]=ctrl-o # ports, connections: the open files of the process

# sockets and links change under you: read them on every open (services keep their own cache, below)
FZX_PERSIST=none

# the mDNS browse (avahi-browse -art, about 5s) is kept in $FZX_CACHE_DIR/network for this long (90, 90s,
# 5m, 2h, 1d); alt-s browses again
FZX_NETWORK_SERVICES_TTL="${FZX_NETWORK_SERVICES_TTL:-10m}"
# how long one browse may take
FZX_NETWORK_SERVICES_TIMEOUT="${FZX_NETWORK_SERVICES_TIMEOUT:-8}"
