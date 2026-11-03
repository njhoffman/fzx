#!/usr/bin/env bash
# bluetooth source: a header row (the controller: name, power, discovering), then "address<TAB>name<TAB>
# display" per device. Every object comes from one D-Bus call to bluez (busctl GetManagedObjects, ~20ms;
# `bluetoothctl info` per device takes ~80ms each). Mode from $FZX_MODE: paired (default: paired or bonded
# devices), all (every device bluez knows, the ones a scan found included). Connected devices first, then
# paired ones, then the rest by signal; by name within each.

# bluetooth::objects: bluez's object tree as busctl JSON ({"type": "a{oa{sa{sv}}}", "data": [{...}]})
bluetooth::objects() {
  command busctl --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects
}

# shellcheck disable=SC2016  # jq, not shell
# the jq functions: devices (every Device1 as a flat object, with its Battery1 percentage) and the
# controller (the first Adapter1)
BLUETOOTH_JQ='def v($k): .[$k].data;
  def pad($w): if length > $w then .[0:$w - 1] + "…" else . + ([range(0; $w - length)] | map(" ") | join("")) end;
  def devices: .data[0] | to_entries | map(select(.value["org.bluez.Device1"]) |
    .value as $o | $o["org.bluez.Device1"] |
    {address: v("Address"), name: ((v("Alias") // v("Name") // v("Address")) | sub("\\s+$"; "")),
     icon: (v("Icon") // ""), paired: (v("Paired") == true or v("Bonded") == true), connected: (v("Connected") == true),
     trusted: (v("Trusted") == true), blocked: (v("Blocked") == true), rssi: v("RSSI"),
     battery: ($o["org.bluez.Battery1"] // {} | v("Percentage"))});
  def controller: [.data[0][] | .["org.bluez.Adapter1"] // empty][0] |
    if . == null then null else {name: (v("Alias") // v("Name") // v("Address")), address: v("Address"),
      powered: (v("Powered") == true), discovering: (v("Discovering") == true)} end;'

# shellcheck disable=SC2016  # jq, not shell
# the header row, from the controller (null: none)
BLUETOOTH_HEADER_JQ='
  if . == null then "-\t-\t" + $dim + "no bluetooth controller (is bluetoothd running?)" + $r
  else "-\t-\t" + $b + .name + $r + "  " + (if .powered then $on + "powered on" else $off + "powered off" end) + $r +
    (if .discovering then "  " + $dim + "scanning" + $r else "" end) + "  " + $dim + .address + $r end'

# bluetooth::_icons: jq --arg options for the device icons (by bluez's Icon property) and the battery
bluetooth::_icons() {
  local _n _g
  BLUETOOTH_ICON_ARGS=()
  fzx::require icons
  for _n in bt_mouse bt_keyboard bt_headset bt_headphones bt_speaker bt_phone bt_computer bt_gamepad bt_display \
    bt_device battery; do
    fzx::icon "$_n" _g
    BLUETOOTH_ICON_ARGS+=(--arg "$_n" "$_g")
  done
}

# bluetooth::list: the header row and the mode's devices, from the object tree on stdin
bluetooth::list() {
  local mode="${FZX_MODE:-paired}"
  local b=$'\e[1m' on=$'\e['"${FZX_COLORS[bluetooth_connected]:-38;5;114}m" off=$'\e['"${FZX_COLORS[bluetooth_off]:-38;5;203}m"
  local dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && b="" on="" off="" dim="" r=""
  bluetooth::_icons
  command jq -r --arg mode "$mode" --arg b "$b" --arg on "$on" --arg off "$off" --arg dim "$dim" --arg r "$r" \
    "${BLUETOOTH_ICON_ARGS[@]}" "$BLUETOOTH_JQ"'
    def icon: {"input-mouse": $bt_mouse, "input-keyboard": $bt_keyboard, "audio-headset": $bt_headset,
      "audio-headphones": $bt_headphones, "audio-card": $bt_speaker, "phone": $bt_phone, "computer": $bt_computer,
      "input-gaming": $bt_gamepad, "video-display": $bt_display}[.icon] // $bt_device;
    def rank: if .connected then 0 elif .paired then 1 else 2 end;
    (controller | '"$BLUETOOTH_HEADER_JQ"'),
    (devices | map(select($mode == "all" or .paired)) | sort_by(rank, (if rank == 2 then -(.rssi // -999) else 0 end), (.name | ascii_downcase))[] |
      [.address, .name,
       ((if .connected then $on + "●" + $r elif .paired then $dim + "○" + $r else " " end) + " " +
        (icon | if . == "" then "" else . + " " end) +
        (if .connected then $b + (.name | pad(28)) + $r else (.name | pad(28)) end) + "  " +
        (if .blocked then $off + ("blocked" | pad(10)) + $r
         elif .connected then $on + ("connected" | pad(10)) + $r
         elif .paired then ("paired" | pad(10))
         elif .rssi != null then $dim + ("\(.rssi) dBm" | pad(10)) + $r
         else $dim + ("new" | pad(10)) + $r end) + "  " +
        ((if .trusted then "trusted" else "" end) | pad(7)) + "  " +
        ((if .battery != null then (if $battery == "" then "" else $battery + " " end) + "\(.battery)%" else "" end) | pad(6)) + "  " +
        $dim + .address + $r)] | join("\t"))
  '
}

bluetooth::source() {
  case "${FZX_MODE:-paired}" in
    paired | all) ;;
    *)
      printf 'bluetooth: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
  command -v busctl > /dev/null || { printf 'bluetooth: needs busctl (systemd)\n' >&2; return 2; }
  local json
  # no bluez on the bus: the header row says so
  json="$(bluetooth::objects 2> /dev/null)" || json='{"data":[{}]}'
  bluetooth::list <<< "$json"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" bluetooth
  bluetooth::source "$@"
}
