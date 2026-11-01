#!/usr/bin/env bash
# audio menu entries, where pactl (and for players playerctl) is installed

audio::manifest() {
  fzx::entry audio "Audio outputs"
  fzx::entry audio:sources "Audio inputs"
  fzx::entry audio:streams "What is playing, and where"
  fzx::entry audio:players "Media players"
}

audio::applicable() {
  case "$1" in
    audio:players) command -v playerctl > /dev/null ;;
    *) command -v pactl > /dev/null && command pactl info > /dev/null 2>&1 ;;
  esac
}

# audio::summary <target>: the default output or input, how many streams, what plays
audio::summary() {
  case "$1" in
    audio) command pactl -f json list sinks 2> /dev/null | command jq -r --arg d "$(command pactl get-default-sink 2> /dev/null)" '.[] | select(.name == $d) | .description // .name' ;;
    audio:sources) command pactl -f json list sources 2> /dev/null | command jq -r --arg d "$(command pactl get-default-source 2> /dev/null)" '.[] | select(.name == $d) | .description // .name' ;;
    audio:streams) command pactl -f json list sink-inputs 2> /dev/null | command jq -r 'length | "\(.) playing"' ;;
    audio:players) command playerctl metadata --format '{{status}}: {{artist}} - {{title}}' 2> /dev/null ;;
  esac
}
