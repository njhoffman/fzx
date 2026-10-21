#!/usr/bin/env bash
# files defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/files/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

FZX_KEYS[files.into]=ctrl-o  # browse the directory under the cursor (a file's own directory)
FZX_KEYS[files.up]=alt-up    # browse the parent directory

# file lists can be large and change rarely within a few minutes: reuse them across runs
FZX_PERSIST=cache:5m
