#!/usr/bin/env bash
# youtube: search YouTube with yt-dlp; play, open or save the results as mp3. `fzx -m youtube [--query Q]`.
# Typing does not filter: enter runs the search (a new query) or prints the video's url (the same query).
# With an empty query the list holds the recent searches; enter on one runs it again. alt-F lists a video's
# formats (youtube:formats --url URL, a child session), where enter downloads the selected ones.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

youtube::opts() {
  if [[ "$FZX_MODE" == formats ]]; then
    FZX_OPTS+=(
      --delimiter=$'\t'
      --with-nth=7
      --accept-nth=2
      --tiebreak=index
      "--header=enter downloads; a video and an audio format selected together are merged"
      --preview "$(fzx::cb preview '{1}' '{2}' '{3}' '{4}' '{5}' '{6}')"
      "--preview-window=right,45%,wrap,nohidden"
    )
    # shellcheck disable=SC2034  # read by lib/actions.sh
    FZX_ACTION_ARGS_FOR['download']='{1} {+2}'
    fzx::bind enter "execute($(fzx::cb action download '{1}' '{+2}'))" "download the selected formats"
    return 0
  fi
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=7
    --accept-nth=1
    --disabled
    --tiebreak=index
    "--header=type a search, enter runs it"
    --preview "$(fzx::cb preview '{1}' '{2}' '{3}' '{4}' '{5}' '{6}')"
    "--preview-window=right,45%,wrap,nohidden"
  )
  if fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb transform enter '{1}' '{2}')" \
      "search for the query, or print the video's url"
    fzx::bind "${FZX_KEYS[youtube.formats]}" "transform:$(fzx::cb transform formats '{1}')" \
      "the video's formats, to download one"
  else
    # standalone has no transform callback: search as you type, once typing pauses
    FZX_OPTS+=(--bind "change:reload:sleep 0.5; $(fzx::cb source)")
  fi
}

fzx::module_main "$@"
