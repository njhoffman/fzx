#!/usr/bin/env bash
# network menu entries, each where its tool is installed (wifi: with a wifi device; services: with the
# avahi daemon running)

network::manifest() {
  fzx::entry network "Listening ports and their processes"
  fzx::entry network:connections "Network connections"
  fzx::entry network:interfaces "Network interfaces and addresses"
  fzx::entry network:routes "Routing table"
  fzx::entry network:wifi "Wifi networks in range"
  fzx::entry network:services "mDNS services on the network"
}

network::applicable() {
  case "$1" in
    network | network:connections) command -v ss > /dev/null ;;
    network:interfaces | network:routes) command -v ip > /dev/null ;;
    network:wifi) command -v nmcli > /dev/null && command nmcli -t -f TYPE device 2> /dev/null | grep -qx wifi ;;
    network:services) command -v avahi-browse > /dev/null && [[ -S "${FZX_NETWORK_AVAHI_SOCKET:-/run/avahi-daemon/socket}" ]] ;;
    *) return 1 ;;
  esac
}

# network::summary_services: the last browse's count. A browse takes longer than a summary may, so one due
# (none yet, or past FZX_NETWORK_SERVICES_TTL) runs detached and its result shows at the next listing: the
# cache file's time is in network::summary_key
network::summary_services() {
  local file="$FZX_CACHE_DIR/network/services" ttl
  fzx::parse_duration "${FZX_NETWORK_SERVICES_TTL:-10m}" ttl || ttl=600
  if [[ ! -f "$file" ]] || ((EPOCHSECONDS - $(stat -c %Y -- "$file") >= ttl)); then
    # shellcheck source=./source.sh
    source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :
    (network::services_cache file) < /dev/null > /dev/null 2>&1 &
    disown
  fi
  if [[ -f "$file" ]]; then
    printf '%s services\n' "$(awk -F'\t' '$5 != 0 { n++ } END { print n + 0 }' "$file")"
  else
    printf 'browsing the network\n'
  fi
}

# network::summary_key: a new browse makes a new summary at once
network::summary_key() { stat -c %Y -- "$FZX_CACHE_DIR/network/services" 2> /dev/null || :; }

network::summary() {
  local n
  case "$1" in
    network)
      n="$(command ss -H -tuln | wc -l)"
      printf '%s listening, %s tcp\n' "$n" "$(command ss -H -tln | wc -l)"
      ;;
    network:connections) printf '%s established\n' "$(command ss -H -tun state established | wc -l)" ;;
    network:interfaces)
      command ip -br addr | awk '$2 == "UP" { n++; if (!a) { a = $1; for (i = 3; i <= NF; i++) if ($i ~ /\./) { a = a " " $i; break } } }
        END { printf "%d up%s\n", n, a ? ": " a : "" }'
      ;;
    network:routes) command ip route show default | awk 'NR == 1 { print "default via " $3 " dev " $5 }' ;;
    network:wifi)
      command nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2> /dev/null |
        awk -F: '{ n++ } $1 == "*" && !on { on = $3; s = $2 } END { if (on != "") printf "on %s (%s%%), %d in range\n", on, s, n; else printf "not connected, %d in range\n", n }'
      ;;
    network:services)
      network::summary_services
      ;;
  esac
}
