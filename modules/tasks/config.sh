#!/usr/bin/env bash
# tasks defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/tasks/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
FZX_COLORS[tasks_icon]="38;5;179"

FZX_COLORS[tasks_project]='38;5;111'
FZX_COLORS[tasks_name]='1;38;5;255'
FZX_COLORS[tasks_mark]='38;5;114'

# directories searched for repositories besides ghq's (FZX_TASKS_DEPTH levels deep)
FZX_TASKS_ROOTS=()
FZX_TASKS_DEPTH=3
# the scan of every repository is kept in $FZX_CACHE_DIR/tasks/index for this long (90, 90s, 5m, 2h, 1d;
# alt-s scans again), FZX_TASKS_JOBS repositories at a time; the repository you are in is read every time
FZX_TASKS_TTL="${FZX_TASKS_TTL:-1h}"
FZX_TASKS_JOBS=8

# built from the scan cache and the current repository on every open
FZX_PERSIST=none
