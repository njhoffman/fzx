#!/usr/bin/env bash
# recent defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/recent/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

FZX_KEYS[recent.dir]=ctrl-o # browse the file's directory in the files module

# telescope-frecency's database (nvim), for the nvim mode (the default when it exists)
FZX_RECENT_NVIM_DB="${FZX_RECENT_NVIM_DB:-$HOME/.local/share/nvim/file_frecency.sqlite3}"

# `fzx jump --files` (v): the mode it matches with ("" = the default mode), and how many matches it opens
# at once before it asks with a picker instead
FZX_RECENT_JUMP_MODE=""
FZX_RECENT_JUMP_MAX=10
