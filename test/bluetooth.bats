#!/usr/bin/env bats
# the bluetooth module against a stub busctl (bluez's object tree from a fixture) and bluetoothctl

load test_helper

BT="$(readlink -f "$BATS_TEST_DIRNAME/../modules/bluetooth")"

setup() {
  setup_fzx
  load_libs # manifests run under the menu, with core (fzx::plural) loaded
  export NO_COLOR=1 FZX_ICONS=none
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  cat > "$STUBS/busctl" << 'STUB'
#!/usr/bin/env bash
[[ -f "$BATS_TEST_TMPDIR/nobluez" ]] && { echo "Call failed: The name org.bluez was not provided" >&2; exit 1; }
cat "$BATS_TEST_TMPDIR/objects.json"
STUB
  # bluetoothctl: info and show from fixtures, every call logged; BT_FAIL makes the named command fail
  cat > "$STUBS/bluetoothctl" << 'STUB'
#!/usr/bin/env bash
echo "$*" >> "$BATS_TEST_TMPDIR/bt.calls"
[[ -n "${BT_FAIL:-}" && "$*" == "$BT_FAIL"* ]] && { echo "Attempting $1"; echo "Failed to $1: org.bluez.Error.Failed"; exit 1; }
case "$1" in
  info)
    [[ -f "$BATS_TEST_TMPDIR/info.$2" ]] || { echo "Device $2 not available"; exit 1; }
    cat "$BATS_TEST_TMPDIR/info.$2" ;;
  show) cat "$BATS_TEST_TMPDIR/show" ;;
esac
STUB
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
  cat > "$BATS_TEST_TMPDIR/objects.json" << 'JSON'
{"type":"a{oa{sa{sv}}}","data":[{
 "/org/bluez":{"org.bluez.AgentManager1":{}},
 "/org/bluez/hci0":{"org.bluez.Adapter1":{"Address":{"type":"s","data":"DC:21:5C:DF:0A:1F"},"Alias":{"type":"s","data":"charon"},
   "Powered":{"type":"b","data":true},"Discovering":{"type":"b","data":false}}},
 "/org/bluez/hci0/dev_AA":{"org.bluez.Device1":{"Address":{"type":"s","data":"AA:00:00:00:00:01"},"Name":{"type":"s","data":"Mouse"},
   "Alias":{"type":"s","data":"Mouse"},"Icon":{"type":"s","data":"input-mouse"},"Paired":{"type":"b","data":true},
   "Connected":{"type":"b","data":true},"Trusted":{"type":"b","data":true},"Blocked":{"type":"b","data":false}},
   "org.bluez.Battery1":{"Percentage":{"type":"y","data":70}}},
 "/org/bluez/hci0/dev_BB":{"org.bluez.Device1":{"Address":{"type":"s","data":"BB:00:00:00:00:02"},"Name":{"type":"s","data":"Buds"},
   "Alias":{"type":"s","data":"buds "},"Icon":{"type":"s","data":"audio-headset"},"Paired":{"type":"b","data":false},
   "Bonded":{"type":"b","data":true},"Connected":{"type":"b","data":false},"Trusted":{"type":"b","data":true}}},
 "/org/bluez/hci0/dev_CC":{"org.bluez.Device1":{"Address":{"type":"s","data":"CC:00:00:00:00:03"},"Alias":{"type":"s","data":"Keys"},
   "Icon":{"type":"s","data":"input-keyboard"},"Paired":{"type":"b","data":true},"Blocked":{"type":"b","data":true}}},
 "/org/bluez/hci0/dev_DD":{"org.bluez.Device1":{"Address":{"type":"s","data":"DD:00:00:00:00:04"},"Alias":{"type":"s","data":"Far"},
   "Paired":{"type":"b","data":false},"RSSI":{"type":"n","data":-80}}},
 "/org/bluez/hci0/dev_EE":{"org.bluez.Device1":{"Address":{"type":"s","data":"EE:00:00:00:00:05"},"Alias":{"type":"s","data":"Near"},
   "Paired":{"type":"b","data":false},"RSSI":{"type":"n","data":-40}}},
 "/org/bluez/hci0/dev_FF":{"org.bluez.Device1":{"Address":{"type":"s","data":"FF:00:00:00:00:06"},"Alias":{"type":"s","data":"Ghost"},
   "Paired":{"type":"b","data":false}}}
}]}
JSON
  printf 'Device AA:00:00:00:00:01 (random)\n\tName: Mouse\n\tAlias: Mouse\n\tIcon: input-mouse\n\tPaired: yes\n\tBonded: yes\n\tTrusted: yes\n\tBlocked: no\n\tConnected: yes\n\tUUID: Battery Service           (0000180f-0000-1000-8000-00805f9b34fb)\n\tUUID: Vendor specific           (00010000-0000-1000-8000-011f2000046d)\n\tUUID: Human Interface Device    (00001812-0000-1000-8000-00805f9b34fb)\n\tBattery Percentage: 0x46 (70)\n' > "$BATS_TEST_TMPDIR/info.AA:00:00:00:00:01"
  printf 'Device BB:00:00:00:00:02 (public)\n\tName: Buds\n\tAlias: buds\n\tTrusted: no\n\tConnected: no\n\tRSSI: 0xffffffc4 (-60)\n\tBattery Percentage: 0x0a (10)\n' > "$BATS_TEST_TMPDIR/info.BB:00:00:00:00:02"
  printf 'Controller DC:21:5C:DF:0A:1F (public)\n\tName: charon\n\tAlias: charon\n\tPowered: yes\n\tDiscovering: no\n\tUUID: Audio Sink                (0000110b-0000-1000-8000-00805f9b34fb)\n' > "$BATS_TEST_TMPDIR/show"
}

