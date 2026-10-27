#!/usr/bin/env bash
# github defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/github/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the menu's icons for modes that open different lists
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[starred]=""
FZX_ICON_MODES[code]=""
# the icon's color in the menu
FZX_COLORS[github_icon]="38;5;255"
FZX_COLORS[github_icon_code]="38;5;177"
FZX_COLORS[github_icon_starred]="38;5;220"

FZX_KEYS[github.into]=ctrl-o   # repos, code, mine, starred: browse the repository's files
FZX_KEYS[github.narrow]=alt-p  # code: search only the repository under the cursor; the others: its code
FZX_KEYS[github.filter]=ctrl-t # repos, code: filter the results with fzf instead of searching, and back

# results per search (gh search --limit, at most 100 for code)
FZX_GITHUB_LIMIT="${FZX_GITHUB_LIMIT:-100}"
# a search, your repositories and your stars are served from $FZX_CACHE_DIR/github for this long (90,
# 90s, 5m, 2h, 1d; ctrl-r does not refresh them: star/unstar does, or `fzx gc`); file contents and trees
# are cached by their sha and never expire
FZX_GITHUB_CACHE_TTL="${FZX_GITHUB_CACHE_TTL:-1h}"
# recent searches per mode, kept in $FZX_STATE_DIR/github/history-<mode>
FZX_GITHUB_HISTORY_MAX="${FZX_GITHUB_HISTORY_MAX:-200}"
# clones (alt-c, `clone`, `repos --clone-missing`) over ssh: mine (your own repositories, which you push
# to), always or never
FZX_GITHUB_CLONE_SSH="${FZX_GITHUB_CLONE_SSH:-mine}"
# where fetch (alt-d) writes; empty: the directory fzx was started in
FZX_GITHUB_FETCH_DIR="${FZX_GITHUB_FETCH_DIR:-}"
# files larger than this (bytes) are not previewed
FZX_GITHUB_PREVIEW_MAX="${FZX_GITHUB_PREVIEW_MAX:-1000000}"
# READMEs in the preview: glow when installed (auto), bat, or cat
FZX_GITHUB_MARKDOWN="${FZX_GITHUB_MARKDOWN:-auto}"

FZX_COLORS[github_owner]="38;5;244"
FZX_COLORS[github_name]="1;38;5;75"
FZX_COLORS[github_star]="38;5;220"
FZX_COLORS[github_count]="38;5;250"
FZX_COLORS[github_match]="1;38;5;16;48;5;220"

# searches are cached by the module itself (per query); the session keeps the list across mode switches
FZX_PERSIST=session

# a repository's README and a file's contents need room: the preview to the right from 140 columns
FZX_PREVIEW_LAYOUTS=("0:down,55%,border-top" "140:right,55%")
