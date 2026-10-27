#!/usr/bin/env bash
# files defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/files/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰈢"

# the menu's icons for modes that open different lists
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[dirs]="󰉋"
FZX_ICON_MODES[grep]="󰍉"
# the icon's color in the menu
FZX_COLORS[files_icon]="38;5;75"
FZX_COLORS[files_icon_dirs]="38;5;214"
FZX_COLORS[files_icon_grep]="38;5;170"

FZX_KEYS[files.into]=ctrl-o  # browse the directory under the cursor (a file's own directory)
FZX_KEYS[files.up]=alt-up    # browse the parent directory

# file lists can be large and change rarely within a few minutes: reuse them across runs
FZX_PERSIST=cache:5m

# never listed or searched, whatever the toggles: tool caches that ignore their own contents (their own
# .gitignore holds "*") but would still show up as directories
FZX_FILES_EXCLUDES=(.git .ruff_cache .mypy_cache .pytest_cache __pycache__ .hypothesis .tox)

# image previews through chafa: symbols works everywhere (tmux popups included); sixels or kitty draw real
# pixels where the terminal (and tmux's allow-passthrough) supports them
FZX_FILES_IMAGE_FORMAT=symbols

# the list needs about 50 columns and code about 80: the preview moves to the right from 130 columns
FZX_PREVIEW_LAYOUTS=("0:down,40%,border-top" "130:right,55%")
