#!/usr/bin/env bash
# youtube: search YouTube with yt-dlp; play, open or save the results as mp3. `fzx -m youtube [--query Q]`.
# Typing does not filter: enter runs the search (a new query) or prints the video's url (the same query).
# With an empty query the list holds the recent searches; enter on one runs it again.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

youtube::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=7
    --accept-nth=1
    --disabled
    --no-sort
    "--header=type a search, enter runs it"
    --preview "$(fzx::cb preview '{1}' '{2}' '{3}' '{4}' '{5}' '{6}')"
    "--preview-window=right,45%,wrap,nohidden"
  )
  if fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb transform enter '{1}' '{2}')" \
      "search for the query, or print the video's url"
  else
    # standalone has no transform callback: search as you type, once typing pauses
    FZX_OPTS+=(--bind "change:reload:sleep 0.5; $(fzx::cb source)")
  fi
}

fzx::module_main "$@"
