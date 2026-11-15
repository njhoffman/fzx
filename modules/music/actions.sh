#!/usr/bin/env bash
# music actions on the selected rows' ids (queue positions, artists, "artist<US>album" keys, playlists,
# files, smart playlist names), by mode, and the enter and header transforms

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
# shellcheck source=./preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/preview.sh"
# shellcheck source=./edit.sh
source "$(dirname "${BASH_SOURCE[0]}")/edit.sh"

# music::files <ids...>: the files the ids stand for under FZX_MODE, one per line, in play order
music::files() {
  local id
  for id; do
    [[ -n "$id" ]] || continue
    case "${FZX_MODE:-queue}" in
      artists) command mpc -f '%file%' find "$MUSIC_TAG" "$id" ;;
      albums | artist) music::album_songs "${id%%"$MUSIC_US"*}" "${id#*"$MUSIC_US"}" | command cut -f1 ;;
      playlists) command mpc -f '%file%' playlist "$id" ;;
      tracks) printf '%s\n' "$id" ;;
    esac
  done
}

# music::action <name> [module args...] -- <ids...>
#   play:     replace the queue with the selection's songs and play (queue: play the first selected)
#   add:      append them; insert: after the song playing, in order
#   remove:   queue: the selected positions; delete: playlists: the selected playlists
#   clear:    the queue; save: the queue as a playlist named on the terminal
#   pause, next, previous: the player
#   rate, tags: queue and tracks: the songs' rating, or their context, mood and picks (edit.sh); the ids
#   are the files here (FZX_ACTION_ARGS_FOR)
#   back:     musicman's player back: return to what played before the last side trip
# With musicman 1.86+, play in the library modes is a side trip (musicman player mpd play --files: back
# returns to what played). The smart mode (smart.sh): play, a side trip; add; delete; save, the query as
# a preset (its one argument, FZX_ACTION_ARGS_FOR); terms, edit the preset's
music::action() {
  local action="${1:-}" files=() i name mm text
  shift
  music::args "$@" 2> /dev/null || :
  while (($#)) && [[ "$1" != -- ]]; do shift; done
  (($#)) && shift
  if [[ "${FZX_MODE:-queue}" == smart ]]; then
    music::smart_action "$action" "$@"
    return
  fi
  case "$action" in
    play)
      if [[ "${FZX_MODE:-queue}" == queue ]]; then
        [[ -n "${1:-}" ]] || return 0
        command mpc -q play "$1"
        return
      fi
      mapfile -t files < <(music::files "$@")
      ((${#files[@]})) || { printf 'music: nothing to play\n' >&2; return 1; }
      if music::back_path mm wait; then
        printf '%s\n' "${files[@]}" | command musicman player mpd play --files -
      else
        command mpc -q clear && printf '%s\n' "${files[@]}" | command mpc -q add && command mpc -q play
      fi
      ;;
    back) music::back ;;
    terms) printf 'music: terms edits a smart playlist\n' >&2; return 1 ;;
    add | insert)
      [[ "${FZX_MODE:-queue}" == queue ]] && { printf 'music: already queued\n' >&2; return 1; }
      mapfile -t files < <(music::files "$@")
      ((${#files[@]})) || { printf 'music: nothing to %s\n' "$action" >&2; return 1; }
      if [[ "$action" == add ]]; then
        printf '%s\n' "${files[@]}" | command mpc -q add
      else
        # each insert goes right after the song playing: the last first keeps them in order
        for ((i = ${#files[@]} - 1; i >= 0; i--)); do
          command mpc -q insert "${files[i]}" || return
        done
      fi
      ;;
    remove)
      [[ "${FZX_MODE:-queue}" == queue ]] || { printf 'music: remove works on the queue\n' >&2; return 1; }
      # the highest position first, so the others keep theirs
      printf '%s\n' "$@" | command sort -rn | while IFS= read -r i; do
        [[ "$i" =~ ^[0-9]+$ ]] && command mpc -q del "$i"
      done
      ;;
    delete)
      [[ "${FZX_MODE:-queue}" == playlists ]] || { printf 'music: delete works on playlists\n' >&2; return 1; }
      for name; do
        [[ -n "$name" ]] && { command mpc -q rm "$name" || return; }
      done
      ;;
    clear) command mpc -q clear ;;
    save)
      fzx::tty_read -r -e -p "save the queue as playlist: " name || return 0
      [[ -n "$name" ]] || return 0
      command mpc -q save "$name"
      ;;
    rate | tags)
      case "${FZX_MODE:-queue}" in
        queue | tracks) "music::$action" "$@" ;;
        *) printf 'music: %s works on songs (the queue, an album or a playlist)\n' "$action" >&2; return 1 ;;
      esac
      ;;
    pause) command mpc -q toggle ;;
    next) command mpc -q next ;;
    previous) command mpc -q prev ;;
    *) printf 'music: unknown action: %s\n' "$action" >&2; return 2 ;;
  esac
}

