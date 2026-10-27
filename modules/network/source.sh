#!/usr/bin/env bash
# network source: a header row, then "id<TAB>copy text<TAB>display" per row. Mode from $FZX_MODE: ports
# (default), connections, interfaces, routes, wifi, services, files (--pid PID). $FZX_SORT: ports by port
# (default) or process, connections by remote (default) or process, wifi by signal (default) or name,
# services by name; the sorted column is drawn in FZX_COLORS[sorted] as well. $FZX_TOGGLES: "root" runs ss
# and lsof through `sudo -n` (every process is named; without a cached sudo the header says so).
# ids: ports and connections PID/PROTO/PORT (PID "-" when the process is not visible), interfaces the
# name, routes "DEST dev DEV" (as `ip route show` takes it), wifi the BSSID, services TYPE|HOST|ADDR|PORT,
# files the file name.

# network::_root: NETWORK_SUDO, the prefix that runs ss and lsof: `sudo -n` when the root toggle is on and
# sudo is cached, else nothing (NETWORK_NOROOT=1 when root was asked for but sudo needs a password)
network::_root() {
  NETWORK_SUDO=(command) NETWORK_NOROOT=""
  [[ " ${FZX_TOGGLES:-} " == *" root "* && "$EUID" -ne 0 ]] || return 0
  if command sudo -n true 2> /dev/null; then NETWORK_SUDO=(command sudo -n); else NETWORK_NOROOT=1; fi
}

# network::_awk_lib: awk functions every table shares: c(code, text) colors (NO_COLOR: none), col(i,
# code, text, right) pads to w[i] and adds hl to the text of the sorted column scol
network::_awk_lib() {
  cat << 'AWK'
function c(code, text) { return nocolor != "" || text == "" ? text : "\033[" code "m" text "\033[0m" }
function pad(text, w, right) { return right ? sprintf("%" w "s", text) : sprintf("%-" w "s", text) }
function col(i, code, text, right,  p) {
  p = pad(text, w[i], right)
  if (i != scol || text == "") return c(code, p)
  return (right ? substr(p, 1, length(p) - length(text)) : "") c(code ";" hl, text) (right ? "" : substr(p, length(text) + 1))
}
function widths(n, cols,  r, i) { for (r = 0; r <= n; r++) for (i = 1; i <= cols; i++) if (length(t[r, i]) > w[i]) w[i] = length(t[r, i]) }
AWK
}

# network::_vars: the awk -v options of every table
network::_vars() {
  NETWORK_VARS=(-v "nocolor=${NO_COLOR+x}" -v "hl=${FZX_COLORS[sorted]:-4}" -v "dim=${FZX_COLORS[dim]:-38;5;244}"
    -v "name=${FZX_COLORS[network_name]:-1;38;5;255}" -v "up=${FZX_COLORS[network_up]:-38;5;114}"
    -v "down=${FZX_COLORS[network_down]:-38;5;203}" -v "port=${FZX_COLORS[network_port]:-1;38;5;141}"
    -v "addr=${FZX_COLORS[network_addr]:-38;5;152}" -v "me=${USER:-$(id -un)}")
}

