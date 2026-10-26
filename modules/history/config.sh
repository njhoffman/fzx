#!/usr/bin/env bash
# history defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/history/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# zsh-histdb's database
FZX_HISTDB_FILE="${FZX_HISTDB_FILE:-${HISTDB_FILE:-$HOME/.histdb/zsh-history.db}}"

# the history changes with every command: always read it fresh
FZX_PERSIST=none

# commands whose latest run failed
FZX_COLORS[history_failed]='38;5;203'

# the command is the whole point: wide list, the run details below it
FZX_PREVIEW_LAYOUTS=("0:down,40%,border-top")
