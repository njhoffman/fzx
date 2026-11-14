#!/usr/bin/env bash
# music preview: a song's cover, tags and musicman fields (the queue's first: the player's state); an
# album's cover and songs; an artist's albums; a playlist's songs

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# music::cache_dir <sub>: the directory of cached covers or musicman answers
music::cache_dir() {
  local dir="${XDG_CACHE_HOME:-$HOME/.cache}/fzx/music/$1"
  mkdir -p -- "$dir" 2> /dev/null && printf '%s' "$dir"
}

# music::cover <file> <rows>: the album art of a song (the folder's cover file, else the embedded one),
# fetched through MPD and cached per directory, drawn with chafa in at most <rows> rows; nothing when
# there is none (remembered too) or no chafa
music::cover() {
  local file="$1" rows="$2" dir key img cols="${FZF_PREVIEW_COLUMNS:-80}" w
  ((rows >= 3)) && command -v chafa > /dev/null || return 0
  dir="$(music::cache_dir covers)" || return 0
  key="$(printf '%s' "${file%/*}" | command md5sum)"
  img="$dir/${key%% *}"
  if [[ ! -e "$img" && ! -e "$img.none" ]]; then
    if ! { command mpc albumart "$file" > "$img.tmp" 2> /dev/null && [[ -s "$img.tmp" ]]; } &&
      ! { command mpc readpicture "$file" > "$img.tmp" 2> /dev/null && [[ -s "$img.tmp" ]]; }; then
      rm -f -- "$img.tmp"
      : > "$img.none"
      return 0
    fi
    mv -f -- "$img.tmp" "$img"
  fi
  [[ -s "$img" ]] || return 0
  # cells are about twice as tall as wide: a square cover is two columns per row
  w=$((rows * 2))
  ((w > cols)) && w="$cols"
  command chafa --format="${FZX_PREVIEW_IMAGE_FORMAT:-symbols}" --size="${w}x$rows" --animate=off -- "$img" 2> /dev/null
}

# music::cover_rows <text lines>: the rows a cover gets above that much text: FZX_MUSIC_COVER_ROWS, less
# when the preview is short, at least what the text leaves (0 when that is too little)
music::cover_rows() {
  local lines="${FZF_PREVIEW_LINES:-40}" max="${FZX_MUSIC_COVER_ROWS:-14}" left
  left=$((lines - $1 - 1))
  ((left > max)) && left="$max"
  ((left > lines / 2)) && left=$((lines / 2))
  ((left < 4)) && left=0
  printf '%d' "$left"
}

# music::music_dir: MPD's music_directory (FZX_MUSIC_DIR, else mpd.conf's), without a trailing slash
music::music_dir() {
  local d="${FZX_MUSIC_DIR:-}" conf
  if [[ -z "$d" ]]; then
    for conf in "${XDG_CONFIG_HOME:-$HOME/.config}/mpd/mpd.conf" "$HOME/.mpdconf" /etc/mpd.conf; do
      [[ -r "$conf" ]] || continue
      d="$(command sed -n 's/^[[:space:]]*music_directory[[:space:]]*"\(.*\)".*/\1/p' "$conf" | command head -n 1)"
      [[ -n "$d" ]] && break
    done
  fi
  d="${d/#\~/$HOME}"
  printf '%s' "${d%/}"
}

# music::musicman <file>: musicman's fields of a song (FZX_MUSIC_TAGS), "name<TAB>value" lines; its
# answer is cached until the file changes. Nothing when musicman is off, missing or knows nothing
music::musicman() {
  local file="$1" root path dir key json tags=("${FZX_MUSIC_TAGS[@]}")
  ((${#tags[@]})) || tags=(rating grouping context mood picks type)
  [[ "${FZX_MUSIC_MUSICMAN:-auto}" != off ]] && command -v musicman > /dev/null && command -v jq > /dev/null || return 0
  root="$(music::music_dir)"
  [[ -n "$root" ]] || return 0
  path="$root/$file"
  [[ -f "$path" ]] || return 0
  dir="$(music::cache_dir tags)" || return 0
  key="$(printf '%s' "$path" | command md5sum)"
  json="$dir/${key%% *}.json"
  if [[ ! -s "$json" || "$path" -nt "$json" ]]; then
    if ! command musicman view "$path" --format json > "$json.tmp" 2> /dev/null || [[ ! -s "$json.tmp" ]]; then
      rm -f -- "$json.tmp"
      return 0
    fi
    mv -f -- "$json.tmp" "$json"
  fi
  command jq -r --args '.[0] as $s | $ARGS.positional[] | select(($s[.] // "") != "") | "\(.)\t\($s[.])"' \
    "${tags[@]}" < "$json" 2> /dev/null
}

# music::stars <rating 0-5 in half steps>: the rating as five stars
music::stars() {
  local r="$1" full half i out=""
  [[ "$r" =~ ^([0-9])(\.([0-9]))?$ ]] || { printf '%s' "$r"; return; }
  full="${BASH_REMATCH[1]}" half=0
  [[ "${BASH_REMATCH[3]:-0}" -ge 5 ]] && half=1
  for ((i = 0; i < 5; i++)); do
    if ((i < full)); then out+="★"; elif ((i == full && half)); then out+="⯪"; else out+="☆"; fi
  done
  printf '%s %s' "$out" "$r"
}

# music::status: the player's state, position, modes and volume
music::status() {
  command mpc status $'%state%\t%currenttime%\t%totaltime%\t%songpos%\t%length%\t%random%\t%repeat%\t%single%\t%consume%\t%volume%' 2> /dev/null |
    command awk -F'\t' -v b="$MP_B" -v d="$MP_D" -v r="$MP_R" '
      {
        modes = ""
        if ($6 == "on") modes = modes " random"; if ($7 == "on") modes = modes " repeat"
        if ($8 == "on") modes = modes " single"; if ($9 == "on") modes = modes " consume"
        vol = $10; gsub(/ /, "", vol)
        printf "%s%s%s  %s / %s  %s%d of %d%s\n", b, $1, r, $2, $3, d, $4, $5, r
        printf "%s%s%s\n\n", d, (modes == "" ? "in order" : substr(modes, 2)) (vol == "" || vol == "-1%" || vol == "n/a" ? "" : ", volume " vol), r
      }'
}

# music::song <file>: a song's cover, title, artist, album and year, number, length, genre, musicman's
# fields and the file
music::song() {
  local file="$1" text tags name value
  text="$(command mpc -f $'[%title%]\t[%artist%]\t[%album%]\t[%date%]\t[%track%]\t[%disc%]\t[%time%]\t[%genre%]' ls "$file" 2> /dev/null |
    command head -n 1 | command awk -F'\t' -v b="$MP_B" -v d="$MP_D" -v r="$MP_R" -v ca="$MP_A" -v cal="$MP_AL" -v f="$file" '
      function row(k, v) { if (v != "") printf "%s%-6s%s  %s\n", d, k, r, v }
      {
        t = $1; if (t == "") { t = f; sub(/.*\//, "", t) }
        print b t r
        if ($2 != "") print ca $2 r
        if ($3 != "") print cal $3 r (length($4) >= 4 ? d "  " substr($4, 1, 4) r : "")
        print ""
        row("track", $5 ($6 != "" ? " (disc " $6 ")" : "")); row("length", $7); row("genre", $8)
      }')"
  tags="$(music::musicman "$file")"
  if [[ -n "$tags" ]]; then
    text+=$'\n'
    while IFS=$'\t' read -r name value; do
      [[ "$name" == rating ]] && value="$MP_RT$(music::stars "$value")$MP_R"
      printf -v value '%s%-8s%s  %s' "$MP_D" "$name" "$MP_R" "$value"
      text+=$'\n'"$value"
    done <<< "$tags"
  fi
  text+=$'\n\n'"$MP_D$file$MP_R"
  music::cover "$file" "$(music::cover_rows "$(printf '%s\n' "$text" | command wc -l)")"
  printf '%s\n' "$text"
}

# music::preview [module args...] -- <id> <kind> <label>
music::preview() {
  music::args "$@" 2> /dev/null || :
  while (($#)) && [[ "$1" != -- ]]; do shift; done
  (($#)) && shift
  local id="${1:-}" kind="${2:-}" label="${3:-}" artist album first n
  [[ -n "$id" ]] || return 0
  declare -g MP_B=$'\e[1m' MP_D=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" MP_R=$'\e[0m'
  declare -g MP_A=$'\e['"${FZX_COLORS[music_artist]:-38;5;180}m" MP_AL=$'\e['"${FZX_COLORS[music_album]:-38;5;111}m"
  declare -g MP_RT=$'\e['"${FZX_COLORS[music_rating]:-38;5;179}m"
  [[ -n "${NO_COLOR:+x}" ]] && MP_B="" MP_D="" MP_R="" MP_A="" MP_AL="" MP_RT=""
  case "$kind" in
    song)
      [[ "${FZX_MODE:-queue}" == queue ]] && music::status
      music::song "$label"
      ;;
    album)
      artist="${id%%"$MUSIC_US"*}" album="${id#*"$MUSIC_US"}"
      first="$(music::album_songs "$artist" "$album" | command head -n 1 | command cut -f1)"
      n="$(music::album_songs "$artist" "$album" | command wc -l)"
      [[ -n "$first" ]] && music::cover "$first" "$(music::cover_rows $((n + 3)))"
      printf '%s%s%s\n%s%s%s\n\n' "$MP_B" "${album:-(no album)}" "$MP_R" "$MP_A" "$artist" "$MP_R"
      MUSIC_ARTIST="$artist" MUSIC_ALBUM="$album" MUSIC_HAS_ALBUM=1 MUSIC_PLAYLIST="" music::tracks | command cut -f4
      ;;
    artist)
      printf '%s%s%s\n\n' "$MP_B" "$id" "$MP_R"
      music::albums "$id" | command cut -f4
      ;;
    playlist)
      printf '%s%s%s\n\n' "$MP_B" "$id" "$MP_R"
      MUSIC_PLAYLIST="$id" music::tracks | command cut -f4
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" music
  music::preview "$@"
}
