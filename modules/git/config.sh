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

# git color settings applied to every git call here (`-c KEY=VALUE`), over the user's: git's defaults
# draw tags, commit hashes and the decoration parentheses in yellow; cool colors instead
FZX_GIT_COLOR_CONFIG=("color.decorate.tag=bold 117" "color.diff.commit=252")
