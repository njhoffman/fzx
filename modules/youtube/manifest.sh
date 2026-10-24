#!/usr/bin/env bash
# youtube menu entries

youtube::manifest() {
  fzx::entry youtube "Search YouTube; play, open or save as mp3"
}

youtube::applicable() {
  command -v yt-dlp > /dev/null && command -v jq > /dev/null
}

youtube::summary() {
  local file="$FZX_STATE_DIR/youtube/history" n
  [[ -f "$file" ]] || return 0
  n="$(wc -l < "$file")"
  printf '%s recent searches\n' "${n// /}"
}
