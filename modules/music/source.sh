#!/usr/bin/env bash
# music source, through mpc (MPD). Lines are "id<TAB>kind<TAB>label<TAB>display":
#   queue      id: the queue position; label: the file
#   artists    id: the artist; label: the artist
#   albums     id: "artist<US>album" (US: \x1f); label: "artist - album"
#   playlists  id: the playlist; label: the playlist
#   tracks     id: the file; label: the file
# Modes from $FZX_MODE: queue, artists, albums, playlists; artist (the albums of --artist A) and tracks
# (an album's songs, --artist A --album B, or a playlist's, --playlist P) are the drill-downs.
# Artists are album artists (MPD falls back to the artist when a song has none); the byartist toggle, or
# --tag artist in a drill-down, lists them by the artist tag instead.

MUSIC_US=$'\x1f'

# music::args [--artist A] [--album B] [--playlist P] [--tag albumartist|artist] [--]
music::args() {
  declare -g MUSIC_ARTIST="" MUSIC_ALBUM="" MUSIC_PLAYLIST="" MUSIC_TAG="" MUSIC_HAS_ALBUM=0
  while (($#)); do
    case "$1" in
      --artist) MUSIC_ARTIST="${2:-}" && shift 2 ;;
      --album) MUSIC_ALBUM="${2:-}" MUSIC_HAS_ALBUM=1 && shift 2 ;;
      --playlist) MUSIC_PLAYLIST="${2:-}" && shift 2 ;;
      --tag)
        case "${2:-}" in
          albumartist | artist) MUSIC_TAG="$2" ;;
          *) printf 'music: --tag takes albumartist or artist: %s\n' "${2:-}" >&2; return 2 ;;
        esac
        shift 2
        ;;
      --) shift; break ;;
      *) printf 'music: unknown argument: %s\n' "$1" >&2; return 2 ;;
    esac
  done
  if [[ -z "$MUSIC_TAG" ]]; then
    MUSIC_TAG=albumartist
    [[ " ${FZX_TOGGLES:-} " == *" byartist "* ]] && MUSIC_TAG=artist
  fi
  return 0
}

# music::artist_fmt: the mpc format of the artist field under MUSIC_TAG
music::artist_fmt() {
  if [[ "$MUSIC_TAG" == artist ]]; then echo '[%artist%]'; else echo '[%albumartist%|%artist%]'; fi
}

