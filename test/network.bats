#!/usr/bin/env bats
# the network module against stubbed ss, ip, nmcli, avahi-browse, lsof, sudo, fuser and xdg-open (calls are
# logged; nothing touches the real network)

load test_helper

NET="$(readlink -f "$BATS_TEST_DIRNAME/../modules/network")"

setup() {
  setup_fzx
  STUBS="$BATS_TEST_TMPDIR/bin"
  CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$STUBS"
  # a real process of ours for the sockets to belong to (its user comes from ps)
  sleep 300 &
  MINE=$!
  stub ss << EOF
case "\$*" in
  '-H -tulpn')
    printf 'tcp LISTEN 0 4096 0.0.0.0:22 0.0.0.0:*\n'
    printf 'udp UNCONN 0 0 224.0.0.251:5353 0.0.0.0:* users:(("chrome",pid=$MINE,fd=1),("chrome",pid=$MINE,fd=2))\n'
    printf 'tcp LISTEN 0 511 127.0.0.1:8080 0.0.0.0:* users:(("node",pid=$MINE,fd=20))\n'
    printf 'tcp LISTEN 0 511 [::1]:631 [::]:* users:(("cupsd",pid=$MINE,fd=7))\n' ;;
  '-H -tupn state established')
    printf 'tcp 0 0 192.168.1.5:50000 140.82.112.3:443 users:(("zeta",pid=$MINE,fd=3))\n'
    printf 'tcp 0 0 192.168.1.5:50001 10.0.0.9:22 users:(("alpha",pid=$MINE,fd=4))\n' ;;
  '-H -tuln') printf 'a\nb\nc\n' ;;
  '-H -tln') printf 'a\nb\n' ;;
  '-H -tun state established') printf 'x\n' ;;
esac
EOF
  stub ip << 'EOF'
case "$*" in
  '-br link') printf 'lo UNKNOWN 00:00:00:00:00:00 <LOOPBACK,UP>\nwlan0 UP dc:21:5c:df:0a:1b <BROADCAST,UP>\n' ;;
  '-br addr') printf 'lo UNKNOWN 127.0.0.1/8 ::1/128\nwlan0 UP fe80::1/64 192.168.1.5/24\n' ;;
  route) printf 'default via 192.168.1.1 dev wlan0 proto dhcp src 192.168.1.5 metric 600\n192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.5\n' ;;
  '-6 route') printf 'fe80::/64 dev wlan0 proto kernel metric 1024\n' ;;
  'route show default') printf 'default via 192.168.1.1 dev wlan0 proto dhcp\n' ;;
esac
EOF
  stub nmcli << 'EOF'
case "$*" in
  '-t -f IN-USE,BSSID,SSID,CHAN,RATE,SIGNAL,SECURITY device wifi list --rescan no')
    printf ' :AA\\:BB\\:CC\\:00\\:00\\:01:zebra:6:270 Mbit/s:40:WPA2\n'
    printf '*:AA\\:BB\\:CC\\:00\\:00\\:02:home:44:540 Mbit/s:80:WPA2\n'
    printf ' :AA\\:BB\\:CC\\:00\\:00\\:03::6:130 Mbit/s:90:\n' ;;
  '-g SSID device wifi list bssid AA:BB:CC:00:00:01 --rescan no') echo zebra ;;
  '-g SSID device wifi list bssid AA:BB:CC:00:00:02 --rescan no') echo home ;;
  '-g NAME connection show') printf 'home\nWired\n' ;;
  '-t -f DEVICE,TYPE device') printf 'lo:loopback\nwlan0:wifi\n' ;;
  '-t -f TYPE device') printf 'loopback\nwifi\n' ;;
  '-t -f IN-USE,SIGNAL,SSID device wifi list --rescan no') printf ' :40:zebra\n*:80:home\n' ;;
esac
EOF
  stub avahi-browse << 'EOF'
printf '+;wlan0;IPv4;ignored;_http._tcp;local\n'
printf '=;wlan0;IPv6;Printer\\032Two;_http._tcp;local;printer.local;fe80::2;80;"ty=Laser" "rp=ipp"\n'
printf '=;wlan0;IPv4;Printer\\032Two;_http._tcp;local;printer.local;192.168.1.20;80;"ty=Laser" "rp=ipp"\n'
printf '=;wlan0;IPv4;Speaker;_spotify-connect._tcp;local;speaker.local;192.168.1.30;41800;"CPath=/spConn"\n'
printf '=;wlan0;IPv4;Box;_device-info._tcp;local;box.local;192.168.1.40;0;"model=X"\n'
EOF
  stub lsof << 'EOF'
printf 'p1234\nfcwd\ntDIR\nn/srv/app\nf20\ntIPv4\nnTCP 127.0.0.1:8080 (LISTEN)\n'
EOF
  stub sudo << 'EOF'
