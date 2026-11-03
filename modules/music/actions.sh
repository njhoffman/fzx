#!/usr/bin/env bash
# music actions on the selected rows' ids (queue positions, artists, "artist<US>album" keys, playlists,
# files), by mode, and the enter transform

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

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
music::action() {
  local action="${1:-}" files=() i name
  shift
  music::args "$@" 2> /dev/null || :
  while (($#)) && [[ "$1" != -- ]]; do shift; done
  (($#)) && shift
  case "$action" in
    play)
      if [[ "${FZX_MODE:-queue}" == queue ]]; then
        [[ -n "${1:-}" ]] || return 0
        command mpc -q play "$1"
        return
      fi
      mapfile -t files < <(music::files "$@")
      ((${#files[@]})) || { printf 'music: nothing to play\n' >&2; return 1; }
      command mpc -q clear && printf '%s\n' "${files[@]}" | command mpc -q add && command mpc -q play
      ;;
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
      read -r -e -p "save the queue as playlist: " name || return 0
      [[ -n "$name" ]] || return 0
      command mpc -q save "$name"
      ;;
    pause) command mpc -q toggle ;;
    next) command mpc -q next ;;
    previous) command mpc -q prev ;;
    *) printf 'music: unknown action: %s\n' "$action" >&2; return 2 ;;
  esac
}

# music::transform enter [module args...] -- <id> <index>: queue: play the song; artists: a child session
# with their albums; albums: one with the album's songs; playlists: one with its songs; songs of an album
# or a playlist: the queue becomes the album or playlist, played from the song (index: fzf's {n})
music::transform() {
  local name="${1:-}" id n args=()
  shift
  music::args "$@" 2> /dev/null || :
  while (($#)) && [[ "$1" != -- ]]; do shift; done
  (($#)) && shift
  id="${1:-}" n="${2:-0}"
  [[ "$name" == enter && -n "$id" ]] || return 0
  [[ "$MUSIC_TAG" == artist ]] && args=(--tag artist)
  case "${FZX_MODE:-queue}" in
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
