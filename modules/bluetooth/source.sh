#!/usr/bin/env bash
# bluetooth source: a header row (the controller: name, power, discovering), then "address<TAB>name<TAB>
# display" per device. Every object comes from one D-Bus call to bluez (busctl GetManagedObjects, ~20ms;
# `bluetoothctl info` per device takes ~80ms each). Mode from $FZX_MODE: paired (default: paired or bonded
# devices), all (every device bluez knows, the ones a scan found included; $FZX_TOGGLES scan keeps a scan
# running meanwhile, bluetooth::scan_control). Connected devices first, then
# paired ones, then the rest by signal; by name within each.

# bluetooth::objects: bluez's object tree as busctl JSON ({"type": "a{oa{sa{sv}}}", "data": [{...}]}).
# busctl cannot write JSON for a dictionary with number keys, which devices a scan finds often carry
# (ManufacturerData is a{qv}): then its text form is read and turned into the same JSON
bluetooth::objects() {
  local out
  if out="$(command busctl --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects 2> /dev/null)"; then
    printf '%s\n' "$out"
    return 0
  fi
  command busctl call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects | bluetooth::text_json
}

# bluetooth::text_json: busctl's text form of a reply ("SIG value...", strings quoted and C-escaped,
# arrays as a count and their items, variants as their signature and value) as busctl's JSON; dictionary
# keys become strings
bluetooth::text_json() {
  awk '
    BEGIN { RS = "\001" }
    # tokens: words, and quoted strings kept with their quotes
    {
      n = 0; s = $0; L = length(s); i = 1
      while (i <= L) {
        c = substr(s, i, 1)
        if (c == " " || c == "\n" || c == "\t") { i++; continue }
        if (c == "\"") {
          j = i + 1
          while (j <= L) { d = substr(s, j, 1); if (d == "\\") { j += 2; continue } if (d == "\"") break; j++ }
          tok[++n] = substr(s, i, j - i + 1); i = j + 1; continue
        }
        j = i
        while (j <= L && index(" \n\t", substr(s, j, 1)) == 0) j++
        tok[++n] = substr(s, i, j - i); i = j
      }
    }
    function next_tok() { return tok[++p] }
    # tlen(t, i): the length of the complete type at position i of signature t
    function tlen(t, i,   c, depth, j) {
      c = substr(t, i, 1)
      if (c == "a") return 1 + tlen(t, i + 1)
      if (c == "(" || c == "{") {
        depth = 0
        for (j = i; j <= length(t); j++) {
          c = substr(t, j, 1)
          if (c == "(" || c == "{") depth++
          else if (c == ")" || c == "}") { depth--; if (depth == 0) return j - i + 1 }
        }
      }
      return 1
    }
    # jstr(quoted): a C-escaped busctl string as a JSON string
    function jstr(q,   s, out, k, c, d) {
      s = substr(q, 2, length(q) - 2); out = ""
      for (k = 1; k <= length(s); k++) {
        c = substr(s, k, 1)
        if (c == "\\") {
          d = substr(s, k + 1, 1); k++
          if (d == "x") { out = out "\\u00" substr(s, k + 1, 2); k += 2 }
          else if (d == "a") out = out "\\u0007"
          else if (d == "v") out = out "\\u000b"
          else if (d == "\047") out = out "\047"
          else out = out "\\" d
        } else if (c == "\t") out = out "\\t"
        else out = out c
      }
      return "\"" out "\""
    }
    function value(t,   c, n, k, out, elem, inner, kt, vt, i, sig, kk) {
      c = substr(t, 1, 1)
      if (c == "v") { sig = next_tok(); return "{\"type\":\"" sig "\",\"data\":" value(sig) "}" }
      if (c == "a") {
        elem = substr(t, 2); n = next_tok() + 0
        if (substr(elem, 1, 1) == "{") {
          inner = substr(elem, 2, length(elem) - 2)
          kt = substr(inner, 1, tlen(inner, 1)); vt = substr(inner, length(kt) + 1)
          out = "{"
          for (i = 0; i < n; i++) { kk = value(kt); if (kk !~ /^"/) kk = "\"" kk "\""; out = out (i ? "," : "") kk ":" value(vt) }
          return out "}"
        }
        out = "["
        for (i = 0; i < n; i++) out = out (i ? "," : "") value(elem)
        return out "]"
      }
      if (c == "(") {
        inner = substr(t, 2, length(t) - 2); out = "["; i = 1; k = 0
        while (i <= length(inner)) { n = tlen(inner, i); out = out (k++ ? "," : "") value(substr(inner, i, n)); i += n }
        return out "]"
      }
      if (c == "s" || c == "o" || c == "g") return jstr(next_tok())
      return next_tok()
    }
    END {
      if (n == 0) exit 1
      p = 0; sig = next_tok()
      printf "{\"type\":\"%s\",\"data\":[%s]}\n", sig, value(sig)
    }'
}

# shellcheck disable=SC2016  # jq, not shell
# the jq functions: devices (every Device1 as a flat object, with its Battery1 percentage) and the
# controller (the first Adapter1)
BLUETOOTH_JQ='def v($k): .[$k].data;
  def pad($w): if length > $w then .[0:$w - 1] + "…" else . + ([range(0; $w - length)] | map(" ") | join("")) end;
  def devices: .data[0] | to_entries | map(select(.value["org.bluez.Device1"]) |
    .value as $o | $o["org.bluez.Device1"] |
    {address: v("Address"), name: ((v("Alias") // v("Name") // v("Address")) | sub("\\s+$"; "") | gsub("[\\t\\n\\r]"; " ")),
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
  [[ -n "${NO_COLOR:+x}" ]] && b="" on="" off="" dim="" r=""
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

# bluetooth::scan_control: start the background scanner (scan.sh) when the all mode shows with the scan
# toggle on, stop it otherwise; it runs on every load, so leaving the mode or turning the toggle off ends
# it. Under fzx only: it needs the session and fzf's socket to reload through
bluetooth::scan_control() {
  [[ -n "${FZX_SESSION_DIR:-}" && -d "${FZX_SESSION_DIR:-}" ]] || return 0
  local pidf="$FZX_SESSION_DIR/bluetooth-scan.pid" pid="" want=0 i act src
  [[ "${FZX_MODE:-paired}" == all && " ${FZX_TOGGLES:-} " == *" scan "* && -n "${FZF_SOCK:-}" ]] && want=1
  [[ -f "$pidf" ]] && read -r pid < "$pidf"
  [[ -n "$pid" ]] && ! kill -0 "$pid" 2> /dev/null && { rm -f -- "$pidf"; pid=""; }
  if ((want)) && [[ -z "$pid" ]]; then
    fzx::require opts
    src="$(fzx::cb source)" || return 0
    fzx::reload_action "$src" act
    # detached, with none of the source's descriptors: fzf waits for the list to end
    command setsid -f "$BASH" "$(dirname "${BASH_SOURCE[0]}")/scan.sh" "$FZF_SOCK" "$pidf" "$act" \
      > /dev/null 2>&1 < /dev/null 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
    # its own pid file: wait for it, so the next load sees it running
    for ((i = 0; i < 20; i++)); do [[ -s "$pidf" ]] && break; sleep 0.05; done
  elif ((!want)) && [[ -n "$pid" ]]; then
    kill "$pid" 2> /dev/null
    # discovery ends with its client: wait, so the header this load draws says so
    for ((i = 0; i < 20; i++)); do kill -0 "$pid" 2> /dev/null || break; sleep 0.05; done
    rm -f -- "$pidf"
  fi
  return 0
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
  bluetooth::scan_control
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