# network::sockets <ports|connections> <sort>: ss's sockets with their processes and the processes' users
network::sockets() {
  local mode="$1" sort="$2" out pids users scol
  network::_root
  if [[ "$mode" == ports ]]; then
    out="$("${NETWORK_SUDO[@]}" ss -H -tulpn)" || return
    case "$sort" in process) scol=4 ;; *) scol=3 ;; esac
  else
    out="$("${NETWORK_SUDO[@]}" ss -H -tupn state established)" || return
    case "$sort" in process) scol=4 ;; *) scol=3 ;; esac
  fi
  # the users of the processes, one ps call for all of them
  pids="$(grep -o 'pid=[0-9]*' <<< "$out" | cut -d= -f2 | sort -u | paste -sd,)"
  users=""
  [[ -n "$pids" ]] && users="$(command ps -o pid=,user= -p "$pids" 2> /dev/null)"
  network::_vars
  awk "${NETWORK_VARS[@]}" -v mode="$mode" -v sort="$sort" -v scol="$scol" -v users="$users" -v noroot="${NETWORK_NOROOT:-}" "$(network::_awk_lib)"'
    # hostport(a, hp): split "addr:port" (IPv6 in brackets, an interface after %) at its last colon
    function hostport(a, hp,  i) { i = match(a, /:[^:]*$/); hp[1] = substr(a, 1, i - 1); hp[2] = substr(a, i + 1) }
    BEGIN {
      FS = " +"
      n = split(users, u, "\n"); for (i = 1; i <= n; i++) { split(u[i], f, " +"); if (f[1] == "") { f[1] = f[2]; f[2] = f[3] } owner[f[1]] = f[2] }
    }
    {
      # ports: netid state recv send local peer [process]; connections (a state filter): no state column
      lc = mode == "ports" ? 5 : 4
      proc = ""; pid = "-"; more = 0
      for (i = lc + 2; i <= NF; i++) proc = proc (proc == "" ? "" : " ") $i
      if (match(proc, /"[^"]*"/)) { pname = substr(proc, RSTART + 1, RLENGTH - 2) } else pname = ""
      if (match(proc, /pid=[0-9]+/)) pid = substr(proc, RSTART + 4, RLENGTH - 4)
      more = gsub(/pid=/, "", proc) - 1
      hostport($lc, l); hostport($(lc + 1), p)
      r++
      t[r, 1] = $1; t[r, 2] = mode == "ports" ? l[1] : $lc; t[r, 3] = mode == "ports" ? l[2] : $(lc + 1)
      t[r, 4] = pname (more > 0 ? " +" more : ""); t[r, 5] = pid; t[r, 6] = pid == "-" ? "" : owner[pid]
      id[r] = pid "/" $1 "/" l[2]; cp[r] = mode == "ports" ? $lc : $(lc + 1)
      key[r] = sort == "process" ? (pname == "" ? "~" : tolower(pname)) sprintf(" %06d", l[2]) : mode == "ports" ? sprintf("%06d %s", l[2], $1) : $(lc + 1)
    }
    END {
      if (mode == "ports") split("PROTO ADDRESS PORT PROCESS PID USER", h, " ")
      else split("PROTO LOCAL REMOTE PROCESS PID USER", h, " ")
      for (i = 1; i <= 6; i++) t[0, i] = h[i]
      widths(r, 6)
      line = ""
      for (i = 1; i <= 6; i++) line = line col(i, "1;38;5;245", h[i], i == 5) " "
      if (noroot != "") line = line c(dim, "(root: run sudo -v first)")
      print "-\t-\t" line
      for (i = 1; i <= r; i++) order[i] = i
      # insertion sort by key (lists are short)
      for (i = 2; i <= r; i++) { v = order[i]; for (j = i - 1; j >= 1 && key[order[j]] > key[v]; j--) order[j + 1] = order[j]; order[j + 1] = v }
      for (k = 1; k <= r; k++) {
        i = order[k]
        o = t[i, 6]
        line = col(1, dim, t[i, 1]) " " col(2, addr, t[i, 2]) " " col(3, mode == "ports" ? port : addr, t[i, 3]) " "
        line = line col(4, t[i, 4] == "" ? dim : name, t[i, 4]) " " col(5, dim, t[i, 5], 1) " "
        line = line col(6, o == "root" ? down : o == me ? "38;5;110" : "38;5;81", o)
        print id[i] "\t" cp[i] "\t" line
      }
    }' <<< "$out"
}

