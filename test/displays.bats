#!/usr/bin/env bats
# the displays module against stub xrandr and displayd (their calls logged): outputs, modes, profiles

load test_helper

DSP="$(readlink -f "$BATS_TEST_DIRNAME/../modules/displays")"

setup() {
  setup_fzx
  export NO_COLOR=1 CALLS="$BATS_TEST_TMPDIR/calls" FZX_TTY="$BATS_TEST_TMPDIR/tty" DISPLAY=:9
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdgconf" XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdgstate"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$XDG_CONFIG_HOME/displayd" "$XDG_STATE_HOME/displayd"
  : > "$FZX_TTY"
  # eDP-1 connected and off, DP-3 on and primary at 100 Hz (60.00 listed twice), DP-1 disconnected
  cat > "$BATS_TEST_TMPDIR/xrandr.out" << 'OUT'
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
eDP-1 connected (normal left inverted right x axis y axis)
   1920x1080     60.02 +  48.00
   1280x720      60.02
DP-1 disconnected (normal left inverted right x axis y axis)
DP-3 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 522mm x 294mm
   1920x1080    100.00*  75.00    60.00 +  60.00
   1280x1024     75.02
OUT
  cat > "$BATS_TEST_TMPDIR/bin/xrandr" << 'STUB'
#!/usr/bin/env bash
printf 'xrandr %s\n' "$*" >> "$CALLS"
[[ "$1" == --query ]] && cat "$BATS_TEST_TMPDIR/xrandr.out"
exit 0
STUB
  cat > "$BATS_TEST_TMPDIR/bin/displayd" << 'STUB'
#!/usr/bin/env bash
printf 'displayd %s\n' "$*" >> "$CALLS"
case "$1" in
  monitors) printf 'eDP-1    286379f919bb   internal  off        LGD 061f\nDP-3     4ffd762d8a7b   external  1920x1080  XEC ES-24C1\n' ;;
  list) printf '   desk  [config]\n*+ External only (laptop off): XEC ES-24C1 1920x1080  [saved]\n   SYN only: SYN 1920x1080  [saved]\n' ;;
  status) printf 'applied   External only (laptop off): XEC ES-24C1 1920x1080 (default)\ndaemon    %s\n' "${DAEMON:-running}" ;;
esac
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

src() { FZX_MODE="$1" "$DSP/source.sh" "${@:2}"; }

@test "outputs: on first with mode, rate, position and displayd's name, then off; all adds the disconnected" {
  run src outputs
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = $'DP-3\ton\t● DP-3     XEC ES-24C1            1920x1080@100.00 +0+0  primary' ]
  [ "${lines[1]}" = $'eDP-1\toff\t○ eDP-1    LGD 061f               off (preferred 1920x1080)' ]
  FZX_TOGGLES=all run src outputs
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[2]}" == $'DP-1\tdisconnected\t'*disconnected ]]
}

@test "outputs: without displayd, xrandr's names alone" {
  FZX_DISPLAYS_DISPLAYD=no-displayd run src outputs
  [[ "${lines[0]}" == $'DP-3\ton\t● DP-3                            1920x1080@100.00'* ]]
}

@test "modes: an output's modes and rates, each once, the one on screen and the preferred marked" {
  run src modes --output DP-3
  [ "${#lines[@]}" -eq 4 ]
  [[ "${lines[0]}" == $'1920x1080\t100.00\t'*"on screen"* ]]
  [[ "${lines[2]}" == $'1920x1080\t60.00\t'*"preferred"* ]]
  [[ "${lines[3]}" == $'1280x1024\t75.02\t'* ]]
  run src modes
  [ "$status" -eq 2 ]
}

@test "profiles: displayd's list, the default here marked" {
  run src profiles
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == $'desk\tconfig\t'* ]]
  [[ "${lines[1]}" == $'External only (laptop off): XEC ES-24C1 1920x1080\tsaved\t'*"default here" ]]
}

@test "power: off while another output is on, on right of one that is on; the last one on stays on" {
  "$DSP/actions.sh" power eDP-1
  grep -qx 'xrandr --output eDP-1 --auto --right-of DP-3' "$CALLS"
  run "$DSP/actions.sh" power DP-3
  [ "$status" -eq 1 ]
  [[ "$output" == *"DP-3 is the only output on"* ]]
  run grep -c -- '--off' "$CALLS"
  [ "$output" = 0 ]
  run "$DSP/actions.sh" power DP-1
  [ "$status" -eq 1 ] && [[ "$output" == *"not connected"* ]]
}

