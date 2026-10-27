#!/usr/bin/env bash
# youtube defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/youtube/config.sh
# shellcheck disable=SC2034  # settings here are read by lib/ and the module

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
declare -gA FZX_COLORS
FZX_COLORS[youtube_icon]="38;5;196"

# results per search (yt-dlp "ytsearchN:")
FZX_YOUTUBE_RESULTS="${FZX_YOUTUBE_RESULTS:-30}"
# a search is served from $FZX_CACHE_DIR/youtube/search for this long (90, 90s, 5m, 2h, 1d)
FZX_YOUTUBE_CACHE_TTL="${FZX_YOUTUBE_CACHE_TTL:-1h}"
# recent searches kept in $FZX_STATE_DIR/youtube/history (the list shown before a search)
FZX_YOUTUBE_HISTORY_MAX="${FZX_YOUTUBE_HISTORY_MAX:-200}"
# the play action's command (detached); the audio action adds --no-video and runs in the terminal
FZX_YOUTUBE_PLAYER=(mpv)
# where the mp3 action saves (yt-dlp -x --audio-format mp3, which needs ffmpeg); empty: the XDG music
# directory, else ~/Music. Then its extra yt-dlp args
FZX_YOUTUBE_AUDIO_DIR="${FZX_YOUTUBE_AUDIO_DIR:-}"
FZX_YOUTUBE_MP3_ARGS=(--audio-quality 0 --embed-metadata)
