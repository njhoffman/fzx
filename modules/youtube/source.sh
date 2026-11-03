#!/usr/bin/env bash
# youtube source. Searches YouTube for $FZF_QUERY (yt-dlp "ytsearchN:"); with an empty query it lists the
# recent searches instead. The search runs on enter (youtube::transform), not as you type.
# Lines are 7 tab-separated fields, the last one displayed:
#   video:  url  title  channel  duration  views  description  display
#   recent: search  query  -  -  -  -  display     (enter searches it again)
#   error:  error  message  -  -  -  -  display    (the search failed)
# Searches are cached per query in $FZX_CACHE_DIR/youtube/search for FZX_YOUTUBE_CACHE_TTL; under fzx the
# query that produced the list is kept in the session's state/youtube_query, which the transform compares
# against.
# Mode formats (hidden, `--url URL`): the video's formats, best first (yt-dlp -J, cached per video in
# $FZX_CACHE_DIR/youtube/formats for FZX_YOUTUBE_CACHE_TTL), 7 fields like the search rows:
#   format: url  format_id  title  kind (video, audio or both)  size (bytes)  details  display

# youtube::trim <text> <var>: without leading and trailing whitespace
youtube::trim() {
  local _t="$1"
  _t="${_t#"${_t%%[![:space:]]*}"}"
  _t="${_t%"${_t##*[![:space:]]}"}"
  printf -v "$2" '%s' "$_t"
}

youtube::history_file() { printf '%s/youtube/history' "$FZX_STATE_DIR"; }

# youtube::history_add <query>: to the top of the recent searches, once, at most FZX_YOUTUBE_HISTORY_MAX
youtube::history_add() {
  local file tmp
  file="$(youtube::history_file)"
  tmp="$file.$BASHPID"
  mkdir -p -- "${file%/*}" || return
  [[ -f "$file" ]] || : > "$file"
  # one awk, no pipe: fzx runs with pipefail, where head closing early or an empty grep would fail it
  # (the query through the environment: awk -v would expand backslash escapes in it)
  Q="$1" awk -v max="${FZX_YOUTUBE_HISTORY_MAX:-200}" 'BEGIN { q = ENVIRON["Q"]; print q; n = 1 } $0 != q && n < max { print; n++ }' \
    "$file" > "$tmp" && mv -f -- "$tmp" "$file"
}

# youtube::search_file <query> <var>: the cache file of a search (results count and query)
youtube::search_file() {
  local _key
  _key="$(printf '%s\n%s' "${FZX_YOUTUBE_RESULTS:-30}" "$1" | md5sum)"
  printf -v "$2" '%s/youtube/search/%s' "$FZX_CACHE_DIR" "${_key%% *}"
}

# youtube::search <query>: "url  title  channel  duration  views  description" rows, from the cache while
# it is fresh, else from yt-dlp (the cache is written only on success)
youtube::search() {
  local file ttl age tmp st
  youtube::search_file "$1" file
  if [[ -f "$file" ]] && fzx::parse_duration "${FZX_YOUTUBE_CACHE_TTL:-1h}" ttl; then
    age=$(($(date +%s) - $(stat -c %Y -- "$file")))
    if ((age < ttl)); then
      cat -- "$file"
      return 0
    fi
  fi
  mkdir -p -- "${file%/*}" || return
  tmp="$file.$BASHPID"
  # flat: the search page only, one request; tabs and newlines in the fields would break the line format
  command yt-dlp --flat-playlist --no-warnings --dump-json -- "ytsearch${FZX_YOUTUBE_RESULTS:-30}:$1" |
    command jq -r '[.url // ("https://www.youtube.com/watch?v=" + .id), .title, .channel // .uploader,
        .duration_string, .view_count, .description]
      | map(. // "" | tostring | gsub("[\t\r\n]+"; " ")) | join("\t")' > "$tmp"
  st=("${PIPESTATUS[@]}")
  if ((st[0] || st[1])); then
    rm -f -- "$tmp"
    return 1
  fi
  mv -f -- "$tmp" "$file"
  cat -- "$file"
}

# youtube::video_id <url> <var>: the 11-character video id of a watch, youtu.be, shorts, live or embed url
youtube::video_id() {
  local _re='(^|[?&/]v[=/]|youtu\.be/|/shorts/|/live/|/embed/)([A-Za-z0-9_-]{11})([?&#/]|$)'
  [[ "$1" =~ $_re ]] || return 1
  printf -v "$2" '%s' "${BASH_REMATCH[2]}"
}

# youtube::fresh <file>: the file exists and is younger than FZX_YOUTUBE_CACHE_TTL
youtube::fresh() {
  local ttl
  [[ -f "$1" ]] && fzx::parse_duration "${FZX_YOUTUBE_CACHE_TTL:-1h}" ttl &&
    (($(date +%s) - $(stat -c %Y -- "$1") < ttl))
}

# youtube::formats <url>: "format_id  title  kind  size  ext  resolution  fps  vcodec  acodec  tbr  note"
# rows, best first; storyboards (neither video nor audio) left out. Cached per video like searches.
youtube::formats() {
  local id file tmp st
  youtube::video_id "$1" id || {
    printf 'youtube: not a video url: %s\n' "$1" >&2
    return 2
  }
  file="$FZX_CACHE_DIR/youtube/formats/$id"
  if youtube::fresh "$file"; then
    cat -- "$file"
    return 0
  fi
  mkdir -p -- "${file%/*}" || return
  tmp="$file.$BASHPID"
  command yt-dlp -J --no-warnings --no-playlist -- "$1" |
    command jq -r '.title as $t | (.formats // []) | reverse[]
      | select((.vcodec // "") != "none" or (.acodec // "") != "none")
      | [.format_id, $t,
          (if .vcodec == "none" then "audio" elif .acodec == "none" then "video" else "both" end),
          (.filesize // .filesize_approx // ""), .ext, .resolution, .fps, .vcodec, .acodec,
          (if .tbr then (.tbr | floor) else "" end), .format_note]
      | map(. // "" | tostring | gsub("[\t\r\n]+"; " ")) | join("\t")' > "$tmp"
  st=("${PIPESTATUS[@]}")
  if ((st[0] || st[1])) || [[ ! -s "$tmp" ]]; then
    rm -f -- "$tmp"
    return 1
  fi
  mv -f -- "$tmp" "$file"
  cat -- "$file"
}

# youtube::format_display <url>: youtube::formats rows -> the mode's 7-field rows (id, ext, resolution,
# fps, kind in color, size, codecs, bitrate and note)
youtube::format_display() {
  local dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m'
  U="$1" awk -F'\t' -v OFS='\t' -v dim="$dim" -v rst="$rst" '
    function human(b) {
      if (b !~ /^[0-9.]+$/) return ""
      if (b >= 1073741824) return sprintf("%.1fG", b / 1073741824)
      if (b >= 1048576) return sprintf("%.0fM", b / 1048576)
      return sprintf("%.0fK", b / 1024)
    }
    BEGIN { url = ENVIRON["U"]; color["both"] = "38;5;114"; color["video"] = "38;5;110"; color["audio"] = "38;5;180" }
    { size = human($4); if ($7 != "") $7 = $7 + 0
      codecs = ($8 != "none" && $8 != "" ? $8 : "") ($9 != "none" && $9 != "" ? ($8 != "none" && $8 != "" ? " + " : "") $9 : "")
      details = "format " $1 "; " $3 "; " $5 (size != "" ? "; " size : "") ($6 != "" ? "; " $6 : "") ($7 != "" ? "; " $7 " fps" : "") \
        (codecs != "" ? "; " codecs : "") ($10 != "" ? "; " $10 "k" : "") ($11 != "" ? "; " $11 : "")
      print url, $1, $2, $3, $4, details, sprintf("%-8s %-5s %-11s %3s  \033[%sm%-5s\033[0m %6s  %s%-28s %6s  %s%s", $1, $5, $6, $7, color[$3], $3, size, dim, codecs, ($10 != "" ? $10 "k" : ""), $11, rst) }'
}

# youtube::source_formats --url URL
youtube::source_formats() {
  local url="" rows
  while (($#)); do
    case "$1" in
      --url) url="${2:-}" && shift ;;
      *)
        printf 'youtube: unknown argument: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done
  [[ -n "$url" ]] || {
    printf 'youtube: formats needs --url URL\n' >&2
    return 2
  }
  rows="$(youtube::formats "$url")" || return
  youtube::format_display "$url" <<< "$rows"
}

# youtube::format: search rows -> display lines ("duration  title  channel · 1.2M views", dim parts)
youtube::format() {
  local dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m'
  awk -F'\t' -v OFS='\t' -v dim="$dim" -v rst="$rst" '
    function short(n) {
      if (n !~ /^[0-9]+$/) return ""
      if (n >= 1e9) return sprintf("%.1fB", n / 1e9)
      if (n >= 1e6) return sprintf("%.1fM", n / 1e6)
      if (n >= 1e3) return sprintf("%.1fK", n / 1e3)
      return n
    }
    { if ($4 ~ /^[0-9]+$/) $4 = "0:" sprintf("%02d", $4)
      v = short($5); meta = $3 (v != "" ? (($3 != "" ? " · " : "") v " views") : "")
      print $1, $2, $3, $4, $5, $6, sprintf("%s%8s%s  %s  %s%s%s", dim, ($4 != "" ? $4 : "live"), rst, $2, dim, meta, rst) }'
}

# youtube::source: the recent searches for an empty query, else the search for $FZF_QUERY; formats mode:
# a video's formats
youtube::source() {
  [[ "${FZX_MODE:-search}" == formats ]] && {
    youtube::source_formats "$@"
    return
  }
  local query dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m' red=$'\e[31m' rows file
  youtube::trim "${FZF_QUERY:-}" query
  if [[ -z "$query" ]]; then
    file="$(youtube::history_file)"
    [[ -f "$file" ]] && awk -v dim="$dim" -v rst="$rst" '{ printf "search\t%s\t\t\t\t\t%s  recent%s  %s\n", $0, dim, rst, $0 }' "$file"
    youtube::_searched ""
    return 0
  fi
  if ! rows="$(youtube::search "$query")"; then
    printf 'youtube: search failed: %s\n' "$query" >&2
    printf 'error\tsearch failed: %s (see fzx debug tail)\t\t\t\t\t%s  search failed:%s %s\n' "$query" "$red" "$rst" "$query"
    return 1
  fi
  [[ -n "$rows" ]] && youtube::format <<< "$rows"
  youtube::history_add "$query"
  youtube::_searched "$query"
}

# youtube::_searched <query>: under fzx, the query the list now shows (state/youtube_query)
youtube::_searched() {
  declare -F fzx::state_set > /dev/null && [[ -n "${FZX_SESSION_DIR:-}" ]] || return 0
  fzx::state_set youtube_query "$1"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" youtube
  youtube::source "$@"
}