[[ "$1" == -n && -n "${SUDO_FAILS:-}" ]] && exit 1
[[ "$1" == -n ]] && shift
[[ "$1" == true ]] && exit 0
exec "$@"
EOF
  stub fuser ':'
  stub xdg-open ':'
  export PATH="$STUBS:$PATH"
}

teardown() {
  kill "$MINE" 2> /dev/null || :
}

# stub <name> [body]: a script that logs its arguments to $CALLS, then runs the body (stdin or the argument)
stub() {
  { printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n' "$1" "$CALLS"
    if (($# > 1)); then printf '%s\n' "$2"; else cat; fi; } > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

plain() { sed 's/\x1b\[[0-9;]*m//g'; }
src() { FZX_MODE="$1" "$NET/source.sh" "${@:2}" | plain; }
act() { FZX_MODE="$1" "$NET/actions.sh" "${@:2}"; }

@test "ports: a header, by port; ids PID/PROTO/PORT, '-' without a visible process; users from ps" {
  run src ports
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == -$'\t'-$'\t'"PROTO ADDRESS"*"PORT"*"PROCESS"*"PID USER"* ]]
  [[ "${lines[1]}" == "-/tcp/22"$'\t'"0.0.0.0:22"$'\t'"tcp "*" 22 "* ]]
  [[ "${lines[2]}" == "$MINE/tcp/631"$'\t'"[::1]:631"$'\t'*"[::1]"*"631"*"cupsd"*"$MINE $USER"* ]]
  [[ "${lines[3]}" == "$MINE/udp/5353"$'\t'* && "${lines[3]}" == *"chrome +1"* ]]
  [[ "${lines[4]}" == "$MINE/tcp/8080"$'\t'"127.0.0.1:8080"$'\t'* ]]
}

@test "ports and connections: sorts by process or remote; the sorted column underlined" {
  FZX_SORT=process run src ports
  [[ "${lines[1]}" == *chrome* && "${lines[2]}" == *cupsd* && "${lines[3]}" == *node* && "${lines[4]}" == "-/tcp/22"* ]]
  run src connections
  [[ "${lines[0]}" == *"PROTO LOCAL"*"REMOTE"*"PROCESS"* ]]
  [[ "${lines[1]}" == "$MINE/tcp/50001"$'\t'"10.0.0.9:22"$'\t'*alpha* && "${lines[2]}" == *zeta* ]]
  FZX_SORT=process run src connections
  [[ "${lines[1]}" == *alpha* ]]
  run env FZX_MODE=ports "$NET/source.sh"
  [[ "${lines[0]}" == *$'\e[1;38;5;245;4mPORT'* ]]
  [[ "${lines[1]}" == *$'\e[1;38;5;141;4m22'* ]]
}

@test "root: ss through sudo -n; without a cached sudo, as you, and the header says so" {
  FZX_TOGGLES=root run src ports
  grep -qx 'sudo -n ss -H -tulpn' "$CALLS"
  [[ "${lines[0]}" != *"sudo -v"* ]]
  SUDO_FAILS=1 FZX_TOGGLES=root run src ports
  [[ "${lines[0]}" == *"(root: run sudo -v first)"* ]]
  [ "${#lines[@]}" -eq 5 ]
}

@test "interfaces, routes: MACs joined, the first IPv4 address to copy; routes as ip takes them, IPv6 too" {
  run src interfaces
  [[ "${lines[0]}" == *"NAME"*"STATE"*"ADDRESSES"*"MAC"* ]]
  [[ "${lines[2]}" == "wlan0"$'\t'"192.168.1.5"$'\t'"wlan0 "*"UP"*"fe80::1/64 192.168.1.5/24"*"dc:21:5c:df:0a:1b" ]]
  run src routes
  [[ "${lines[1]}" == "default dev wlan0"$'\t'"default"$'\t'"default"*"192.168.1.1"*"wlan0"*"192.168.1.5"*"proto dhcp metric 600" ]]
  [[ "${lines[3]}" == "fe80::/64 dev wlan0"$'\t'* ]]
}

@test "wifi: BSSID ids (nmcli's escaped colons), hidden networks as --, strongest first or by name" {
  run src wifi
  [[ "${lines[1]}" == "AA:BB:CC:00:00:03"$'\t\t'*"--"*"90%"*"open" ]]
  [[ "${lines[2]}" == "AA:BB:CC:00:00:02"$'\t'"home"$'\t'"* home"*"80% ▂▄▆█"*"44"*"WPA2" ]]
  [[ "${lines[3]}" == *zebra*"40% ▂▄__"* ]]
  FZX_SORT=name run src wifi
  [[ "${lines[1]}" == *"--"* && "${lines[2]}" == *home* && "${lines[3]}" == *zebra* ]]
}

@test "services: browsed once into the cache (IPv4 kept, names unescaped, no port-0 records), then served" {
  run src services
  [[ "${lines[0]}" == *"NAME"*"TYPE"*"HOST"*"ADDRESS"* ]]
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[1]}" == "_http._tcp|printer.local|192.168.1.20|80"$'\t'"printer.local:80"$'\t'"Printer Two "*"192.168.1.20:80" ]]
  [[ "${lines[2]}" == *Speaker*"_spotify-connect._tcp"* ]]
  run src services
  [ "$(grep -c '^avahi-browse' "$CALLS")" -eq 1 ]
  # past the ttl: browsed again
  touch -d '1 hour ago' "$FZX_CACHE_DIR/network/services"
  run src services
  [ "$(grep -c '^avahi-browse' "$CALLS")" -eq 2 ]
}

@test "files: lsof's open files of the process; a row without a visible process says so" {
  run src files --pid "1234/tcp/8080"
  [[ "${lines[0]}" == *"FD"*"TYPE"*"NAME"* ]]
  [[ "${lines[1]}" == "/srv/app"$'\t'"/srv/app"$'\t'"cwd "*"DIR"*"/srv/app" ]]
  [[ "${lines[2]}" == *"20 "*"IPv4"*"TCP 127.0.0.1:8080 (LISTEN)" ]]
  grep -qx 'lsof -n -P -w -p 1234 -F ftn' "$CALLS"
  run env FZX_MODE=files "$NET/source.sh" --pid "-/tcp/22"
  [ "$status" -eq 0 ]
  [ "$output" = "-"$'\t'"-"$'\t'"no visible process for tcp/22: pick a row with a PID, or turn on root (sudo -n) first" ]
}

@test "kill: yours as you, another's through sudo, a port without a process through sudo fuser" {
  act ports kill "$MINE/tcp/8080"
  ! kill -0 "$MINE" 2> /dev/null
  act ports kill "1/tcp/631" || :
  grep -qx 'sudo kill -TERM -- 1' "$CALLS"
  act ports kill "-/tcp/22"
  grep -qx 'sudo fuser -k -TERM 22/tcp' "$CALLS"
}

@test "wifi actions: a saved network comes up by name, a new one asks; disconnect the wifi device; rescan" {
  act wifi connect AA:BB:CC:00:00:02
  grep -qx 'nmcli connection up id home' "$CALLS"
  act wifi connect AA:BB:CC:00:00:01
  grep -qx 'nmcli --ask device wifi connect AA:BB:CC:00:00:01' "$CALLS"
  act wifi disconnect AA:BB:CC:00:00:02
  grep -qx 'nmcli device disconnect wlan0' "$CALLS"
}

@test "services actions: open http ones in the browser, refuse others; rescan drops the cache" {
  src services > /dev/null
  act services open "_http._tcp|printer.local|192.168.1.20|80"
  grep -qx 'xdg-open http://192.168.1.20:80' "$CALLS"
  run act services open "_spotify-connect._tcp|speaker.local|192.168.1.30|41800"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a web service"* ]]
  act services rescan
  [ ! -e "$FZX_CACHE_DIR/network/services" ]
  run act ports open x
  [ "$status" -eq 2 ]
  [[ "$output" == *"open does not apply to ports"* ]]
}

@test "menu: entries where their tools are; summaries" {
  load_libs log config menu
  fzx::menu_entries network "$NET"
  network::applicable network
  network::applicable network:wifi
  [ "$(network::summary network)" = "3 listening, 2 tcp" ]
  [ "$(network::summary network:connections)" = "1 established" ]
  [ "$(network::summary network:interfaces)" = "1 up: wlan0 192.168.1.5/24" ]
  [ "$(network::summary network:routes)" = "default via 192.168.1.1 dev wlan0" ]
  [ "$(network::summary network:wifi)" = "on home (80%), 2 in range" ]
  # services: only from a browse already made
  [ -z "$(network::summary network:services)" ]
  FZX_MODE=services "$NET/source.sh" > /dev/null
  [ "$(network::summary network:services)" = "3 services" ]
  FZX_NETWORK_AVAHI_SOCKET="$BATS_TEST_TMPDIR/none" run network::applicable network:services
  [ "$status" -eq 1 ]
}

@test "under fzx: ctrl-o opens the process's files, copy takes the addresses, preview by mode" {
  stub_fzf
  run "$FZX" -m network
  [[ "$(fzf_bind ctrl-o)" == "ctrl-o:transform:$FZX _cb nav goto network:files --pid {1}" ]]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=2 "* && " ${FZF_ARGS[*]} " == *" --header-lines=1 "* ]]
  run env FZX_MODE=services NO_COLOR=1 "$NET/preview.sh" "_http._tcp|printer.local|192.168.1.20|80"
  [[ "$output" == *"printer.local"*"192.168.1.20:80"* ]]
  run env FZX_MODE=ports "$NET/preview.sh" "-/tcp/22"
  [[ "$output" == *"not yours"* ]]
}
