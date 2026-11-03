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

# the all mode also reads the TODO.md files the dotbare repository tracks (~/.config/tmux/TODO.md ...):
# its git directory ("" leaves them out; default $DOTBARE_DIR, else ~/.cfg) and work tree ($DOTBARE_TREE,
# else ~)
FZX_TODOS_DOTBARE_DIR="${FZX_TODOS_DOTBARE_DIR-${DOTBARE_DIR:-$HOME/.cfg}}"
FZX_TODOS_DOTBARE_TREE="${FZX_TODOS_DOTBARE_TREE:-${DOTBARE_TREE:-$HOME}}"
# and the top-level TODO.md of git repositories directly under ~ (~/.shell); 0 leaves them out
FZX_TODOS_HOME_REPOS="${FZX_TODOS_HOME_REPOS:-1}"

# the files change under you (Claude Code, other editors): read them on every open
FZX_PERSIST=none

# the item's card under the list, as todo-fzf has it
FZX_PREVIEW_LAYOUTS=("0:down,40%,border-top")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=development

# sorts without a column to mark: no header row under FZX_SORTED_SHOW=header or both
FZX_SORTED_COLUMNS=0