src() { FZX_MODE="$1" "$BT/source.sh"; }

@test "paired: the controller's header row, connected first, then paired (or bonded) by name; state, trust, battery" {
  run src paired
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[0]}" = $'-\t-\tcharon  powered on  DC:21:5C:DF:0A:1F' ]
  [[ "${lines[1]}" == $'AA:00:00:00:00:01\tMouse\t● Mouse '*"  connected   trusted  70%     AA:00:00:00:00:01" ]]
  # the alias's trailing space trimmed; bonded counts as paired
  [[ "${lines[2]}" == $'BB:00:00:00:00:02\tbuds\t○ buds '*"  paired      trusted"*"BB:00:00:00:00:02" ]]
  [[ "${lines[3]}" == $'CC:00:00:00:00:03\tKeys\t○ Keys '*"  blocked   "* ]]
}

@test "all: devices found by a scan too, strongest signal first, unknown signal last" {
  run src all
  [ "${#lines[@]}" -eq 7 ]
  [ "$(printf '%s\n' "${lines[@]:1}" | cut -f2 | tr '\n' ' ')" = "Mouse buds Keys Near Far Ghost " ]
  [[ "${lines[4]}" == *"  -40 dBm  "* && "${lines[6]}" == *"  new  "* ]]
}

@test "icons by bluez's Icon property, a generic one otherwise; the battery icon" {
  FZX_ICONS=unicode run src all
  [[ "${lines[1]}" == *"● ⌖ Mouse"*"▮ 70%"* && "${lines[2]}" == *"○ ☊ buds"* && "${lines[4]}" == *"  ᛒ Near"* ]]
}

@test "no bluez on the bus: the header row says so; powered off and scanning in the header" {
  touch "$BATS_TEST_TMPDIR/nobluez"
  run src paired
  [ "$status" -eq 0 ]
  [ "$output" = $'-\t-\tno bluetooth controller (is bluetoothd running?)' ]
  rm "$BATS_TEST_TMPDIR/nobluez"
  sed -i 's/"Powered":{"type":"b","data":true},"Discovering":{"type":"b","data":false}/"Powered":{"type":"b","data":false},"Discovering":{"type":"b","data":true}/' "$BATS_TEST_TMPDIR/objects.json"
  run src paired
  [ "${lines[0]}" = $'-\t-\tcharon  powered off  scanning  DC:21:5C:DF:0A:1F' ]
  FZX_MODE=bogus run "$BT/source.sh"
  [ "$status" -eq 2 ]
}

