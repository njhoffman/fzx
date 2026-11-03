#!/usr/bin/env bash
# youtube actions (on the selected videos' urls) and the enter transform.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# show a failure until a key is pressed; execute would otherwise wipe it at once
youtube::_report() {
  local rc="$1"
  ((rc == 0)) && return 0
  printf '\n\e[31mfailed (exit %s)\e[0m, press a key ' "$rc"
  IFS= read -rsn1 < /dev/tty || :
  return "$rc"
}

# youtube::audio_dir <var>: FZX_YOUTUBE_AUDIO_DIR, else the XDG music directory, else ~/Music
youtube::audio_dir() {
  local _d="${FZX_YOUTUBE_AUDIO_DIR:-}"
  [[ -n "$_d" ]] || _d="$(xdg-user-dir MUSIC 2> /dev/null)" || :
  [[ -n "$_d" && "$_d" != "$HOME" ]] || _d="$HOME/Music"
  printf -v "$1" '%s' "$_d"
}

# youtube::video_dir <var>: FZX_YOUTUBE_VIDEO_DIR, else the XDG videos directory, else ~/Videos
youtube::video_dir() {
  local _d="${FZX_YOUTUBE_VIDEO_DIR:-}"
  [[ -n "$_d" ]] || _d="$(xdg-user-dir VIDEOS 2> /dev/null)" || :
  [[ -n "$_d" && "$_d" != "$HOME" ]] || _d="$HOME/Videos"
  printf -v "$1" '%s' "$_d"
}

# youtube::selector <url> <format ids...>: the -f selector: the ids joined with + (a video and an audio
# format are merged); a lone video-only format gets +bestaudio. The kinds come from the formats cache.
youtube::selector() {
  local url="$1" rows kind sel
  shift
  sel="$(IFS=+; printf '%s' "$*")"
  if (($# == 1)) && rows="$(youtube::formats "$url" 2> /dev/null)"; then
    kind="$(F="$1" awk -F'\t' '$1 == ENVIRON["F"] { print $3; exit }' <<< "$rows")"
    [[ "$kind" == video ]] && sel+="+bestaudio"
  fi
  printf '%s' "$sel"
}

# youtube::download <args...>: search mode: the urls at their best; formats mode: <url> <format ids...>
# into the videos directory (the audio directory when every format is audio only)
youtube::download() {
  local dir sel=() url rows kind audio=1 f
  if [[ "${FZX_MODE:-search}" == formats ]]; then
    url="${1:-}"
    shift
    [[ "$url" == http* ]] && (($#)) || return 0
    sel=(-f "$(youtube::selector "$url" "$@")")
    rows="$(youtube::formats "$url" 2> /dev/null)" || rows=""
    for f in "$@"; do
      kind="$(F="$f" awk -F'\t' '$1 == ENVIRON["F"] { print $3; exit }' <<< "$rows")"
      [[ "$kind" == audio ]] || audio=0
    done
    set -- "$url"
  else
    audio=0
  fi
  if ((audio)); then youtube::audio_dir dir; else youtube::video_dir dir; fi
  mkdir -p -- "$dir" || return
  printf 'saving to %s\n\n' "$dir"
  command yt-dlp --no-warnings "${sel[@]}" "${FZX_YOUTUBE_DOWNLOAD_ARGS[@]}" -o "$dir/%(title)s.%(ext)s" -- "$@"
  youtube::_report $?
}

# youtube::action <play|audio|browser|mp3|download> <items...>: recent-search and error rows are skipped;
# download in formats mode takes the url and the format ids
youtube::action() {
  local action="${1:-}" urls=() u dir
  local -A seen=()
  shift
  if [[ "$action" == download ]]; then
    youtube::download "$@"
    return
  fi
  # formats rows all carry the video's url: once each
  for u in "$@"; do
    [[ ("$u" == http://* || "$u" == https://*) && -z "${seen[$u]:-}" ]] && urls+=("$u") && seen[$u]=1
  done
  ((${#urls[@]})) || return 0
  case "$action" in
    play) nohup "${FZX_YOUTUBE_PLAYER[@]:-mpv}" -- "${urls[@]}" > /dev/null 2>&1 & ;;
    audio)
      trap : INT
      "${FZX_YOUTUBE_PLAYER[@]:-mpv}" --no-video -- "${urls[@]}"
      ;;
    browser)
      fzx::require builtin
      fzx::open_url "${urls[@]}"
      ;;
    mp3)
      if ! command -v ffmpeg > /dev/null; then
        printf 'youtube: mp3 needs ffmpeg\n' >&2
        printf 'youtube: mp3 needs ffmpeg\n'
        youtube::_report 1
        return
      fi
      youtube::audio_dir dir
      mkdir -p -- "$dir" || return
      printf 'saving to %s\n\n' "$dir"
      command yt-dlp --no-warnings -x --audio-format mp3 "${FZX_YOUTUBE_MP3_ARGS[@]}" \
        -o "$dir/%(title)s.%(ext)s" -- "${urls[@]}"
      youtube::_report $?
      ;;
    *)
      printf 'youtube: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

# youtube::_arg <action> <text>: action(text) with a delimiter pair fzf accepts that text does not close
youtube::_arg() {
  local d
  for d in '()' '[]' '{}' '<>' '~~' '!!' '@@' '##' '$$' '%%' '^^' '&&' '**' ';;' '//' '||'; do
    [[ "$2" == *"${d:1:1}"* ]] && continue
    printf '%s%s%s%s' "$1" "${d:0:1}" "$2" "${d:1:1}"
    return 0
  done
  return 1
}

# youtube::transform enter <first field> <second field>: enter searches when the query is new (or reruns
# a recent search the cursor is on, if nothing new was typed), otherwise accepts the video.
# youtube::transform formats <first field>: the video's formats as a child session (a bell elsewhere)
youtube::transform() {
  local name="${1:-}" kind="${2:-}" text="${3:-}" query last="" reload q
  case "$name" in
    enter)
      youtube::trim "${FZF_QUERY:-}" query
      fzx::state_get youtube_query last || last=""
      fzx::require opts
      fzx::reload_action "$(fzx::cb source)" reload
      if [[ "$kind" == search && "$query" == "$last" && -n "$text" ]]; then
        youtube::_arg change-query "$text" q || return 0
        printf '%s+%s' "$q" "$reload"
      elif [[ -n "$query" && "$query" != "$last" ]]; then
        printf '%s' "$reload"
      elif [[ "$kind" == http* ]]; then
        printf 'accept'
      fi
      ;;
    formats)
      if [[ "$kind" == http* ]]; then
        fzx::require nav
        fzx::nav goto youtube:formats --url "$kind"
      else
        printf 'bell'
      fi
      ;;
    *)
      printf 'youtube: unknown transform: %s\n' "$name" >&2
      return 2
      ;;
  esac
}

# run directly: core for the formats cache (FZX_CACHE_DIR, fzx::parse_duration)
[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  youtube::action "$@"
}
