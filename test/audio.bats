#!/usr/bin/env bats
# the audio module against a stub pactl (two sinks, a source and its monitor, two streams) and playerctl

load test_helper

AUDIO="$(readlink -f "$BATS_TEST_DIRNAME/../modules/audio")"

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  # pactl: lists from fixtures, every other call logged to pactl.calls
  cat > "$STUBS/pactl" << 'STUB'
#!/usr/bin/env bash
[[ "$1" == -f ]] && shift 2
case "$1 ${2:-}" in
  "list sinks") cat "$BATS_TEST_TMPDIR/sinks.json" ;;
  "list sources") cat "$BATS_TEST_TMPDIR/sources.json" ;;
  "list sink-inputs") cat "$BATS_TEST_TMPDIR/inputs.json" ;;
  "get-default-sink ") echo bluez_output.speaker ;;
  "get-default-source ") echo alsa_input.mic ;;
  "info ") echo "Server Name: PulseAudio (on PipeWire 1.4.7)" ;;
  *) echo "$*" >> "$BATS_TEST_TMPDIR/pactl.calls" ;;
esac
STUB
  cat > "$STUBS/playerctl" << 'STUB'
#!/usr/bin/env bash
case "$*" in
  "-l") printf 'spotify\nchromium.instance1\n' ;;
  "-p spotify metadata --format "*$'\t'*) printf 'Playing\tNine Inch Nails\tFind My Way\n' ;;
  "-p chromium.instance1 metadata --format "*$'\t'*) exit 1 ;;
  "-p chromium.instance1 status") echo Paused ;;
  "-p spotify metadata --format "*) echo "Find My Way by Nine Inch Nails" ;;
  "metadata --format "*) echo "Playing: Nine Inch Nails - Find My Way" ;;
  *) echo "$*" >> "$BATS_TEST_TMPDIR/playerctl.calls" ;;
esac
STUB
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
  cat > "$BATS_TEST_TMPDIR/sinks.json" << 'JSON'
[{"index":55,"name":"alsa_output.hdmi","description":"HDMI Output","state":"SUSPENDED","mute":false,
  "volume":{"front-left":{"value_percent":"100%"},"front-right":{"value_percent":"100%"}},"active_port":"hdmi-output-0",
  "sample_specification":"s24-32le 2ch 48000Hz","monitor_source":"alsa_output.hdmi.monitor","properties":{"device.bus":"pci"}},
 {"index":79,"name":"bluez_output.speaker","description":"Bose Revolve+ II SoundLink","state":"RUNNING","mute":true,
  "volume":{"front-left":{"value_percent":"40%"},"front-right":{"value_percent":"42%"}},"active_port":"speaker-output",
  "sample_specification":"s16le 2ch 48000Hz","monitor_source":"bluez_output.speaker.monitor",
  "properties":{"device.bus":"bluetooth","api.bluez5.codec":"sbc"}}]
JSON
  cat > "$BATS_TEST_TMPDIR/sources.json" << 'JSON'
[{"index":59,"name":"alsa_input.mic","description":"Microphone","state":"IDLE","mute":false,"monitor_of_sink":null,
  "volume":{"mono":{"value_percent":"49%"}},"properties":{"device.class":"sound"}},
 {"index":80,"name":"bluez_output.speaker.monitor","description":"Monitor of Bose","state":"IDLE","mute":false,
  "monitor_of_sink":null,"volume":{"mono":{"value_percent":"100%"}},"properties":{"device.class":"monitor"}},
 {"index":81,"name":"alsa_output.hdmi.monitor","description":"Monitor of HDMI","state":"IDLE","mute":false,
  "monitor_of_sink":"alsa_output.hdmi","volume":{"mono":{"value_percent":"100%"}},"properties":{}}]
JSON
  cat > "$BATS_TEST_TMPDIR/inputs.json" << 'JSON'
[{"index":816,"sink":79,"mute":false,"volume":{"front-left":{"value_percent":"100%"},"front-right":{"value_percent":"100%"}},
  "sample_specification":"float32le 2ch 44100Hz",
  "properties":{"application.name":"spotify","media.name":"Spotify","application.process.binary":"spotify","application.process.id":"2256"}},
 {"index":900,"sink":55,"mute":true,"volume":{"mono":{"value_percent":"30%"}},
  "properties":{"application.process.binary":"mpv","media.name":"a\tvideo.mkv"}}]
JSON
}

src() { FZX_MODE="$1" "$AUDIO/source.sh" "${@:2}"; }

@test "sinks: the default marked, description, volume bar and percent, muted, state" {
  run src sinks
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == $'alsa_output.hdmi\tdevice\t  HDMI Output '*" ██████████ 100%  suspended" ]]
  # the mean of the channels, rounded: 41
  [[ "${lines[1]}" == $'bluez_output.speaker\tdevice\t● Bose Revolve+ II SoundLink '*" ████░░░░░░ muted  running" ]]
  # a long description is cut in the middle, keeping the end that tells a card's outputs apart
  sed -i 's/"HDMI Output"/"Tiger Lake-LP Smart Sound Technology Audio Controller HDMI 3 Output"/' "$BATS_TEST_TMPDIR/sinks.json"
  run src sinks
  [[ "${lines[0]}" == *$'\t  Tiger Lake-LP Smart So…troller HDMI 3 Output ██'* ]]
}

@test "sources: monitors (PipeWire's class, PulseAudio's monitor_of_sink) only with the toggle, the default kept" {
  run src sources
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == $'alsa_input.mic\tdevice\t● Microphone '*" █████░░░░░ 49%  idle" ]]
  FZX_TOGGLES=monitors run src sources
  [ "${#lines[@]}" -eq 3 ]
  # a monitor that is the default stays
  sed -i 's/echo alsa_input.mic/echo alsa_output.hdmi.monitor/' "$STUBS/pactl"
  run src sources
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "alsa_input.mic alsa_output.hdmi.monitor " ]
}