# music::back: musicman's player back, which says why when there is nowhere to go
music::back() {
  local mm
  music::back_path mm wait || { printf 'music: going back needs musicman 1.86+\n' >&2; return 1; }
  command musicman player back
}

# music::smart_action <action> <names...>: the smart mode's actions (save: the query instead of names)
music::smart_action() {
  local action="$1" name text row
  shift
  case "$action" in
    play) music::smart_play side "$@" ;;
    add) music::smart_play add "$@" ;;
    back) music::back ;;
    delete)
      (($#)) || return 0
      command musicman smart rm "$@"
      ;;
    save)
      text="${1:-}"
      [[ -n "$text" ]] || { printf 'music: type the search terms as the query first\n' >&2; return 1; }
      fzx::tty_read -r -e -p "save \"$text\" as smart playlist: " name || return 0
      [[ -n "$name" ]] || return 0
      music::smart_save "$name" "$text"
      ;;
    terms)
      name="${1:-}"
      [[ -n "$name" ]] || return 0
      music::smart_row "$name" row || { printf 'music: no smart playlist %s\n' "$name" >&2; return 1; }
      text="$(printf '%s' "$row" | command cut -f2)"
      music::ask text "$name: " "$text" || return 0
      [[ -n "$text" ]] || return 0
      music::smart_save "$name" "$text"
      ;;
    pause) command mpc -q toggle ;;
    next) command mpc -q next ;;
    previous) command mpc -q prev ;;
    clear) command mpc -q clear ;;
    *) printf 'music: %s works on songs, not smart playlists\n' "$action" >&2; return 1 ;;
  esac
}

# music::header_action: the fzf action that shows the module's header with the back point under it
# ("back: artist - title") or without one; nothing without musicman 1.86+. In the header position the
# header goes to meta/header, which fzx's header callback draws under the component line
music::header_action() {
  # shellcheck disable=SC2034  # mm: set through a nameref
  local header point action mm d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  music::back_path mm || return 0
  [[ -n "${NO_COLOR:+x}" ]] && d="" r=""
  music::header header
  if music::back_point point; then
    point="${d}back: $point$r"
    header+="${header:+$'\n'}$point"
  fi
  if [[ "${FZX_HEADER_POSITION:-footer}" == header ]] && fzx::in_session; then
    fzx::meta_set header "$header"
    printf 'transform-header(%s)' "$(fzx::cb header)"
    return
  fi
  fzx::require opts
  fzx::action_arg change-header "$header" action && printf '%s' "$action"
}

# music::transform enter [module args...] -- <id> <index>: queue: play the song; artists: a child session
# with their albums; albums: one with the album's songs; playlists: one with its songs; songs of an album
# or a playlist: the queue becomes the album or playlist, played from the song (index: fzf's {n}); smart:
# play the preset as the main list (musicman forgets the back point), then reload.
# music::transform header [module args...] --: the header with the back point (bound to load)
music::transform() {
  local name="${1:-}" id n args=()
  shift
  music::args "$@" 2> /dev/null || :
  while (($#)) && [[ "$1" != -- ]]; do shift; done
  (($#)) && shift
  if [[ "$name" == header ]]; then
    music::header_action
    return 0
  fi
  id="${1:-}" n="${2:-0}"
  [[ "$name" == enter && -n "$id" ]] || return 0
  [[ "$MUSIC_TAG" == artist ]] && args=(--tag artist)
  case "${FZX_MODE:-queue}" in
    smart)
      music::smart_play main "$id" >&2 || return 0
      fzx::require opts
      local reload
      fzx::reload_action "$(fzx::cb source)" reload
      printf '%s' "$reload"
      ;;
    queue)
      command mpc -q play "$id" || return 0
      fzx::require opts
      local reload
      fzx::reload_action "$(fzx::cb source)" reload
      printf '%s' "$reload"
      ;;
    artists)
      fzx::require nav
      fzx::nav goto music:artist --artist "$id" "${args[@]}"
      ;;
    albums | artist)
      fzx::require nav
      fzx::nav goto music:tracks --artist "${id%%"$MUSIC_US"*}" --album "${id#*"$MUSIC_US"}" "${args[@]}"
      ;;
    playlists)
      fzx::require nav
      fzx::nav goto music:tracks --playlist "$id"
      ;;
    tracks)
      [[ "$n" =~ ^[0-9]+$ ]] || n=0
      command mpc -q clear || return 0
      if [[ -n "$MUSIC_PLAYLIST" ]]; then
        command mpc -q load "$MUSIC_PLAYLIST"
      else
        music::album_songs "$MUSIC_ARTIST" "$MUSIC_ALBUM" | command cut -f1 | command mpc -q add
      fi && command mpc -q play "$((n + 1))"
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" music
  music::action "$@"
}
