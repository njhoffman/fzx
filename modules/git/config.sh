#!/usr/bin/env bash
# git defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/git/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

FZX_KEYS[git.stage]=alt-s   # status: git add the selected files
FZX_KEYS[git.unstage]=alt-u # status: git restore --staged the selected files
FZX_KEYS[git.switch]=alt-c  # branches: git switch (remote branches: --track)
FZX_KEYS[git.edit]=ctrl-e   # status: open the selected files in $EDITOR
FZX_KEYS[git.into]=ctrl-o   # branches: open the branch's log

# commits listed in log mode
FZX_GIT_LOG_LIMIT=1000

# diffs in the preview are piped through this when set, e.g. "delta --paging=never"
FZX_GIT_DIFF_FILTER=""
