#!/usr/bin/env bash
# network actions on the selected ids of the current mode; an action that does not apply to the mode says
# so and does nothing.

# network::wait: keep a failure on screen until a key (foreground actions return to fzf at once)
network::wait() {
  [[ -t 1 ]] || return 0
  printf '\n\e[2m(press a key)\e[0m'
  read -rsn1 < /dev/tty || :
}

# network::_kill <PID/PROTO/PORT>: SIGTERM to the process: as you when it is yours, else through sudo; a
# port whose process is not visible goes to `sudo fuser -k`
network::_kill() {
  local pid="${1%%/*}" rest="${1#*/}"
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    if [[ -O "/proc/$pid" ]]; then kill -TERM -- "$pid"; else command sudo kill -TERM -- "$pid"; fi
  else
    # PROTO/PORT -> PORT/PROTO, as fuser takes it
    command sudo fuser -k -TERM "${rest#*/}/${rest%%/*}"
  fi
}

# network::_wifi_device: the first wifi device NetworkManager has
network::_wifi_device() {
  command nmcli -t -f DEVICE,TYPE device | awk -F: '$2 == "wifi" { print $1; exit }'
}

# network::action <action> <id...>
network::action() {
  local action="${1:-}" mode="${FZX_MODE:-ports}" id ssid rc=0
  shift
  case "$action:$mode" in
    kill:ports | kill:connections)
      for id in "$@"; do network::_kill "$id" || rc=$?; done
      ;;
    connect:wifi)
      id="${1:-}"
      ssid="$(command nmcli -g SSID device wifi list bssid "$id" --rescan no 2> /dev/null | head -1)"
      if [[ -n "$ssid" ]] && command nmcli -g NAME connection show | grep -qxF -- "$ssid"; then
        command nmcli connection up id "$ssid" || rc=$?
      else
        command nmcli --ask device wifi connect "$id" || rc=$?
      fi
      ;;
    disconnect:wifi)
      command nmcli device disconnect "$(network::_wifi_device)" || rc=$?
      ;;
    rescan:wifi) command nmcli device wifi rescan 2> /dev/null; sleep 2 ;;
    rescan:services) rm -f -- "$FZX_CACHE_DIR/network/services" ;;
    open:services)
      local type addr port scheme
      for id in "$@"; do
        IFS='|' read -r type _ addr port <<< "$id"
        case "$type" in
          _http._tcp) scheme=http ;; _https._tcp) scheme=https ;;
          *) printf 'network: %s is not a web service\n' "$type" >&2; rc=2; continue ;;
        esac
        command xdg-open "$scheme://$addr:$port" > /dev/null 2>&1 || rc=$?
      done
      ;;
    *)
      printf 'network: %s does not apply to %s\n' "$action" "$mode" >&2
      return 2
      ;;
  esac
  ((rc == 0)) || network::wait
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && network::action "$@"
