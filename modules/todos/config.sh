#!/usr/bin/env bash
# todos defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/todos/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
declare -gA FZX_COLORS
FZX_COLORS[todos_icon]="38;5;114"

# directories searched for TODO.md files in the all mode besides ghq's repositories, and single files
FZX_TODOS_ROOTS=()
FZX_TODOS_FILES=()

# the files change under you (Claude Code, other editors): read them on every open
FZX_PERSIST=none

# the item's card under the list, as todo-fzf has it
FZX_PREVIEW_LAYOUTS=("0:down,40%,border-top")
