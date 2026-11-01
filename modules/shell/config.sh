#!/usr/bin/env bash
# shell defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/shell/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the menu's icons for modes that open different lists
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[aliases]="󰌹"
FZX_ICON_MODES[functions]="󰊕"
FZX_ICON_MODES[params]="󰫧"
# the icons' colors in the menu
FZX_COLORS[shell_icon]="38;5;114"
FZX_COLORS[shell_icon_aliases]="38;5;180"
FZX_COLORS[shell_icon_functions]="38;5;117"
FZX_COLORS[shell_icon_params]="38;5;75"

# the shell changes: read it on every open
FZX_PERSIST=none

# the zsh dump (shell/fzx.zsh writes it at the first prompt; its shell widget before opening the module) is
# used while younger than this many seconds; older or missing, an interactive `zsh -ic` dumps the shell
FZX_SHELL_DUMP_TTL="${FZX_SHELL_DUMP_TTL:-86400}"
# parameters whose upper-cased names match this extended regular expression have their values masked (the
# reveal toggle shows exported ones). The zsh side reads FZX_SHELL_SECRETS from its own environment, with
# the same default: set it there too (zshrc) when you change it
FZX_SHELL_SECRETS="${FZX_SHELL_SECRETS:-TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|APIKEY|_KEY\$|PASS\$}"

FZX_COLORS[shell_name]='1;38;5;117'
FZX_COLORS[shell_kind]='38;5;180'
FZX_COLORS[shell_value]='38;5;250'
FZX_COLORS[shell_export]='1;38;5;75'
FZX_COLORS[shell_masked]='38;5;203'

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=shell
