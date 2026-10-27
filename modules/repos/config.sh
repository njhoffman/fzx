#!/usr/bin/env bash
# repos defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/repos/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
FZX_COLORS[repos_icon]="38;5;141"

FZX_KEYS[repos.git]=ctrl-o   # the git module on the repository
FZX_KEYS[repos.files]=alt-o  # the files module on the repository

# owners for the mine mode (the directory above the repository under ghq); empty: git's github.user, else
# ghq.user, else the user gh is logged in as (~/.config/gh/hosts.yml), else the login name
FZX_REPOS_OWNERS=()
# directories searched for repositories besides ghq's (FZX_REPOS_DEPTH levels deep); links into ghq collapse
FZX_REPOS_ROOTS=()
FZX_REPOS_DEPTH=3
# the background scan: at most once per FZX_REPOS_TTL seconds, FZX_REPOS_JOBS repositories at a time, each
# git status given FZX_REPOS_TIMEOUT seconds (a huge checkout shows blank state rather than holding it up)
FZX_REPOS_TTL=120
FZX_REPOS_JOBS=8
FZX_REPOS_TIMEOUT=10

# the list is built from the scan cache on every open; the scan keeps it current
FZX_PERSIST=none

FZX_COLORS[repos_name]='1;38;5;111'
FZX_COLORS[repos_branch]='38;5;81'
FZX_COLORS[repos_changed]='38;5;255'
FZX_COLORS[repos_ahead]='38;5;114'
FZX_COLORS[repos_behind]='38;5;203'
FZX_COLORS[repos_todo]='38;5;117'

# long rows (name, branch, state): the preview goes below until the terminal is wide
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "160:right,45%")
