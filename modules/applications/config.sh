#!/usr/bin/env bash
# applications defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/applications/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰀻"
# the icon's color in the menu
FZX_COLORS[applications_icon]="38;5;111"
# the main category column
FZX_COLORS[applications_category]="38;5;110"

# where desktop entries are read, highest precedence first (an entry hides those with its ID in later
# directories); empty: $XDG_DATA_HOME and $XDG_DATA_DIRS, each with /applications
FZX_APPLICATIONS_DIRS=()

# the icon theme the preview looks icons up in (then the theme it inherits, then hicolor and pixmaps);
# empty: gtk-icon-theme-name from ~/.config/gtk-3.0/settings.ini, else gsettings' icon-theme
FZX_APPLICATIONS_ICON_THEME="${FZX_APPLICATIONS_ICON_THEME:-}"
# rows the icon takes at the top of the preview (0: no icon; it needs chafa)
FZX_APPLICATIONS_ICON_ROWS="${FZX_APPLICATIONS_ICON_ROWS:-8}"

# entries change with installs only: kept for the session, ctrl-r reads them again
FZX_PERSIST=session

# names and short comments: a right preview early
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top" "120:right,45%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
