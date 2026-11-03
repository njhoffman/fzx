#!/usr/bin/env bash
# glyphs defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/glyphs/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰛖"

# the menu's icons for modes that open different lists
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[unicode]="󰻐"
FZX_ICON_MODES[emoji]="󰞅"
# the icon's color in the menu
FZX_COLORS[glyphs_icon]="38;5;180"
FZX_COLORS[glyphs_icon_unicode]="38;5;152"
FZX_COLORS[glyphs_icon_emoji]="38;5;223"

FZX_KEYS[glyphs.into]=ctrl-o # blocks: open the block; unicode: open the character's block

# where the Unicode data is (UnicodeData.txt, Blocks.txt, emoji/emoji-test.txt; the unicode-data package)
FZX_GLYPHS_UNICODE_DIR="${FZX_GLYPHS_UNICODE_DIR:-/usr/share/unicode}"
# what the update action downloads (into $FZX_CACHE_DIR/glyphs, used instead of the module's own copy)
FZX_GLYPHS_NERD_URL="${FZX_GLYPHS_NERD_URL:-https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json}"

# the lists are built once into $FZX_CACHE_DIR/glyphs by the module itself
FZX_PERSIST=session

# the glyph, its codes and a grid of its neighbours: narrow, to the right from 100 columns
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top" "100:right,45%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=terminal

# --freeze-left (config/defaults.sh): the glyph and its name stay
FZX_FREEZE_COL=gap2
