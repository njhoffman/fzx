#!/usr/bin/env bash
# audio actions on the selected rows' ids (sink or source names, stream indexes, player names), by mode, and
# the enter transform

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# audio::pactl_kind: the pactl object of the mode's rows: sink, source or sink-input
audio::pactl_kind() {
  case "${FZX_MODE:-sinks}" in
    sources) echo source ;;
    streams) echo sink-input ;;
    *) echo sink ;;
  esac
}

# audio::action <up|down|mute|next|previous> [module args...] -- <ids...>
#   up, down: sinks, sources and streams by FZX_AUDIO_STEP (at most 100%, or FZX_AUDIO_MAX); players by
#             the same step through playerctl
#   mute:     toggle (players: play or pause)
#   next, previous: players' tracks
audio::action() {
  local action="${1:-}" id kind step="${FZX_AUDIO_STEP:-5}" rc=0 frac
  shift
  while (($#)) && [[ "$1" != -- ]]; do shift; done
  (($#)) && shift
  kind="$(audio::pactl_kind)"
  # playerctl takes a fraction: 5 -> 0.05
  printf -v frac '%d.%02d' $((step / 100)) $((step % 100))
  for id; do
    [[ -n "$id" ]] || continue
    if [[ "${FZX_MODE:-sinks}" == players ]]; then
      case "$action" in
        up) command playerctl -p "$id" volume "$frac+" ;;
        down) command playerctl -p "$id" volume "$frac-" ;;
        mute) command playerctl -p "$id" play-pause ;;
        next | previous) command playerctl -p "$id" "$action" ;;
        *) printf 'audio: unknown action: %s\n' "$action" >&2; return 2 ;;
      esac || rc=$?
      continue
    fi
    case "$action" in
      up) audio::volume_up "$kind" "$id" "$step" ;;
      down) command pactl "set-$kind-volume" "$id" "-$step%" ;;
      mute) command pactl "set-$kind-mute" "$id" toggle ;;
      next | previous) ;;
      *) printf 'audio: unknown action: %s\n' "$action" >&2; return 2 ;;
    esac || rc=$?
  done
  return "$rc"
}

# audio::volume_up <kind> <id> <step>: up by the step, no higher than FZX_AUDIO_MAX (pactl would go past 100%)
audio::volume_up() {
  local list=sinks cur max="${FZX_AUDIO_MAX:-100}"
  case "$1" in source) list=sources ;; sink-input) list=sink-inputs ;; esac
  cur="$(audio::json "$list" | command jq -r --arg id "$2" "$AUDIO_JQ"'.[] | select(.name == $id or (.index | tostring) == $id) | vol')"
  [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
  ((cur + $3 > max)) && { command pactl "set-$1-volume" "$2" "$max%"; return; }
  command pactl "set-$1-volume" "$2" "+$3%"
}

# audio::transform enter [module args...] -- <id>: sinks and sources: make the row the default (sinks with
# --move N: move stream N there and go back); streams: pick its new output (sinks --move N, a child
# session); players: play or pause. Every one but the move reloads the list
audio::transform() {
  local name="${1:-}" id
  shift
  audio::args "$@" 2> /dev/null || :
  while (($#)) && [[ "$1" != -- ]]; do shift; done
  (($#)) && shift
  id="${1:-}"
  [[ "$name" == enter && -n "$id" ]] || return 0
  fzx::require opts
  local reload
  fzx::reload_action "$(fzx::cb source)" reload
  case "${FZX_MODE:-sinks}" in
    sinks | sources)
      if [[ -n "$AUDIO_MOVE" ]]; then
        # back in the streams list, which is read again (FZX_PERSIST=none) and shows the new output
        command pactl move-sink-input "$AUDIO_MOVE" "$id" || return 0
        fzx::require nav
        fzx::nav back
        return
      fi
      command pactl "set-default-${FZX_MODE%s}" "$id" || return 0
      printf '%s' "$reload"
      ;;
    streams)
      fzx::require nav
      fzx::nav goto audio:sinks --move "$id"
      ;;
    players)
      command playerctl -p "$id" play-pause
      printf '%s' "$reload"
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" audio
  audio::action "$@"
}
