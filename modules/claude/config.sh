#!/usr/bin/env bash
# claude defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/claude/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font: robot); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰚩"

# the icon's color in the menu
FZX_COLORS[claude_icon]="38;5;173"

FZX_KEYS[claude.git]=alt-l   # the git module on the project
FZX_KEYS[claude.files]=alt-d # the files module on the project

# the command the claude and resume actions run (resume adds --continue)
FZX_CLAUDE_CMD=claude
# the background scan (claude-projects --tsv, a few seconds): at most once per FZX_CLAUDE_TTL seconds
FZX_CLAUDE_TTL=120
# the active mode: projects with a session in this many days (or uncommitted or unpushed work)
FZX_CLAUDE_ACTIVE_DAYS=7

# the list is built from the scan cache on every open (ages stay current); the scan keeps it current
FZX_PERSIST=none

FZX_COLORS[claude_name]='1;38;5;111'
FZX_COLORS[claude_mode_git]='38;5;110'
FZX_COLORS[claude_mode_dotbare]='38;5;140'
FZX_COLORS[claude_mode_plain]='38;5;180'
FZX_COLORS[claude_branch]='38;5;81'
FZX_COLORS[claude_changed]='38;5;255'
FZX_COLORS[claude_ahead]='38;5;114'
FZX_COLORS[claude_behind]='38;5;203'
FZX_COLORS[claude_todo]='38;5;117'
FZX_COLORS[claude_p1]='38;5;203'

# rows run to ~100 columns: the preview goes below until the terminal is wide
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "170:right,45%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=development
