#!/usr/bin/env bats
# the bluetooth module against a stub busctl (bluez's object tree from a fixture) and bluetoothctl

load test_helper

BT="$(readlink -f "$BATS_TEST_DIRNAME/../modules/bluetooth")"

setup() {
  setup_fzx
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

@test "scan: the all mode only, for FZX_BLUETOOTH_SCAN_SECONDS" {
  FZX_MODE=paired run "$BT/actions.sh" scan
  [ "$status" -eq 2 ]
  FZX_MODE=all FZX_BLUETOOTH_SCAN_SECONDS=2 run "$BT/actions.sh" scan
  [ "$status" -eq 0 ]
  grep -qx -- '--timeout 2 scan on' "$BATS_TEST_TMPDIR/bt.calls"
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
