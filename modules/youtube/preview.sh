#!/usr/bin/env bash
# youtube preview: a video's thumbnail, then its title, channel, duration, views and description from the
# search row, or for a recent search what enter does and its cached results; formats mode: the thumbnail,
# the title and the format's details.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# youtube::thumb_rows <text lines>: the rows the thumbnail gets above that much text: FZX_YOUTUBE_THUMB_ROWS,
# at most half the preview, at least what the text leaves (0 when that is too little)
youtube::thumb_rows() {
  local lines="${FZF_PREVIEW_LINES:-40}" max="${FZX_YOUTUBE_THUMB_ROWS:-10}" left
  left=$((lines - $1 - 1))
  ((left > max)) && left="$max"
  ((left > lines / 2)) && left=$((lines / 2))
  ((left < 4)) && left=0
  printf '%d' "$left"
}

# youtube::thumb <url> <rows>: the video's thumbnail (i.ytimg.com's mqdefault, fetched once into
# $FZX_CACHE_DIR/youtube/thumbs) drawn with chafa in <rows> rows; nothing without chafa or curl, when the
# fetch fails (not cached: the network may come back) or with FZX_YOUTUBE_THUMBS=0
youtube::thumb() {
  local url="$1" rows="$2" id img cols="${FZF_PREVIEW_COLUMNS:-80}" w
  [[ "${FZX_YOUTUBE_THUMBS:-1}" == 1 ]] && ((rows >= 4)) || return 0
  command -v chafa > /dev/null && command -v curl > /dev/null || return 0
  youtube::video_id "$url" id || return 0
  img="${FZX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fzx}/youtube/thumbs/$id.jpg"
  if [[ ! -s "$img" ]]; then
    mkdir -p -- "${img%/*}" || return 0
    if ! command curl -fsSL --max-time "${FZX_YOUTUBE_THUMB_TIMEOUT:-3}" -o "$img.$BASHPID" \
      "https://i.ytimg.com/vi/$id/mqdefault.jpg" 2> /dev/null || [[ ! -s "$img.$BASHPID" ]]; then
      rm -f -- "$img.$BASHPID"
      return 0
    fi
    mv -f -- "$img.$BASHPID" "$img"
  fi
  # 16:9 in cells about twice as tall as wide: 32 columns per 9 rows
  w=$((rows * 32 / 9))
  ((w > cols)) && w="$cols"
  command chafa --format="${FZX_PREVIEW_IMAGE_FORMAT:-symbols}" --size="${w}x$rows" --animate=off -- "$img" 2> /dev/null
  printf '\n'
}

# youtube::preview <url|search|error> <title|query|message> [channel duration views description]
youtube::preview() {
  local kind="${1:-}" text="${2:-}" dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" bold=$'\e[1m' rst=$'\e[0m'
  local width="${FZF_PREVIEW_COLUMNS:-80}" file
  case "$kind" in
    search)
      printf '%senter%s searches again for %s%s%s\n' "$bold" "$rst" "$bold" "$text" "$rst"
      youtube::search_file "$text" file
      [[ -f "$file" ]] || return 0
      printf '\n%scached results:%s\n' "$dim" "$rst"
      cut -f2 -- "$file"
      ;;
    error) printf '%s\n' "$text" ;;
    http*)
      if [[ "${FZX_MODE:-}" == formats ]]; then
        # url  format_id  title  kind  size  details
        youtube::thumb "$kind" "$(youtube::thumb_rows 8)"
        printf '%s%s%s\n\n' "$bold" "$3" "$rst"
        printf '%s\n' "${6//; /$'\n'}"
        return 0
      fi
      youtube::thumb "$kind" "$(youtube::thumb_rows $((8 + ${#6} / (width > 0 ? width : 80))))"
      printf '%s%s%s\n\n' "$bold" "$text" "$rst"
      [[ -n "${3:-}" ]] && printf '%schannel%s   %s\n' "$dim" "$rst" "$3"
      printf '%sduration%s  %s\n' "$dim" "$rst" "${4:-live}"
      [[ "${5:-}" =~ ^[0-9]+$ ]] && printf "%sviews%s     %'d\n" "$dim" "$rst" "$5"
      printf '%surl%s       %s\n' "$dim" "$rst" "$kind"
      [[ -n "${6:-}" ]] && printf '\n%s\n' "$6" | fold -s -w "$width"
      ;;
    *) return 0 ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && youtube::preview "$@"
