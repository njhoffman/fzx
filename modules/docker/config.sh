#!/usr/bin/env bash
# docker defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/docker/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# containers change state under you: read docker on every open
FZX_PERSIST=none

# log lines shown in the container preview and before following
FZX_DOCKER_LOG_LINES=40
# shells tried by exec, in order
FZX_DOCKER_SHELLS=(zsh bash ash sh)

FZX_COLORS[docker_name]='1;38;5;111'
FZX_COLORS[docker_running]='38;5;114'
FZX_COLORS[docker_paused]='38;5;222'
FZX_COLORS[docker_stopped]='38;5;203'
