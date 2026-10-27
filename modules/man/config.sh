#!/usr/bin/env bash
# man defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/man/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰈙"

# the icon's color in the menu
FZX_COLORS[man_icon]="38;5;109"

# the man database and tldr pages change rarely: lists are cached for a day (ctrl-r reads them again)
FZX_PERSIST=cache:1d

# sections listed in commands mode: a page is listed when its section starts with one of these
# (1 also takes 1p, 1ssl and the like)
FZX_MAN_SECTIONS=(1 8)

# tldr platforms listed after common, and tealdeer's pages directory ("" asks tealdeer)
FZX_MAN_TLDR_PLATFORMS=(linux)
FZX_MAN_TLDR_PAGES="${FZX_MAN_TLDR_PAGES-}"

FZX_COLORS[man_name]='1;38;5;117'
FZX_COLORS[man_section]='38;5;244'