@test "place and rotate ask on the terminal; another key cancels" {
  printf 'l' > "$FZX_TTY"
  "$DSP/actions.sh" place eDP-1
  grep -qx 'xrandr --output eDP-1 --auto --left-of DP-3' "$CALLS"
  printf 'i' > "$FZX_TTY"
  "$DSP/actions.sh" rotate DP-3
  grep -qx 'xrandr --output DP-3 --rotate inverted' "$CALLS"
  : > "$CALLS"
  printf 'q' > "$FZX_TTY"
  "$DSP/actions.sh" rotate DP-3
  run grep -c -- '--rotate' "$CALLS"
  [ "$output" = 0 ]
}

@test "set, primary and the displayd actions run what they say" {
  "$DSP/actions.sh" set DP-3 1920x1080 75.00
  "$DSP/actions.sh" primary eDP-1
  "$DSP/actions.sh" apply desk
  "$DSP/actions.sh" default desk
  "$DSP/actions.sh" rescue
  run "$DSP/actions.sh" daemon
  [ "$output" = "displayd stopped (until start or the next login)" ]
  DAEMON=stopped run "$DSP/actions.sh" daemon
  [ "$output" = "displayd started" ]
  run grep -v -e ' --query' -e ' status' -e ' monitors' "$CALLS"
  [ "$output" = "xrandr --output DP-3 --mode 1920x1080 --rate 75.00
xrandr --output eDP-1 --primary
displayd apply desk
displayd default desk
displayd rescue
displayd stop
displayd start" ]
}

@test "preview: an output's state, monitor and modes; a profile's config table or saved layout" {
  FZX_MODE=outputs run "$DSP/preview.sh" DP-3
  [ "${lines[0]}" = "DP-3  XEC ES-24C1" ]
  [[ "$output" == *"fingerprint  4ffd762d8a7b"* && "$output" == *"1920x1080 at 100.00 Hz, at +0+0, primary"* ]]
  [[ "$output" == *"modes (4; enter lists them all)"* ]]
  printf '[general]\nx = 1\n[profiles.desk]\n[profiles.desk.outputs.DP-3]\nmode = "1920x1080"\n[profiles.other]\ny = 2\n' \
    > "$XDG_CONFIG_HOME/displayd/config.toml"
  FZX_MODE=profiles run "$DSP/preview.sh" desk config
  [[ "$output" == *'[profiles.desk.outputs.DP-3]'*'mode = "1920x1080"'* && "$output" != *other* && "$output" != *general* ]]
  command -v jq > /dev/null || return 0
  printf '{"layouts": {"SYN only: SYN 1920x1080": {"outputs": {"DP-3": {"mode": "1920x1080"}}}}}' \
    > "$XDG_STATE_HOME/displayd/state.json"
  FZX_MODE=profiles run "$DSP/preview.sh" "SYN only: SYN 1920x1080" saved
  [[ "$output" == *'"mode": "1920x1080"'* ]]
}

@test "under fzx: enter lists an output's modes, sets a mode, applies a profile; the header is displayd's" {
  stub_fzf
  run "$FZX" -m displays
  [ "$(fzf_bind enter)" = "enter:transform:$FZX _cb nav goto displays:modes --output {1}" ]
  [[ "$(fzf_flag --header 2> /dev/null || true)$(read_fzf_args; printf '%s\n' "${FZF_ARGS[@]}")" == *"--header=displayd: External only (laptop off): XEC ES-24C1 1920x1080 (default)  (daemon running)"* ]]
  run "$FZX" -m displays:modes --output DP-3
  [ "$(fzf_bind enter)" = "enter:execute-silent($FZX _cb action set DP-3 {1} {2})+reload($FZX _cb source)" ] ||
    [[ "$(fzf_bind enter)" == "enter:transform($FZX _cb notify set DP-3 {1} {2})"* ]]
  run "$FZX" -m displays:profiles
  [[ "$(fzf_bind enter)" == *"_cb notify apply {1}"* ]]
}

@test "menu: applicable under X with xrandr; profiles with displayd; the summaries" {
  load_libs log
  source "$DSP/manifest.sh"
  displays::applicable displays
  displays::applicable displays:profiles
  DISPLAY="" run displays::applicable displays
  [ "$status" -ne 0 ]
  [ "$(displays::summary displays)" = "2 connected; on: DP-3 1920x1080" ]
  [ "$(displays::summary displays:profiles)" = "3 profiles, default: External only (laptop off): XEC ES-24C1 1920x1080" ]
  FZX_DISPLAYS_DISPLAYD=no-displayd run displays::applicable displays:profiles
  [ "$status" -ne 0 ]
}

@test "components: every row has its five fields (two blanks or a tab between them), with displayd and without" {
  local bad
  bad="$("$DSP/components.tsv" | grep -v '^#' | awk -F'  +|\t' 'NF != 5')"
  [ -z "$bad" ] || { printf 'rows without five fields:\n%s\n' "$bad"; return 1; }
  FZX_DISPLAYS_DISPLAYD=no-displayd run "$DSP/components.tsv"
  [[ "$output" != *profiles* && "$output" != *rescue* && "$output" == *power* ]]
}
