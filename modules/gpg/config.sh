#!/usr/bin/env bash
# gpg defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/gpg/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰯄"
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[secret]="󰌆"
# the icon's color in the menu
FZX_COLORS[gpg_icon]="38;5;179"
FZX_COLORS[gpg_icon_secret]="38;5;173"

# a key you trust (ultimate or full) and the secret mark; expired, revoked or disabled keys
FZX_COLORS[gpg_trusted]="38;5;114"
FZX_COLORS[gpg_dim]="38;5;244"

# the key's listing reads wide: below until 160, then on the right
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "160:right,50%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
