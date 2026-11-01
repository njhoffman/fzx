#!/usr/bin/env bash
# audio preview: a device's description, state, volume per channel, port and bus, and for an output the
# streams playing to it; a stream's application, process and output; a player's track

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# audio::preview <id> <kind>
audio::preview() {
  local id="${1:-}" b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  [[ -n "$id" ]] || return 0
  case "${FZX_MODE:-sinks}" in
    sinks | sources)
      audio::json "${FZX_MODE:-sinks}" | command jq -r --arg id "$id" --arg b "$b" --arg d "$d" --arg r "$r" "$AUDIO_JQ"'
        def row(k; v): if (v // "") == "" then empty else "\($d)\(k)\($r)  \(v)" end;
        .[] | select(.name == $id) | .properties as $p |
        "\($b)\(.description // .name)\($r)", "",
        row("state  "; .state | ascii_downcase), row("volume "; "\(vol)%\(if .mute then " (muted)" else "" end)"),
        row("channel"; [.volume | to_entries[] | "\(.key) \(.value.value_percent)"] | join(", ")),
        row("port   "; .active_port), row("bus    "; $p["device.bus"]), row("codec  "; $p["api.bluez5.codec"]),
        row("format "; .sample_specification), row("name   "; .name), row("index  "; .index)'
      if [[ "${FZX_MODE:-sinks}" == sinks ]]; then
        command jq -r -n --arg id "$id" --arg d "$d" --arg r "$r" \
          --slurpfile sinks <(audio::json sinks) --slurpfile inputs <(audio::json sink-inputs) "$AUDIO_JQ"'
          ($sinks[0][] | select(.name == $id) | .index) as $i |
          [$inputs[0][] | select(.sink == $i)] |
          if length == 0 then "", "\($d)nothing playing here\($r)" else "", "\($d)playing here\($r)",
            (.[] | .properties as $p | "  \($p["application.name"] // $p["application.process.binary"] // "?")  \(($p["media.name"] // "") | gsub("[\t\r\n]+"; " "))  \($d)\(vol)%\($r)") end'
      fi
      ;;
    streams)
      command jq -r -n --arg id "$id" --arg b "$b" --arg d "$d" --arg r "$r" \
        --slurpfile sinks <(audio::json sinks) --slurpfile inputs <(audio::json sink-inputs) "$AUDIO_JQ"'
        def row(k; v): if (v // "") == "" then empty else "\($d)\(k)\($r)  \(v)" end;
        ($sinks[0] | map({key: (.index | tostring), value: (.description // .name)}) | from_entries) as $out |
        $inputs[0][] | select((.index | tostring) == $id) | .properties as $p |
        "\($b)\($p["application.name"] // $p["application.process.binary"] // "?")\($r)", (($p["media.name"] // "") | gsub("[\t\r\n]+"; " ")), "",
        row("output "; $out[.sink | tostring]), row("volume "; "\(vol)%\(if .mute then " (muted)" else "" end)"),
        row("process"; [$p["application.process.binary"], $p["application.process.id"]] | map(select(. != null)) | join(" ")),
        row("format "; .sample_specification), row("index  "; .index), "",
        "\($d)enter: move it to another output\($r)"'
      ;;
    players)
      command playerctl -p "$id" metadata --format \
        "${b}{{title}}${r}"$'\n'"{{artist}}"$'\n'"${d}{{album}}${r}"$'\n\n'"${d}status${r}    {{status}}"$'\n'"${d}position${r}  {{duration(position)}} / {{duration(mpris:length)}}"$'\n'"${d}volume${r}    {{volume}}"$'\n'"${d}player${r}    {{playerName}}" 2> /dev/null ||
        printf '%s\n\n%sno track%s\n' "$id" "$d" "$r"
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" audio
  audio::preview "$@"
}
