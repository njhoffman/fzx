#!/usr/bin/env bash
# history defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/history/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
FZX_COLORS[history_icon]="38;5;151"

# zsh-histdb's database
FZX_HISTDB_FILE="${FZX_HISTDB_FILE:-${HISTDB_FILE:-$HOME/.histdb/zsh-history.db}}"

# a command over several lines as an item over several lines (1), or joined by ↵ on one (0); at most
# FZX_HISTORY_MAX_LINES of its lines, then "… +N lines" (the preview always has all of it)
FZX_HISTORY_MULTILINE="${FZX_HISTORY_MULTILINE:-1}"
FZX_HISTORY_MAX_LINES="${FZX_HISTORY_MAX_LINES:-4}"

# the history changes with every command: always read it fresh
FZX_PERSIST=none

# commands whose latest run failed
FZX_COLORS[history_failed]='38;5;203'
# and those that were interrupted rather than failed
FZX_COLORS[history_interrupted]='38;5;179'

# exit statuses that mean the run was interrupted, not that it failed: 130 is ctrl-c (and esc in fzf), 141 a
# closed pipe (cmd | head). Interrupted runs are not red, the failed toggle leaves them out, the succeeded
# toggle keeps them, and the preview's success rate does not count them.
FZX_HISTORY_INTERRUPTED="${FZX_HISTORY_INTERRUPTED-130 141}"

# the command is the whole point: wide list, the run details below it
FZX_PREVIEW_LAYOUTS=("0:down,40%,border-top")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=shell