@test "streams: application, what it plays, volume and output; a missing name falls back to the binary" {
  run src streams
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == $'816\tstream\tspotify '*" Spotify "*" ██████████ 100%  → Bose Revolve+ II SoundLink" ]]
  [[ "${lines[1]}" == $'900\tstream\tmpv '*" a video.mkv "*" muted  → HDMI Output" ]]
}

@test "sinks --move: the stream's current output marked instead of the default" {
  run src sinks --move 900
  [[ "${lines[0]}" == $'alsa_output.hdmi\tdevice\t● '* ]]
  [[ "${lines[1]}" == $'bluez_output.speaker\tdevice\t  '* ]]
}

@test "players: the state, the player, artist and title; one without a track" {
  run src players
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = $'spotify\tplayer\tP spotify                      Nine Inch Nails - Find My Way' ]
  [[ "${lines[1]}" == $'chromium.instance1\tplayer\t= chromium.instance1'* ]]
}

@test "preview: a device's details and what plays there; a stream; a player" {
  FZX_MODE=sinks run "$AUDIO/preview.sh" bluez_output.speaker device
  [ "${lines[0]}" = "Bose Revolve+ II SoundLink" ]
  [[ "$output" == *"volume   41% (muted)"* && "$output" == *"channel  front-left 40%, front-right 42%"* ]]
  [[ "$output" == *"codec    sbc"* && "$output" == *$'playing here\n  spotify  Spotify  100%'* ]]
  FZX_MODE=sinks run "$AUDIO/preview.sh" alsa_output.hdmi device
  [[ "$output" == *$'playing here\n  mpv  a video.mkv  30%' ]]
  FZX_MODE=streams run "$AUDIO/preview.sh" 816 stream
  [ "${lines[0]}" = spotify ]
  [[ "$output" == *"output   Bose Revolve+ II SoundLink"* && "$output" == *"process  spotify 2256"* ]]
  FZX_MODE=players run "$AUDIO/preview.sh" spotify player
  [ "$output" = "Find My Way by Nine Inch Nails" ]
}

@test "actions: volume up (capped), down and mute by mode; players' tracks and volume" {
  FZX_MODE=sinks "$AUDIO/actions.sh" up -- bluez_output.speaker
  FZX_MODE=sinks "$AUDIO/actions.sh" up -- alsa_output.hdmi
  FZX_MODE=sources "$AUDIO/actions.sh" down -- alsa_input.mic
  FZX_MODE=streams "$AUDIO/actions.sh" mute -- 816 900
  [ "$(cat "$BATS_TEST_TMPDIR/pactl.calls")" = "set-sink-volume bluez_output.speaker +5%
set-sink-volume alsa_output.hdmi 100%
set-source-volume alsa_input.mic -5%
set-sink-input-mute 816 toggle
set-sink-input-mute 900 toggle" ]
  FZX_MODE=players FZX_AUDIO_STEP=10 "$AUDIO/actions.sh" up -- spotify
  FZX_MODE=players "$AUDIO/actions.sh" next -- spotify
  FZX_MODE=players "$AUDIO/actions.sh" mute -- spotify
  [ "$(cat "$BATS_TEST_TMPDIR/playerctl.calls")" = "-p spotify volume 0.10+
-p spotify next
-p spotify play-pause" ]
  FZX_MODE=sinks run "$AUDIO/actions.sh" bogus -- x
  [ "$status" -eq 2 ]
}

@test "under fzx: enter sets the default and reloads; a stream picks its output in a child; the move goes back" {
  load_libs log session
  fzx::session_create audio "$AUDIO"
  fzx::state_set mode sinks
  run "$FZX" _cb transform enter -- alsa_output.hdmi
  [[ "$output" == *"reload("*"_cb source)" ]]
  grep -qx 'set-default-sink alsa_output.hdmi' "$BATS_TEST_TMPDIR/pactl.calls"
  fzx::state_set mode streams
  run "$FZX" _cb transform enter -- 816
  [[ "$output" == "become:"*" -m :sinks" ]]
  local parent="$FZX_SESSION" child="${output##*--resume }" args=()
  child="${child%% *}"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${args[*]}" = "--move 816" ]
  # (the launch writes the child's modes; this one was never launched)
  printf sinks > "$FZX_RUNTIME_DIR/sessions/$child/state/mode"
  FZX_SESSION="$child" run "$FZX" _cb transform enter --move 816 -- alsa_output.hdmi
  grep -qx 'move-sink-input 816 alsa_output.hdmi' "$BATS_TEST_TMPDIR/pactl.calls"
  [[ "$output" == "become:"*"--resume $parent"* ]]
  fzx::state_set mode players
  run "$FZX" _cb transform enter -- spotify
  [[ "$output" == *"reload("* ]]
  grep -qx -- '-p spotify play-pause' "$BATS_TEST_TMPDIR/playerctl.calls"
  stub_fzf
  run "$FZX" -m audio:sinks --move 816
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=move spotify to: enter picks the output "* ]]
  [[ "$(fzf_bind alt-up)" == *"_cb action up --move 816 -- {+1}"* ]]
}

@test "menu: four entries; players only with playerctl; summaries" {
  source "$AUDIO/manifest.sh"
  audio::applicable audio
  audio::applicable audio:players
  [ "$(audio::summary audio)" = "Bose Revolve+ II SoundLink" ]
  [ "$(audio::summary audio:sources)" = "Microphone" ]
  [ "$(audio::summary audio:streams)" = "2 playing" ]
  [ "$(audio::summary audio:players)" = "Playing: Nine Inch Nails - Find My Way" ]
}
