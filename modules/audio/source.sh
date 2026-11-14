#!/usr/bin/env bash
# audio source, through pactl (PulseAudio or PipeWire's pulse server) and playerctl. Lines are
# "id<TAB>kind<TAB>display": the id is a sink's or source's name, a stream's index or a player's name.
# Mode from $FZX_MODE: sinks (outputs; `--move N`: where to move stream N), sources (inputs; monitors with
# the monitors toggle), streams (what plays, per application), players (MPRIS media players).

# audio::args [--move INDEX] [--]: AUDIO_MOVE, the stream the sinks list picks a new output for
audio::args() {
  declare -g AUDIO_MOVE=""
  while (($#)); do
    case "$1" in
      --move) AUDIO_MOVE="${2:-}" && shift 2 ;;
      --) shift; break ;;
      *) printf 'audio: unknown argument: %s\n' "$1" >&2; return 2 ;;
    esac
  done
}

# audio::json <sinks|sources|sink-inputs>: pactl's list as JSON
audio::json() {
  command pactl -f json list "$1"
}

# shellcheck disable=SC2016  # jq, not shell
# the jq functions: a device's or stream's volume (the channels' mean, in percent)
AUDIO_JQ='def vol: [.volume[]?.value_percent | rtrimstr("%") | tonumber] | if length == 0 then 0 else (add / length | round) end;
  def bar($p): ([($p + 5) / 10 | floor, 10] | min) as $n | ([range(0; $n)] | map("█") | join("")) + ([range($n; 10)] | map("░") | join(""));
  def pad($w): if length > $w then .[0:$w - 1] + "…" else . + ([range(0; $w - length)] | map(" ") | join("")) end;
  # cut in the middle: devices of one card share a long start and differ at the end ("... HDMI 3 Output")
  def padm($w): if length > $w then .[0:($w / 2 | floor)] + "…" + .[length - ($w - ($w / 2 | floor) - 1):] else pad($w) end;'

# audio::devices <sinks|sources>: the default marked, the description, the volume bar and percent, muted,
# the state; sources leave the outputs' monitors out (the default aside) unless the monitors toggle is on; with AUDIO_MOVE, the stream's
# current output is marked instead of the default
audio::devices() {
  local kind="$1" def monitors=false current=""
  local a=$'\e['"${FZX_COLORS[audio_default]:-1;38;5;114}m" m=$'\e['"${FZX_COLORS[audio_muted]:-38;5;203}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && a="" m="" d="" r=""
  [[ " ${FZX_TOGGLES:-} " == *" monitors "* ]] && monitors=true
  def="$(command pactl "get-default-${kind%s}" 2> /dev/null)"
  if [[ -n "$AUDIO_MOVE" && "$kind" == sinks ]]; then
    current="$(audio::json sink-inputs | command jq -r --argjson i "$AUDIO_MOVE" '.[] | select(.index == $i) | .sink')"
  fi
  audio::json "$kind" | command jq -r --arg def "$def" --arg cur "$current" --argjson mon "$monitors" \
    --arg a "$a" --arg m "$m" --arg d "$d" --arg r "$r" "$AUDIO_JQ"'
    # a monitor: PipeWire marks the class, PulseAudio names the sink (n/a when it is none); the default stays
    def monitor: (.properties["device.class"] // "") == "monitor" or ((.monitor_of_sink // "n/a") | tostring | . != "n/a" and . != "");
    .[] | select($mon or .name == $def or (monitor | not)) |
    (if $cur != "" then (.index | tostring) == $cur else .name == $def end) as $on | vol as $v |
    [.name, "device",
     ((if $on then $a + "● " else "  " end) + ((.description // .name) | padm(44)) + $r + " " +
      (if .mute then $m + bar($v) + " muted" + $r else bar($v) + " \($v)%" end) + "  " + $d + (.state | ascii_downcase) + $r)]
    | join("\t")'
}

# audio::streams: per playing stream, the application, what it plays, the output and the volume
audio::streams() {
  local m=$'\e['"${FZX_COLORS[audio_muted]:-38;5;203}m" n=$'\e['"${FZX_COLORS[audio_app]:-1;38;5;180}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && m="" n="" d="" r=""
  command jq -r -n --arg m "$m" --arg n "$n" --arg d "$d" --arg r "$r" \
    --slurpfile sinks <(audio::json sinks) --slurpfile inputs <(audio::json sink-inputs) "$AUDIO_JQ"'
    ($sinks[0] | map({key: (.index | tostring), value: (.description // .name)}) | from_entries) as $out |
    $inputs[0][] | vol as $v | .properties as $p |
    [(.index | tostring), "stream",
     ($n + (($p["application.name"] // $p["application.process.binary"] // "?") | pad(20)) + $r + " " +
      (($p["media.name"] // "") | gsub("[\t\r\n]+"; " ") | pad(30)) + " " +
      (if .mute then $m + bar($v) + " muted" + $r else bar($v) + " \($v)%" end) + "  " + $d + "→ " + ($out[.sink | tostring] // "?") + $r)]
    | join("\t")'
}

# audio::players: per MPRIS player, its state, the artist and title
audio::players() {
  local p status artist title icon a=$'\e['"${FZX_COLORS[audio_default]:-1;38;5;114}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' i_play i_pause i_stop
  [[ -n "${NO_COLOR:+x}" ]] && a="" d="" r=""
  command -v playerctl > /dev/null || { printf 'audio: players need playerctl\n' >&2; return 2; }
  fzx::require icons
  fzx::icon running i_play
  fzx::icon paused i_pause
  fzx::icon stopped i_stop
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    IFS=$'\t' read -r status artist title < <(command playerctl -p "$p" metadata \
      --format $'{{status}}\t{{artist}}\t{{title}}' 2> /dev/null || command playerctl -p "$p" status 2> /dev/null)
    case "$status" in
      Playing) icon="$a${i_play:-P}$r" ;;
      Paused) icon="${i_pause:-=}" ;;
      *) icon="$d${i_stop:-S}$r" ;;
    esac
    printf '%s\tplayer\t%s %-28s %s%s%s\n' "$p" "$icon" "$p" "$artist" "${artist:+${title:+ - }}" "$title"
  done < <(command playerctl -l 2> /dev/null)
}

audio::source() {
  audio::args "$@" || return
  case "${FZX_MODE:-sinks}" in
    sinks | sources)
      command -v pactl > /dev/null || { printf 'audio: needs pactl\n' >&2; return 2; }
      audio::devices "${FZX_MODE:-sinks}"
      ;;
    streams)
      command -v pactl > /dev/null || { printf 'audio: needs pactl\n' >&2; return 2; }
      audio::streams
      ;;
    players) audio::players ;;
    *)
      printf 'audio: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" audio
  audio::source "$@"
}