# network::interfaces: ip's brief addresses joined with the links' MAC addresses
network::interfaces() {
  network::_vars
  awk "${NETWORK_VARS[@]}" "$(network::_awk_lib)"'
    FNR == NR { mac[$1] = $3; next }
    {
      r++; t[r, 1] = $1; t[r, 2] = $2; a = ""; first = ""
      for (i = 3; i <= NF; i++) { a = a (a == "" ? "" : " ") $i; if (first == "" && $i ~ /\./) first = $i }
      if (first == "" && NF >= 3) first = $3
      sub(/\/.*/, "", first)
      t[r, 3] = a; t[r, 4] = mac[$1]; cp[r] = first == "" ? $1 : first
    }
    END {
      split("NAME STATE ADDRESSES MAC", h, " "); for (i = 1; i <= 4; i++) t[0, i] = h[i]
      widths(r, 4)
      print "-\t-\t" col(1, "1;38;5;245", h[1]) " " col(2, "1;38;5;245", h[2]) " " col(3, "1;38;5;245", h[3]) " " c("1;38;5;245", h[4])
      for (i = 1; i <= r; i++) {
        s = t[i, 2]
        print t[i, 1] "\t" cp[i] "\t" col(1, name, t[i, 1]) " " col(2, s == "UP" ? up : s == "DOWN" ? down : dim, s) " " col(3, addr, t[i, 3]) " " c(dim, t[i, 4])
      }
    }' <(command ip -br link) <(command ip -br addr)
}

# network::routes: IPv4 then IPv6 routes as columns (the rest of the line, proto/scope/metric, dim)
network::routes() {
  network::_vars
  { command ip route; command ip -6 route 2> /dev/null; } |
    awk "${NETWORK_VARS[@]}" "$(network::_awk_lib)"'
      {
        r++; dest = $1; via = ""; dev = ""; src = ""; rest = ""
        for (i = 2; i <= NF; i++) {
          if ($i == "via") via = $(++i)
          else if ($i == "dev") dev = $(++i)
          else if ($i == "src") src = $(++i)
          else rest = rest (rest == "" ? "" : " ") $i
        }
        t[r, 1] = dest; t[r, 2] = via; t[r, 3] = dev; t[r, 4] = src; t[r, 5] = rest
        id[r] = dest (dev == "" ? "" : " dev " dev)
      }
      END {
        split("DESTINATION VIA DEV SRC OPTIONS", h, " "); for (i = 1; i <= 5; i++) t[0, i] = h[i]
        widths(r, 5)
        line = ""; for (i = 1; i <= 4; i++) line = line col(i, "1;38;5;245", h[i]) " "
        print "-\t-\t" line c("1;38;5;245", h[5])
        for (i = 1; i <= r; i++)
          print id[i] "\t" t[i, 1] "\t" col(1, t[i, 1] == "default" ? port : addr, t[i, 1]) " " col(2, name, t[i, 2]) " " col(3, up, t[i, 3]) " " col(4, addr, t[i, 4]) " " c(dim, t[i, 5])
      }'
}

