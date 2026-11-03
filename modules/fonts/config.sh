#!/usr/bin/env bash
# fonts defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/fonts/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""
# the icon's color in the menu
FZX_COLORS[fonts_icon]="38;5;180"
# the monospace marker in the list
FZX_COLORS[fonts_mono]="38;5;114"

# the sample the preview draws in the font (rendered by ImageMagick, drawn by chafa, cached per font file):
# its text (lines split on \n), colors (#rrggbb or a name; background "none" is transparent), size in
# points, and the rows it takes at most (0: no sample)
FZX_FONTS_SAMPLE="${FZX_FONTS_SAMPLE:-The quick brown fox jumps\nover the lazy dog 0123456789\n{}[]()<>=+-*/ !?&@#\$%}"
FZX_FONTS_SAMPLE_FG="${FZX_FONTS_SAMPLE_FG:-#d0d0d0}"
FZX_FONTS_SAMPLE_BG="${FZX_FONTS_SAMPLE_BG:-none}"
FZX_FONTS_SAMPLE_POINTS="${FZX_FONTS_SAMPLE_POINTS:-48}"
FZX_FONTS_SAMPLE_ROWS="${FZX_FONTS_SAMPLE_ROWS:-10}"

# fontconfig's list changes with installs only: kept for the session, ctrl-r reads it again
FZX_PERSIST=session

# the sample wants width: below until 140, then a wide right preview
FZX_PREVIEW_LAYOUTS=("0:down,55%,border-top" "140:right,55%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
