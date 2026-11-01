#!/usr/bin/env bash
# menu defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/menu/config.sh

# shellcheck disable=SC2034  # read by lib/
# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the entry's preview under the list until the terminal is wide enough to put it beside
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "180:right,40%")

# groups mode: the most used entries shown first under "recent" (0: none), and the order of the groups
# below it (a module's FZX_MENU_GROUP; groups not listed follow by name)
FZX_MENU_RECENT=5
FZX_MENU_GROUPS=(files shell development system terminal other)
# how use is weighed: a use counts half after FZX_MENU_HALF_LIFE_DAYS, nothing after FZX_MENU_STATS_DAYS
FZX_MENU_HALF_LIFE_DAYS=7
FZX_MENU_STATS_DAYS=90
