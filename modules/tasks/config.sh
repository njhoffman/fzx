#!/usr/bin/env bash
# tasks defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/tasks/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the menu's icons for modes that open different lists
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[repos]="󰳐"
FZX_ICON_MODES[all]="󰝖"
# the icons' colors in the menu
FZX_COLORS[tasks_icon]="38;5;80"
FZX_COLORS[tasks_icon_repos]="38;5;111"
FZX_COLORS[tasks_icon_all]="38;5;141"

FZX_COLORS[tasks_project]='38;5;111'
FZX_COLORS[tasks_name]='1;38;5;255'
FZX_COLORS[tasks_mark]='38;5;114'
# each runner's icon (Nerd Font icons only; with FZX_ICONS=unicode or none the rows show the runner's name)
FZX_COLORS[tasks_kind_make]='38;5;108'
FZX_COLORS[tasks_kind_just]='38;5;180'
FZX_COLORS[tasks_kind_npm]='38;5;167'
FZX_COLORS[tasks_kind_task]='38;5;80'
FZX_COLORS[tasks_kind_cargo]='38;5;208'
FZX_COLORS[tasks_kind_pdm]='38;5;159'
FZX_COLORS[tasks_kind_poe]='38;5;159'
FZX_COLORS[tasks_kind_hatch]='38;5;159'

# directories searched for repositories besides ghq's (FZX_TASKS_DEPTH levels deep)
FZX_TASKS_ROOTS=()
FZX_TASKS_DEPTH=3
# the scan of every repository is kept in $FZX_CACHE_DIR/tasks/index for this long (90, 90s, 5m, 2h, 1d;
# alt-s scans again), FZX_TASKS_JOBS repositories at a time; the repository you are in is read every time
FZX_TASKS_TTL="${FZX_TASKS_TTL:-1h}"
FZX_TASKS_JOBS=8

# built from the scan cache and the current repository on every open
FZX_PERSIST=none

# rows (task and command) want about 70 columns, definitions are short: right from 140
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top" "140:right,50%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=development
