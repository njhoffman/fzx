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

# youtube::action <play|audio|browser|mp3> <items...>: recent-search and error rows are skipped
youtube::action() {
  local action="${1:-}" urls=() u dir
  shift
  for u in "$@"; do
    [[ "$u" == http://* || "$u" == https://* ]] && urls+=("$u")
  done
  ((${#urls[@]})) || return 0
  case "$action" in
    play) nohup "${FZX_YOUTUBE_PLAYER[@]:-mpv}" -- "${urls[@]}" > /dev/null 2>&1 & ;;
    audio)
      trap : INT
      "${FZX_YOUTUBE_PLAYER[@]:-mpv}" --no-video -- "${urls[@]}"
      ;;
    browser)
      for u in "${urls[@]}"; do
        if command -v xdg-open > /dev/null; then xdg-open "$u"; else open "$u"; fi > /dev/null 2>&1
      done
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
# a recent search the cursor is on, if nothing new was typed), otherwise accepts the video
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
    *)
      printf 'youtube: unknown transform: %s\n' "$name" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && youtube::action "$@"
