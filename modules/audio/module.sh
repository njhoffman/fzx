#!/usr/bin/env bash
# audio: outputs, inputs, playing streams and media players. `fzx -m audio[:sources|:streams|:players]`.
# Enter makes a device the default, moves a stream (to the output picked next) or plays and pauses a player;
# alt-up and alt-down change the volume, alt-m mutes.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS: read by lib/actions.sh
audio::opts() {
  audio::args "${FZX_ARGS[@]}" || return
  local a="" what
  ((${#FZX_ARGS[@]})) && printf -v a '%q ' "${FZX_ARGS[@]}"
  a+="--"
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{2}')"
    "--preview-window=right,40%,nohidden"
  )
  FZX_ACTION_ARGS="$a {+1}"
  if [[ -n "$AUDIO_MOVE" ]]; then
    what="$(audio::json sink-inputs 2> /dev/null | command jq -r --argjson i "$AUDIO_MOVE" \
      '.[] | select(.index == $i) | .properties["application.name"] // empty' 2> /dev/null)"
    FZX_OPTS+=("--header=move ${what:-stream $AUDIO_MOVE} to: enter picks the output")
  fi
  if fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb transform enter "$a" '{1}')" \
      "sinks, sources: make it the default; streams: move it to another output; players: play or pause"
  fi
}

fzx::module_main "$@"
