#!/usr/bin/env bash
# menu defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/menu/config.sh

# shellcheck disable=SC2034  # read by lib/
# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the entry's preview under the list until the terminal is wide enough to put it beside
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "180:right,40%")