# music::library [find args...]: "artist<TAB>album<TAB>date<TAB>time" per song, every song without
# arguments (search filename "" matches all)
music::library() {
  local fmt
  fmt="$(music::artist_fmt)"$'\t[%album%]\t[%date%]\t[%time%]'
  if (($#)); then
    command mpc -f "$fmt" find "$@"
  else
    command mpc -f "$fmt" search filename ""
  fi
}

# music::colors: the escapes the rows use (r, d: dim, a: artist, al: album, y: year, c: current)
music::colors() {
  declare -g MC_R=$'\e[0m' MC_D=$'\e['"${FZX_COLORS[dim]:-38;5;244}m"
  declare -g MC_A=$'\e['"${FZX_COLORS[music_artist]:-38;5;180}m" MC_AL=$'\e['"${FZX_COLORS[music_album]:-38;5;111}m"
  declare -g MC_Y=$'\e['"${FZX_COLORS[music_year]:-38;5;244}m" MC_C=$'\e['"${FZX_COLORS[music_current]:-1;38;5;114}m"
  if [[ -n "${NO_COLOR+x}" ]]; then MC_R="" MC_D="" MC_A="" MC_AL="" MC_Y="" MC_C=""; fi
}

# music::artists: each artist with its album and song counts, by name
music::artists() {
  music::colors
  music::library | LC_ALL=C command awk -F'\t' -v d="$MC_D" -v r="$MC_R" '
    $1 == "" { next }
    { songs[$1]++; if (!(($1 SUBSEP $2) in seen)) { seen[$1, $2] = 1; albums[$1]++ } }
    END { for (a in songs) printf "%s\t%s\t%s\t%s  %s%d album%s, %d song%s%s\n", a, "artist", a, a, d,
      albums[a], albums[a] == 1 ? "" : "s", songs[a], songs[a] == 1 ? "" : "s", r }' |
    command sort -t$'\t' -k1,1 -f
}

# music::albums [artist]: albums with their year, artist (all albums only) and song count; one artist's
# by year, all of them by artist then year
music::albums() {
  local one=0
  music::colors
  # set before the pipeline: its first part runs in a subshell
  (($#)) && one=1
  if ((one)); then
    music::library "$MUSIC_TAG" "$1"
  else
    music::library
  fi | LC_ALL=C command awk -F'\t' -v one="$one" -v us="$MUSIC_US" -v d="$MC_D" -v r="$MC_R" \
    -v cy="$MC_Y" -v ca="$MC_A" -v cal="$MC_AL" '
    one == 0 && $1 == "" { next }
    {
      k = $1 SUBSEP $2
      if (!(k in n)) { order[++c] = k; art[k] = $1; alb[k] = $2 }
      # %time% is m:ss (h:mm:ss past an hour)
      m = split($4, tp, ":"); sec = 0; for (j = 1; j <= m; j++) sec = sec * 60 + tp[j]
      n[k]++; secs[k] += sec
      y = substr($3, 1, 4)
      if (y ~ /^[0-9]{4}$/ && (!(k in year) || y < year[k])) year[k] = y
    }
    END {
      for (i = 1; i <= c; i++) {
        k = order[i]; y = (k in year) ? year[k] : "    "; name = alb[k] == "" ? "(no album)" : alb[k]
        t = int(secs[k] / 60)
        line = cy y r "  " cal name r
        if (!one) line = line "  " ca art[k] r
        line = line "  " d n[k] " song" (n[k] == 1 ? "" : "s") ", " t " min" r
        # the sort key leads, cut off below
        printf "%s\t%s\t%s%s%s\talbum\t%s - %s\t%s\n", (one ? "" : tolower(art[k])), y, art[k], us, alb[k], art[k], alb[k], line
      }
    }' | command sort -t$'\t' -k1,1 -k2,2 | command cut -f3-
}

# music::album_songs <artist> <album>: "file<TAB>disc<TAB>track<TAB>title<TAB>artist<TAB>time" of an
# album's songs, in disc and track order
music::album_songs() {
  command mpc -f $'%file%\t[%disc%]\t[%track%]\t[%title%]\t[%artist%]\t[%time%]' find "$MUSIC_TAG" "$1" album "$2" |
    command sort -t$'\t' -k2,2n -k3,3n -k1,1
}

# music::playlist_songs <playlist>: the same fields for a stored playlist's songs, in its order
music::playlist_songs() {
  command mpc -f $'%file%\t[%disc%]\t[%track%]\t[%title%]\t[%artist%]\t[%time%]' playlist "$1"
}

# music::tracks: the songs of --artist/--album or --playlist; an album's numbered, a playlist's with
# their artist
music::tracks() {
  music::colors
  if [[ -z "$MUSIC_PLAYLIST" ]] && ! ((MUSIC_HAS_ALBUM)); then
    printf 'music: tracks need --artist and --album, or --playlist\n' >&2
    return 2
  fi
  if [[ -n "$MUSIC_PLAYLIST" ]]; then
    music::playlist_songs "$MUSIC_PLAYLIST"
  else
    music::album_songs "$MUSIC_ARTIST" "$MUSIC_ALBUM"
  fi | command awk -F'\t' -v pl="${MUSIC_PLAYLIST:+1}" -v artist="$MUSIC_ARTIST" -v d="$MC_D" -v r="$MC_R" -v ca="$MC_A" '
    {
      title = $4; if (title == "") { title = $1; sub(/.*\//, "", title) }
      no = $3; sub(/\/.*/, "", no)
      if (pl) line = sprintf("%3d  %s%s%s - %s", NR, ca, $5, r, title)
      else {
        line = sprintf("%s%3s%s  %s", d, no, r, title)
        if ($5 != "" && $5 != artist) line = line "  " ca $5 r
      }
      printf "%s\tsong\t%s\t%s  %s%s%s\n", $1, $1, line, d, $6, r
    }'
}

# music::queue: the queue in order, the current song marked
music::queue() {
  local cur i_play i_pause
  music::colors
  fzx::require icons
  fzx::icon running i_play
  fzx::icon paused i_pause
  cur="$(command mpc status '%songpos% %state%' 2> /dev/null)"
  command mpc -f $'%position%\t%file%\t[%artist%]\t[%title%]\t[%album%]\t[%time%]' playlist |
    command awk -F'\t' -v cur="$cur" -v play="${i_play:->}" -v pause="${i_pause:-=}" \
      -v d="$MC_D" -v r="$MC_R" -v ca="$MC_A" -v cal="$MC_AL" -v cc="$MC_C" '
      BEGIN { split(cur, s, " ") }
      {
        title = $4; if (title == "") { title = $2; sub(/.*\//, "", title) }
        mark = "  "; on = 0
        if ($1 == s[1] && s[2] != "stopped") { mark = (s[2] == "playing" ? play : pause) " "; on = 1 }
        line = sprintf("%s%3d  %s%s%s - %s%s%s", mark, $1, ca, $3, r, (on ? cc : ""), title, r)
        line = line "  " d $6 r
        if ($5 != "") line = line "  " cal $5 r
        printf "%s\tsong\t%s\t%s\n", $1, $2, line
      }'
}

# music::playlists: the stored playlists with their song counts
music::playlists() {
  local p n
  music::colors
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    n="$(command mpc playlist "$p" 2> /dev/null | command wc -l)"
    printf '%s\tplaylist\t%s\t%s  %s%d song%s%s\n' "$p" "$p" "$p" "$MC_D" "$n" "$( ((n == 1)) || echo s)" "$MC_R"
  done < <(command mpc lsplaylists | LC_ALL=C command sort -f)
}

music::source() {
  music::args "$@" || return
  command -v mpc > /dev/null || { printf 'music: needs mpc\n' >&2; return 2; }
  case "${FZX_MODE:-queue}" in
    queue) music::queue ;;
    artists) music::artists ;;
    albums) music::albums ;;
    artist)
      [[ -n "$MUSIC_ARTIST" ]] || { printf 'music: artist needs --artist\n' >&2; return 2; }
      music::albums "$MUSIC_ARTIST"
      ;;
    tracks) music::tracks ;;
    playlists) music::playlists ;;
    *)
      printf 'music: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" music
  music::source "$@"
}
