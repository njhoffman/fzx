#!/usr/bin/env bash
# bluetooth preview: a device's name, kind, address, state, battery, signal and services from `bluetoothctl
# info`; the header row (id "-"): the controller from `bluetoothctl show`

# bluetooth::preview <address|->
bluetooth::preview() {
  local id="${1:-}" out
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" on=$'\e['"${FZX_COLORS[bluetooth_connected]:-38;5;114}m"
  local off=$'\e['"${FZX_COLORS[bluetooth_off]:-38;5;203}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" on="" off="" r=""
  [[ -n "$id" ]] || return 0
  if [[ "$id" == - ]]; then
    out="$(command bluetoothctl show 2>&1)" || { printf '%s\n' "$out"; return 0; }
  else
    out="$(command bluetoothctl info "$id" 2>&1)" || { printf '%s\n' "$out"; return 0; }
  fi
  # "Key: value" lines (a tab first); UUID lines become the services list, the rest is shown in a fixed order
  awk -v b="$b" -v d="$d" -v on="$on" -v off="$off" -v r="$r" -v low="${FZX_BLUETOOTH_BATTERY_LOW:-20}" '
    function row(k, label,  v) { if (!(k in f)) return; v = f[k]
      if (v == "yes" && (k == "Connected" || k == "Powered")) v = on v r
      else if (v == "yes" && k == "Blocked") v = off v r
      printf "%s%-10s%s %s\n", d, label, r, v }
    /^(Device|Controller) / { addr = $2; type = $3; next }
    /^\t[A-Za-z ]+: / {
      line = substr($0, 2); k = line; sub(/: .*/, "", k); v = line; sub(/^[^:]*: /, "", v)
      if (k == "UUID") { sub(/[ \t]+\([0-9a-f-]+\)$/, "", v); if (v != "Vendor specific" && !(v in seen)) { seen[v] = 1; svc[++n] = v } ; next }
      if (k == "Battery Percentage") { v = v; sub(/^0x[0-9a-f]+ \(/, "", v); sub(/\)$/, "", v); v = (v + 0 <= low ? off v "%" r : v "%") }
      if (k == "RSSI" || k == "TxPower") { sub(/^0x[0-9a-f]+ \(/, "", v); sub(/\)$/, "", v); v = v " dBm" }
      if (!(k in f)) f[k] = v
    }
    END {
      if (addr == "") exit
      name = ("Alias" in f) ? f["Alias"] : (("Name" in f) ? f["Name"] : addr)
      printf "%s%s%s\n\n", b, name, r
      if ("Icon" in f) printf "%s%-10s%s %s\n", d, "kind", r, f["Icon"]
      printf "%s%-10s%s %s %s\n", d, "address", r, addr, d type r
      if (("Name" in f) && f["Name"] != name) row("Name", "name")
      row("Powered", "powered"); row("Discovering", "scanning"); row("Pairable", "pairable"); row("Discoverable", "visible")
      row("Connected", "connected"); row("Paired", "paired"); row("Bonded", "bonded"); row("Trusted", "trusted"); row("Blocked", "blocked")
      row("Battery Percentage", "battery"); row("RSSI", "signal"); row("TxPower", "tx power")
      if (n) { printf "\n%sservices%s\n", d, r; for (i = 1; i <= n; i++) printf "  %s\n", svc[i] }
    }' <<< "$out"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" bluetooth
  bluetooth::preview "$@"
}