@test "preview: a device's name, kind, address, state, battery, signal and services; the controller" {
  run "$BT/preview.sh" AA:00:00:00:00:01
  [ "${lines[0]}" = Mouse ]
  [[ "$output" == *"kind       input-mouse"* && "$output" == *"address    AA:00:00:00:00:01 (random)"* ]]
  [[ "$output" == *"connected  yes"* && "$output" == *"battery    70%"* ]]
  # vendor-specific UUIDs left out, the names without their UUIDs
  [[ "$output" == *$'services\n  Battery Service\n  Human Interface Device' ]]
  # the alias is the title, the name shown when it differs; the signal in dBm
  run "$BT/preview.sh" BB:00:00:00:00:02
  [ "${lines[0]}" = buds ]
  [[ "$output" == *"name       Buds"* && "$output" == *"signal     -60 dBm"* && "$output" == *"battery    10%"* ]]
  run "$BT/preview.sh" -
  [ "${lines[0]}" = charon ]
  [[ "$output" == *"powered    yes"* && "$output" == *$'services\n  Audio Sink' ]]
  run "$BT/preview.sh" 00:11:22:33:44:55
  [ "$output" = "Device 00:11:22:33:44:55 not available" ]
}

@test "actions: connect, disconnect, pair (then trust and connect), remove; the header row skipped" {
  "$BT/actions.sh" connect - AA:00:00:00:00:01 BB:00:00:00:00:02
  "$BT/actions.sh" disconnect AA:00:00:00:00:01
  "$BT/actions.sh" pair DD:00:00:00:00:04
  "$BT/actions.sh" remove CC:00:00:00:00:03
  [ "$(cat "$BATS_TEST_TMPDIR/bt.calls")" = "connect AA:00:00:00:00:01
connect BB:00:00:00:00:02
disconnect AA:00:00:00:00:01
pair DD:00:00:00:00:04
trust DD:00:00:00:00:04
connect DD:00:00:00:00:04
remove CC:00:00:00:00:03" ]
  # a failed pair stops there
  rm "$BATS_TEST_TMPDIR/bt.calls"
  BT_FAIL=pair run "$BT/actions.sh" pair DD:00:00:00:00:04
  [ "$status" -eq 1 ]
  [ "$(cat "$BATS_TEST_TMPDIR/bt.calls")" = "pair DD:00:00:00:00:04" ]
  run "$BT/actions.sh" bogus AA:00:00:00:00:01
  [ "$status" -eq 2 ]
}

@test "actions: trust flips each device; power flips the controller; failures name bluetoothctl's last line" {
  "$BT/actions.sh" trust AA:00:00:00:00:01 BB:00:00:00:00:02
  "$BT/actions.sh" power
  [ "$(grep -v '^info\|^show' "$BATS_TEST_TMPDIR/bt.calls")" = "untrust AA:00:00:00:00:01
trust BB:00:00:00:00:02
power off" ]
  BT_FAIL=disconnect run "$BT/actions.sh" disconnect AA:00:00:00:00:01
  [ "$status" -eq 1 ]
  [ "$output" = "Failed to disconnect: org.bluez.Error.Failed" ]
  run "$BT/actions.sh" trust 00:11:22:33:44:55
  [ "$status" -eq 1 ]
  [ "$output" = "Device 00:11:22:33:44:55 not available" ]
}

# a scanner a failed test leaves behind
teardown() {
  local p="${FZX_SESSION_DIR:-$BATS_TEST_TMPDIR/sess}/bluetooth-scan.pid"
  [[ -s "$p" ]] && kill "$(cat "$p")" 2> /dev/null
  [[ -s "$BATS_TEST_TMPDIR/bt.scan.pid" ]] && kill "$(cat "$BATS_TEST_TMPDIR/bt.scan.pid")" 2> /dev/null
  return 0
}

# scan_setup: the scan's stubs: bluetoothctl's scan prints a find and waits (its pid in bt.scan.pid), curl
# answers for fzf's socket while $BATS_TEST_TMPDIR/alive exists and logs what is posted; a session dir
scan_setup() {
  cat > "$STUBS/bluetoothctl" << 'STUB'
#!/usr/bin/env bash
echo "$*" >> "$BATS_TEST_TMPDIR/bt.calls"
if [[ "$*" == *"scan on"* ]]; then
  echo $$ > "$BATS_TEST_TMPDIR/bt.scan.pid"
  printf 'Discovery started\n[\e[0;92mNEW\e[0m] Device 11:22:33:44:55:66 Speaker\n'
  exec sleep 30
fi
STUB
  cat > "$STUBS/curl" << 'STUB'
#!/usr/bin/env bash
[[ -f "$BATS_TEST_TMPDIR/alive" ]] || exit 7
for ((i = 1; i <= $#; i++)); do
  [[ "${!i}" == --data-binary ]] && { j=$((i + 1)); echo "${!j}" >> "$BATS_TEST_TMPDIR/posts"; }
done
exit 0
STUB
  chmod +x "$STUBS"/*
  touch "$BATS_TEST_TMPDIR/alive"
  export FZX_SESSION_DIR="$BATS_TEST_TMPDIR/sess" FZF_SOCK="$BATS_TEST_TMPDIR/fzf.sock"
  mkdir -p "$FZX_SESSION_DIR"
  source "$BT/source.sh" || :
  # the reload action, as fzx would build it
  fzx::require() { :; }
  fzx::cb() { echo "fzx _cb source"; }
  fzx::reload_action() { printf -v "$2" 'reload(%s)' "$1"; }
}

# wait_for <command...>: up to 5s for it to succeed
wait_for() {
  local i
  for ((i = 0; i < 50; i++)); do "$@" && return 0; sleep 0.1; done
  return 1
}

scanning() { [[ -s "$FZX_SESSION_DIR/bluetooth-scan.pid" ]] && kill -0 "$(cat "$FZX_SESSION_DIR/bluetooth-scan.pid")" 2> /dev/null; }
bt_alive() { [[ -s "$BATS_TEST_TMPDIR/bt.scan.pid" ]] && kill -0 "$(cat "$BATS_TEST_TMPDIR/bt.scan.pid")" 2> /dev/null; }

@test "objects: when busctl cannot write JSON (number-keyed dictionaries), its text form is turned into the same" {
  cat > "$STUBS/busctl" << 'STUB'
#!/usr/bin/env bash
if [[ "$1" == --json=short ]]; then echo "Failed to create new json object: Invalid argument" >&2; exit 1; fi
cat "$BATS_TEST_TMPDIR/objects.txt"
STUB
  chmod +x "$STUBS/busctl"
  printf '%s\n' 'a{oa{sa{sv}}} 3 "/org/bluez" 1 "org.bluez.AgentManager1" 0 "/org/bluez/hci0" 1 "org.bluez.Adapter1" 3 "Address" s "DC:21:5C:DF:0A:1F" "Alias" s "charon" "Powered" b true "/org/bluez/hci0/dev_AA" 1 "org.bluez.Device1" 8 "Address" s "AA:00:00:00:00:09" "Alias" s "Lamp \"1\"\ttab" "Paired" b false "Connected" b false "RSSI" n -64 "UUIDs" as 2 "a" "b" "ManufacturerData" a{qv} 2 34818 ay 3 236 0 1 76 ay 0 "ServiceData" a{sv} 1 "x" (ii) 1 2' > "$BATS_TEST_TMPDIR/objects.txt"
  source "$BT/source.sh" || :
  run bluetooth::objects
  [ "$status" -eq 0 ]
  [ "$(jq -c '.data[0]["/org/bluez/hci0/dev_AA"]["org.bluez.Device1"] | [.Alias.data, .RSSI.data, .UUIDs.data, .ManufacturerData.data["34818"].data, .ManufacturerData.data["76"].data, .ServiceData.data.x.data]' <<< "$output")" = '["Lamp \"1\"\ttab",-64,["a","b"],[236,0,1],[],[1,2]]' ]
  FZX_MODE=all run "$BT/source.sh"
  [ "${lines[0]}" = $'-\t-\tcharon  powered on  DC:21:5C:DF:0A:1F' ]
  [[ "${lines[1]}" == $'AA:00:00:00:00:09\tLamp "1" tab\t'*"-64 dBm"* ]]
}

@test "scan: the toggle in the all mode keeps a scan running and reloads on a find; off or another mode stops it" {
  scan_setup
  FZX_MODE=all FZX_TOGGLES=scan bluetooth::scan_control
  scanning
  wait_for grep -qx 'reload(fzx _cb source)' "$BATS_TEST_TMPDIR/posts"
  wait_for bt_alive
  grep -q -- '--timeout 60 scan on' "$BATS_TEST_TMPDIR/bt.calls"
  # a second load while it runs starts no other
  FZX_MODE=all FZX_TOGGLES=scan bluetooth::scan_control
  [ "$(grep -c 'scan on' "$BATS_TEST_TMPDIR/bt.calls")" -eq 1 ]
  # toggled off: the scanner and its bluetoothctl end
  FZX_MODE=all FZX_TOGGLES="" bluetooth::scan_control
  [ ! -e "$FZX_SESSION_DIR/bluetooth-scan.pid" ]
  wait_for eval '! bt_alive'
  # another mode stops it too
  FZX_MODE=all FZX_TOGGLES=scan bluetooth::scan_control
  scanning
  FZX_MODE=paired FZX_TOGGLES=scan bluetooth::scan_control
  ! scanning
}

@test "scan: it ends by itself when fzf's socket stops answering; nothing outside a session or without the socket" {
  scan_setup
  FZX_MODE=all FZX_TOGGLES=scan bluetooth::scan_control
  scanning
  wait_for bt_alive
  rm "$BATS_TEST_TMPDIR/alive"
  wait_for eval '! scanning'
  wait_for eval '! bt_alive'
  touch "$BATS_TEST_TMPDIR/alive"
  FZF_SOCK="" FZX_MODE=all FZX_TOGGLES=scan bluetooth::scan_control
  ! scanning
  FZX_SESSION_DIR="" FZX_MODE=all FZX_TOGGLES=scan bluetooth::scan_control
  ! scanning
}

@test "under fzx: the header row, addresses accepted, action keys and their flags" {
  stub_fzf
  run "$FZX" -m bluetooth
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=1 "* && " ${FZF_ARGS[*]} " == *" --header-lines=1 "* ]]
  [[ "$(fzf_bind alt-c)" == "alt-c:execute($FZX _cb action connect {+1})+"*"+reload("* ]]
  [[ "$(fzf_bind alt-d)" == "alt-d:transform($FZX _cb notify disconnect {+1})+"*"+reload("* ]]
  [[ "$(fzf_bind alt-x)" == "alt-x:execute($FZX _cb action remove {+1})+"*"+reload("* ]]
  [[ "$(fzf_bind alt-P)" == "alt-P:transform($FZX _cb notify power {+1})+"*"+reload("* ]]
}

@test "menu: two entries where bluez answers; the summary names what is connected" {
  source "$BT/manifest.sh"
  bluetooth::applicable bluetooth
  [ "$(bluetooth::summary bluetooth)" = "1 connected: Mouse" ]
  sed -i 's/"Connected":{"type":"b","data":true}/"Connected":{"type":"b","data":false}/' "$BATS_TEST_TMPDIR/objects.json"
  [ "$(bluetooth::summary bluetooth)" = "nothing connected" ]
  sed -i 's/"Powered":{"type":"b","data":true}/"Powered":{"type":"b","data":false}/' "$BATS_TEST_TMPDIR/objects.json"
  [ "$(bluetooth::summary bluetooth)" = "powered off" ]
  touch "$BATS_TEST_TMPDIR/nobluez"
  ! bluetooth::applicable bluetooth
}
