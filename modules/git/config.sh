#!/usr/bin/env bash
# git defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/git/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

FZX_KEYS[git.into]=ctrl-o   # branches, tags: the log; log, reflog, stash: the commit's files; worktrees: status
FZX_KEYS[git.view]=alt-v    # status, commit: the preview shows the diff or the blame

# commits listed in log mode
FZX_GIT_LOG_LIMIT=1000

# diffs in the preview are piped through this command: "auto" is delta when it is installed (at the
# preview's width), "" none, anything else a command line, e.g. "diff-so-fancy"
FZX_GIT_DIFF_FILTER="${FZX_GIT_DIFF_FILTER-auto}"

# the destructive verbs (drop, fixup, squash, reword, rebase; components.tsv) are bound only when 1, and ask
# first even then; amend of a pushed commit is allowed too. Exported: the components table is a script
export FZX_GIT_DESTRUCTIVE="${FZX_GIT_DESTRUCTIVE:-0}"

# git color settings applied to every git call here (`-c KEY=VALUE`), over the user's: git's defaults
# draw tags, commit hashes and the decoration parentheses in yellow; cool colors instead
FZX_GIT_COLOR_CONFIG=("color.decorate.tag=bold 117" "color.diff.commit=252")
