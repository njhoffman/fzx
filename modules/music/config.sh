#!/usr/bin/env bash
# music defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/music/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰝚"

# the menu's icons for modes that open different lists
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[artists]="󰠃"
FZX_ICON_MODES[albums]="󰀥"
FZX_ICON_MODES[playlists]="󰲸"
# the icon's color in the menu
FZX_COLORS[music_icon]="38;5;141"
FZX_COLORS[music_icon_artists]="38;5;180"
FZX_COLORS[music_icon_albums]="38;5;111"
FZX_COLORS[music_icon_playlists]="38;5;114"

# rows: artists, albums, years, the song playing; the preview's rating
FZX_COLORS[music_artist]="38;5;180"
FZX_COLORS[music_album]="38;5;111"
FZX_COLORS[music_year]="38;5;244"
FZX_COLORS[music_current]="1;38;5;114"
FZX_COLORS[music_rating]="38;5;179"

# musicman (github.com/njhoffman/musicman) adds its library tags to a song's preview: auto (when it is
# installed) or off. Its answers are cached per file until the file changes
FZX_MUSIC_MUSICMAN="${FZX_MUSIC_MUSICMAN:-auto}"
# the musicman fields shown, in this order
FZX_MUSIC_TAGS=(rating grouping context mood picks type)
# MPD's music_directory, for musicman's paths; empty: read from ~/.config/mpd/mpd.conf or ~/.mpdconf
FZX_MUSIC_DIR="${FZX_MUSIC_DIR:-}"
# the cover's height in the preview, in rows at most (it also keeps to half the preview's width)
FZX_MUSIC_COVER_ROWS="${FZX_MUSIC_COVER_ROWS:-14}"

# the queue and the player change under you: read the lists again on every load (all are quick)
FZX_PERSIST=none

# short rows and a cover: a preview on the right early
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "100:right,45%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=other
