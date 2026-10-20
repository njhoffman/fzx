#!/usr/bin/env bash
# dirs defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/dirs/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

FZX_KEYS[dirs.files]=ctrl-o  # browse the directory in the files module

# named directories for the bookmarks mode (name -> path); the mode is offered when this is not empty
declare -gA FZX_DIRS_BOOKMARKS=()
