#!/usr/bin/env bash
# network preview by mode: ports and connections the process (user, start, command line) and its sockets;
# interfaces their addresses and counters (ip -s) and NetworkManager's view; routes the route in detail and
# its interface; wifi the network in detail and whether a connection is saved for it; services the
# service's address and TXT records; files the file (stat).

[[ -n "${_FZX_CORE_LOADED:-}" ]] || source "${FZX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/core.sh"

# network::preview <id>
network::preview() {
  local id="${1:-}" b=$'\e[1m' d=$'\e[38;5;244m' r=$'\e[0m' color=always
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r="" color=never
  case "${FZX_MODE:-ports}" in
    ports | connections)
      local pid="${id%%/*}" proto port rest
      rest="${id#*/}" proto="${rest%%/*}" port="${rest#*/}"
      if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        printf '%s/%s: the process is not yours; turn on root (sudo -n) to see it\n' "$port" "$proto"
        return 0
      fi
      [[ -d "/proc/$pid" ]] || { printf 'process %s has exited\n' "$pid"; return 0; }
      command ps -o pid=,user=,lstart=,etime= -p "$pid" | awk -v b="$b" -v r="$r" '{ printf "%s%s%s  %s  started %s %s %s %s %s (%s ago)\n", b, $1, r, $2, $3, $4, $5, $6, $7, $8 }'
      tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null
      printf '\n\n%ssockets%s\n' "$b" "$r"
      command lsof -n -P -w -a -i -p "$pid" 2> /dev/null | awk 'NR > 1 { $1 = $2 = $3 = $4 = $6 = $7 = ""; sub(/^ +/, ""); print "  " $0 }'
      ;;
    interfaces)
      command ip -c="$color" -s addr show dev "$id" 2> /dev/null || command ip -s addr show dev "$id"
      if command -v nmcli > /dev/null; then
        printf '\n'
        command nmcli -f GENERAL.TYPE,GENERAL.CONNECTION,GENERAL.STATE,IP4.GATEWAY,IP4.DNS,IP6.GATEWAY device show "$id" 2> /dev/null |
          awk -v d="$d" -v r="$r" 'NF > 1 { k = $1; $1 = ""; printf "%s%-22s%s%s\n", d, k, r, $0 }'
      fi
      ;;
    routes)
      local dev=""
      [[ "$id" == *" dev "* ]] && dev="${id##* dev }"
      # shellcheck disable=SC2086  # the id is "DEST dev DEV", words ip takes as they are
      command ip -d route show $id 2> /dev/null || command ip -6 -d route show $id
      if [[ -n "$dev" ]]; then
        printf '\n'
        command ip -c="$color" -br addr show dev "$dev" 2> /dev/null
      fi
      ;;
    wifi)
      local ssid
      command nmcli -f SSID,BSSID,MODE,CHAN,FREQ,RATE,SIGNAL,BARS,SECURITY,WPA-FLAGS,RSN-FLAGS -m multiline \
        device wifi list bssid "$id" --rescan no 2> /dev/null
      ssid="$(command nmcli -g SSID device wifi list bssid "$id" --rescan no 2> /dev/null | head -1)"
      printf '\n'
      if [[ -n "$ssid" ]] && command nmcli -g NAME connection show 2> /dev/null | grep -qxF -- "$ssid"; then
        printf '%ssaved connection:%s %s (alt-c connects without asking)\n' "$d" "$r" "$ssid"
      else
        printf '%sno saved connection: alt-c asks for the password%s\n' "$d" "$r"
      fi
      ;;
    services)
      local type host addr port file
      IFS='|' read -r type host addr port <<< "$id"
      printf '%s%s%s  %s\n%s:%s  (%s)\n' "$b" "$host" "$r" "$type" "$addr" "$port" "$host:$port"
      fzx::require log session
      file="$FZX_CACHE_DIR/network/services"
      [[ -f "$file" ]] && awk -F'\t' -v t="$type" -v h="$host" -v a="$addr" -v d="$d" -v r="$r" '
        $2 == t && $3 == h && $4 == a {
          printf "\n%sname%s %s\n", d, r, $1
          n = split($6, f, "\" \""); if (n) printf "\n%sTXT records%s\n", d, r
          for (i = 1; i <= n; i++) { gsub(/^"|"$/, "", f[i]); if (f[i] != "") print "  " f[i] }
        }' "$file"
      ;;
    files)
      [[ -e "$id" ]] && command stat -- "$id" 2> /dev/null || printf '%s\n' "$id"
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && network::preview "$@"
