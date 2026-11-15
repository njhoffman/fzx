#!/usr/bin/env bash
# music: MPD's queue, artists, albums and playlists through mpc. `fzx -m music[:artists|:albums|:playlists]`,
# `fzx -m music:artist --artist A`, `fzx -m music:tracks --artist A --album B | --playlist P`. Enter plays a
# queued song, opens an artist's albums, an album's or a playlist's songs (each a child session: back
# returns), or plays an album or playlist from the song under the cursor; alt-enter plays the selection,
# alt-a adds it, alt-i plays it next. With musicman (smart.sh): `fzx -m music:smart`, its smart playlists, and
# side trips: alt-enter in the library modes remembers what played, alt-B goes back, and the header shows
# the back point.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS: read by lib/actions.sh
music::opts() {
  music::args "${FZX_ARGS[@]}" || return
  local a=""
  ((${#FZX_ARGS[@]})) && printf -v a '%q ' "${FZX_ARGS[@]}"
  a+="--"
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=4
    --accept-nth=3
    --tiebreak=index
    --multi
    --preview "$(fzx::cb preview "$a" '{1}' '{2}' '{3}')"
    "--preview-window=right,45%,nohidden"
  )
  FZX_ACTION_ARGS="$a {+1}"
  FZX_ACTION_ARGS_FOR['copy']='{+3}'
  # the songs' files, not the queue positions
  FZX_ACTION_ARGS_FOR['rate']="$a {+3}"
  FZX_ACTION_ARGS_FOR['tags']="$a {+3}"
  # smart: the query is the new preset's terms (the queue's save takes nothing)
  FZX_ACTION_ARGS_FOR['save']="$a {q}"
  local header enter="queue: play the song; artists: their albums; albums, playlists: their songs; songs: play from here"
  music::header header
  [[ -n "$header" ]] && FZX_OPTS+=("--header=$header")
  if fzx::in_session; then
    if music::mm_on; then
      enter+="; smart: play it as the main list (forgets the back point)"
      # the back point under the header, read again after every load (a play or back reloads)
      FZX_OPTS+=(--bind "load:+transform:$(fzx::cb transform header "$a")")
    fi
    fzx::bind enter "transform:$(fzx::cb transform enter "$a" '{1}' '{n}')" "$enter"
  fi
}

fzx::module_main "$@"