# network::wifi <sort>: nmcli's networks in range (its last scan); the one in use marked
network::wifi() {
  local sort="$1" scol=3
  [[ "$sort" == name ]] && scol=2
  network::_vars
  command nmcli -t -f IN-USE,BSSID,SSID,CHAN,RATE,SIGNAL,SECURITY device wifi list --rescan no |
    awk "${NETWORK_VARS[@]}" -v sort="$sort" -v scol="$scol" "$(network::_awk_lib)"'
      function bars(s) { return s >= 75 ? "▂▄▆█" : s >= 50 ? "▂▄▆_" : s >= 25 ? "▂▄__" : "▂___" }
      {
        # nmcli -t escapes the colons in a field (the BSSID) as \:
        gsub(/\\:/, "\001"); split($0, f, ":"); for (i in f) gsub("\001", ":", f[i])
        r++; on[r] = f[1] == "*"; t[r, 1] = on[r] ? "*" : ""; t[r, 2] = f[3] == "" ? "--" : f[3]
        t[r, 3] = f[6] "% " bars(f[6]); t[r, 4] = f[4]; t[r, 5] = f[5]; t[r, 6] = f[7]; id[r] = f[2]; sig[r] = f[6]
        key[r] = sort == "name" ? tolower(t[r, 2]) sprintf(" %03d", 100 - f[6]) : sprintf("%03d %s", 100 - f[6], tolower(t[r, 2]))
      }
      END {
        split("_ SSID SIGNAL CHAN RATE SECURITY", h, " "); h[1] = ""; for (i = 1; i <= 6; i++) t[0, i] = h[i]
        widths(r, 6)
        line = ""; for (i = 1; i <= 5; i++) line = line col(i, "1;38;5;245", h[i]) " "
        print "-\t-\t" line c("1;38;5;245", h[6])
        for (i = 1; i <= r; i++) order[i] = i
        for (i = 2; i <= r; i++) { v = order[i]; for (j = i - 1; j >= 1 && key[order[j]] > key[v]; j--) order[j + 1] = order[j]; order[j + 1] = v }
        for (k = 1; k <= r; k++) {
          i = order[k]; s = sig[i]
          print id[i] "\t" (t[i, 2] == "--" ? "" : t[i, 2]) "\t" col(1, up, t[i, 1]) " " col(2, on[i] ? up ";1" : t[i, 2] == "--" ? dim : name, t[i, 2]) " " \
            col(3, s >= 50 ? up : s >= 25 ? "38;5;221" : down, t[i, 3]) " " col(4, dim, t[i, 4], 1) " " col(5, dim, t[i, 5]) " " c(t[i, 6] == "" ? down : dim, t[i, 6] == "" ? "open" : t[i, 6])
        }
      }'
}

# network::services_cache <var>: the cache file of the mDNS browse, browsed again when missing or older than
# FZX_NETWORK_SERVICES_TTL. One row per service (IPv4 preferred over IPv6): name, type, host, address,
# port, TXT records, tab-separated.
network::services_cache() {
  local _file="$FZX_CACHE_DIR/network/services" _ttl _mtime
  printf -v "$1" '%s' "$_file"
  fzx::parse_duration "${FZX_NETWORK_SERVICES_TTL:-10m}" _ttl || _ttl=600
  if [[ -f "$_file" ]]; then
    _mtime="$(stat -c %Y -- "$_file")"
    ((EPOCHSECONDS - _mtime < _ttl)) && return 0
  fi
  mkdir -p -- "${_file%/*}"
  timeout "${FZX_NETWORK_SERVICES_TIMEOUT:-8}" avahi-browse -artpk 2> /dev/null |
    awk -F';' '
      # avahi escapes a name byte as \DDD (decimal) and a dot or backslash with a backslash
      function unescape(s,  out, i, ch) {
        out = ""
        for (i = 1; i <= length(s); i++) {
          ch = substr(s, i, 1)
          if (ch == "\\" && substr(s, i + 1, 3) ~ /^[0-9][0-9][0-9]$/) { out = out sprintf("%c", substr(s, i + 1, 3) + 0); i += 3 }
          else if (ch == "\\") { out = out substr(s, i + 1, 1); i++ }
          else out = out ch
        }
        return out
      }
      $1 == "=" {
        k = $4 SUBSEP $5
        if ((k in row) && !(v6[k] && $3 == "IPv4")) next
        txt = $10; for (i = 11; i <= NF; i++) txt = txt ";" $i
        gsub(/\t/, " ", txt)
        if (!(k in row)) order[++n] = k
        row[k] = unescape($4) "\t" $5 "\t" $7 "\t" $8 "\t" $9 "\t" txt; v6[k] = $3 == "IPv6"
      }
      END { for (i = 1; i <= n; i++) print row[order[i]] }' > "$_file.$$"
  mv -f -- "$_file.$$" "$_file"
}

