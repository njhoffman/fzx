#!/usr/bin/env bash
# git defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/git/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

FZX_KEYS[git.into]=ctrl-o   # branches: open the branch's log

# commits listed in log mode
FZX_GIT_LOG_LIMIT=1000

# diffs in the preview are piped through this when set, e.g. "delta --paging=never"
FZX_GIT_DIFF_FILTER=""
