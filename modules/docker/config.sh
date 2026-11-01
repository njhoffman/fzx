#!/usr/bin/env bash
# docker defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/docker/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
FZX_COLORS[docker_icon]="38;5;39"

# containers change state under you: read docker on every open
FZX_PERSIST=none

# log lines shown in the container preview and before following
FZX_DOCKER_LOG_LINES=40
# shells tried by exec, in order
FZX_DOCKER_SHELLS=(zsh bash ash sh)

FZX_COLORS[docker_name]='1;38;5;111'
FZX_COLORS[docker_running]='38;5;114'
FZX_COLORS[docker_paused]='38;5;252'
FZX_COLORS[docker_stopped]='38;5;203'

# rows (name, image, status, ports) and the logs in the preview are both long: below until 190 columns (a 200-column terminal)
FZX_PREVIEW_LAYOUTS=("0:down,55%,border-top" "190:right,50%")
# wide content: a larger popup than the default
FZX_POPUP_LAYOUTS=("0:center,100%" "140:center,95%,90%" "220:center,90%,85%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
