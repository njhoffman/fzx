#!/usr/bin/env bash
# snippets defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/snippets/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰅌"
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[history]="󰋚"
# the icon's color in the menu
FZX_COLORS[snippets_icon]="38;5;180"
FZX_COLORS[snippets_icon_history]="38;5;144"

# snippet names; ages, sources and labels
FZX_COLORS[snippets_name]="38;5;117"
FZX_COLORS[snippets_dim]="38;5;244"

# the paste history (lib/snippets.sh): how many pastes it keeps; FZX_SNIPPETS_HISTORY=0 records none (set it
# in ~/.config/fzx/config.sh: the capture and tmux modules record)
FZX_SNIPPETS_HISTORY_MAX="${FZX_SNIPPETS_HISTORY_MAX:-200}"

# the files change under the list (pastes, edits): read them on every load
FZX_PERSIST=none

# the text is what is read: below until 150, then on the right
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "150:right,50%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=shell
