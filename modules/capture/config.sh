#!/usr/bin/env bash
# capture defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/capture/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# capture another pane of the same window: the next and previous one (alt-[ is avoided: it is how
# terminal escape sequences start)
FZX_KEYS[capture.next]="alt-."
FZX_KEYS[capture.prev]="alt-,"

# how many lines of scrollback above the screen to read; "" reads all of it (the pane's history-limit)
FZX_CAPTURE_LINES="${FZX_CAPTURE_LINES-}"

# the pane changes all the time: capture it on every open and reload
FZX_PERSIST=none

# the position column: the visible screen, and lines above or below it
FZX_COLORS[capture_visible]="38;5;81"
FZX_COLORS[capture_offscreen]="38;5;244"

# the context of a hit under the list; to the right on wide terminals
FZX_PREVIEW_LAYOUTS=("0:down,40%,border-top" "150:right,50%")
