#!/usr/bin/env bash
# systemd defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/systemd/config.sh
# Actions on system units run through sudo when fzx is not root (in the foreground, so it can prompt).

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
FZX_COLORS[systemd_icon]="38;5;66"


# unit rows and systemctl status lines are long: the preview stays below until 190 columns (a 200-column terminal)
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "190:right,50%")
# wide content: a larger popup than the default
FZX_POPUP_LAYOUTS=("0:center,100%" "140:center,95%,90%" "220:center,90%,85%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system

# --freeze-left (config/defaults.sh): timers, sockets: the manager and the unit stay
declare -gA FZX_FREEZE_COLS
FZX_FREEZE_COLS[timers]=gap2
FZX_FREEZE_COLS[sockets]=gap2
