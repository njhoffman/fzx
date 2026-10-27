#!/usr/bin/env bash
# dirs defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/dirs/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

FZX_KEYS[dirs.files]=ctrl-o  # browse the directory in the files module

# named directories for the bookmarks mode (name -> path); the mode is offered when this is not empty
declare -gA FZX_DIRS_BOOKMARKS=()

# the all mode, every directory under ~ (what g falls back to): how deep fd goes and what it skips.
# Unlimited, ~ can hold hundreds of thousands of directories and take most of a minute to walk.
FZX_DIRS_ALL_DEPTH=6
FZX_DIRS_ALL_EXCLUDES=(.git node_modules .cache .npm .cargo/registry .rustup go/pkg .local/share/Trash snap)