# network::services: the cached mDNS services, by name
network::services() {
  local file
  network::services_cache file
  network::_vars
  sort -f -t $'\t' -k1,1 -- "$file" |
    awk -F'\t' "${NETWORK_VARS[@]}" -v scol=1 "$(network::_awk_lib)"'
      # a service without a port (device-info records) has nothing to connect to
      $5 == 0 { next }
      { r++; t[r, 1] = length($1) > 40 ? substr($1, 1, 39) "…" : $1; t[r, 2] = $2; t[r, 3] = $3; t[r, 4] = $4 ":" $5; id[r] = $2 "|" $3 "|" $4 "|" $5; cp[r] = $3 ":" $5 }
      END {
        split("NAME TYPE HOST ADDRESS", h, " "); for (i = 1; i <= 4; i++) t[0, i] = h[i]
        widths(r, 4)
        print "-\t-\t" col(1, "1;38;5;245", h[1]) " " col(2, "1;38;5;245", h[2]) " " col(3, "1;38;5;245", h[3]) " " c("1;38;5;245", h[4])
        for (i = 1; i <= r; i++) print id[i] "\t" cp[i] "\t" col(1, name, t[i, 1]) " " col(2, t[i, 2] ~ /^_https?\._tcp$/ ? up : dim, t[i, 2]) " " col(3, addr, t[i, 3]) " " c(port, t[i, 4])
      }'
}

# network::files <pid>: lsof's open files of the process (its sockets included)
network::files() {
  local pid="${1%%/*}"
  # a row whose process is not visible (or no row at all): say so in the list instead of failing the load
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    printf -- '-\t-\tno visible process%s: pick a row with a PID, or turn on root (sudo -n) first\n' "${1:+ for ${1#*/}}"
    return 0
  fi
  network::_vars
  network::_root
  # lsof's field output (-F): an f line starts each file, t its type, n its name
  "${NETWORK_SUDO[@]}" lsof -n -P -w -p "$pid" -F ftn |
    awk "${NETWORK_VARS[@]}" -v noroot="${NETWORK_NOROOT:-}" "$(network::_awk_lib)"'
      /^f/ { r++; t[r, 1] = substr($0, 2) }
      /^t/ && r { t[r, 2] = substr($0, 2) }
      /^n/ && r { t[r, 3] = substr($0, 2) }
      END {
        split("FD TYPE NAME", h, " "); for (i = 1; i <= 3; i++) t[0, i] = h[i]
        widths(r, 3)
        print "-\t-\t" col(1, "1;38;5;245", h[1]) " " col(2, "1;38;5;245", h[2]) " " c("1;38;5;245", h[3]) (noroot != "" ? " " c(dim, "(root: run sudo -v first)") : "")
        for (i = 1; i <= r; i++) {
          ty = t[i, 2]
          print t[i, 3] "\t" t[i, 3] "\t" col(1, dim, t[i, 1]) " " col(2, ty ~ /^IPv/ ? port : ty == "REG" ? name : dim, ty) " " c(ty ~ /^IPv/ ? addr : "", t[i, 3])
        }
      }'
}

# network::source [--pid PID]
network::source() {
  local mode="${FZX_MODE:-ports}" pid=""
  while (($#)); do
    case "$1" in
      --pid)
        pid="${2:-}"
        shift
        ;;
      *)
        printf 'network: unknown argument: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done
  case "$mode" in
    ports) network::sockets ports "${FZX_SORT:-port}" ;;
    connections) network::sockets connections "${FZX_SORT:-remote}" ;;
    interfaces) network::interfaces ;;
    routes) network::routes ;;
    wifi) network::wifi "${FZX_SORT:-signal}" ;;
    services) network::services ;;
    files) network::files "$pid" ;;
    *)
      printf 'network: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  [[ -n "${_FZX_CORE_LOADED:-}" ]] || source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  network::source "$@"
}
