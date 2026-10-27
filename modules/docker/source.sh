#!/usr/bin/env bash
# docker source: "id<TAB>display" per mode. containers (running first, state colored; toggle running: only
# running ones), images (dangling ones dim), volumes (unused ones dim), networks, compose (projects).
# The id is what docker commands take: container/image/network ID, volume name, compose project name.
# $FZX_SORT: containers by state (running first, default) or name; images by created (newest first,
# default), size or name. The sorted column is drawn in FZX_COLORS[sorted] as well.

# docker::color <name> <default SGR>: an escape sequence from FZX_COLORS
docker::color() { printf '\e[%sm' "${FZX_COLORS[$1]:-$2}"; }

docker::source() {
  local dim rst=$'\e[0m' run pause stop name hl="${FZX_COLORS[sorted]:-4}" sort="${FZX_SORT:-}"
  command -v docker > /dev/null || { printf 'docker: the docker command is not installed\n' >&2; return 2; }
  dim="$(docker::color dim '38;5;244')" name="$(docker::color docker_name '1;38;5;111')"
  run="$(docker::color docker_running '38;5;114')" pause="$(docker::color docker_paused '38;5;252')"
  stop="$(docker::color docker_stopped '38;5;203')"
  case "${FZX_MODE:-containers}" in
    containers)
      local all=(-a)
      [[ " ${FZX_TOGGLES:-} " == *" running "* ]] && all=()
      fzx::require icons
      fzx::icon_vars running paused stopped created
      command docker ps "${all[@]}" --format '{{.ID}}\t{{.State}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' |
        awk -F'\t' "${FZX_ICON_VARS[@]}" -v dim="$dim" -v rst="$rst" -v name="$name" -v run="$run" -v pause="$pause" -v stop="$stop" \
          -v sort="${sort:-state}" -v hl=$'\e['"${hl}m" '
          # cell(color, text, width, sorted): text padded to width; the sorted column adds hl to the text
          function cell(color, text, w, on) { return on ? color hl text rst sprintf("%" (w - length(text) > 0 ? w - length(text) : 0) "s", "") : color sprintf("%-" w "s", text) rst }
          { c = ($2 == "running") ? run : ($2 == "paused" || $2 == "restarting") ? pause : stop
            i = ($2 == "running") ? icon_running : ($2 == "paused" || $2 == "restarting") ? icon_paused : ($2 == "created") ? icon_created : icon_stopped
            if (i == "") i = "●"
            # state: running ones first, docker order (newest first) within each group; name: by name
            key = sort == "name" ? tolower($3) : ($2 == "running" ? 0 : 1)
            printf "%s\t%s\t%s%s%s %s %-34s %s %s%s%s\n", key, $1, c, i, rst, cell(name, $3, 28, sort == "name"), $4, cell(c, $5, 24, sort == "state"), dim, $6, rst }' |
        LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
      ;;
    images)
      local dangling
      dangling=" $(command docker images -q --filter dangling=true | tr '\n' ' ') "
      command docker images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}\t{{.Size}}' |
        awk -F'\t' -v dim="$dim" -v rst="$rst" -v name="$name" -v dangling="$dangling" -v sort="${sort:-created}" -v hl=$'\e['"${hl}m" '
          function cell(color, text, w, on) { return on ? color hl text rst sprintf("%" (w - length(text) > 0 ? w - length(text) : 0) "s", "") : color sprintf("%-" w "s", text) rst }
          # docker size ("1.2GB", "350MB", "0B") in bytes
          function bytes(s,  n, u) { n = s + 0; u = s; sub(/^[0-9.]+/, "", u)
            return n * (u == "kB" ? 1e3 : u == "MB" ? 1e6 : u == "GB" ? 1e9 : u == "TB" ? 1e12 : 1) }
          { ref = ($2 == "<none>") ? "<none>" : $2 ":" $3
            # created: docker order (newest first); size: largest first; name: by repository and tag
            key = sort == "size" ? sprintf("%016d", 1e15 - bytes($5)) : sort == "name" ? (ref == "<none>" ? "~" : tolower(ref)) : sprintf("%08d", NR)
            c = index(dangling, " " $1 " ") ? dim : name
            printf "%s\t%s\t%s %s%-14s%s %s %s\n", key, $1, cell(c, ref, 48, sort == "name"), dim, $1, rst,
              cell(dim, $4, 16, sort == "created"), cell(c == dim ? dim : "", $5, 0, sort == "size") }' |
        LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
      ;;
    volumes)
      local unused
      unused=" $(command docker volume ls -q --filter dangling=true | tr '\n' ' ') "
      command docker volume ls --format '{{.Name}}\t{{.Driver}}\t{{.Mountpoint}}' |
        awk -F'\t' -v dim="$dim" -v rst="$rst" -v name="$name" -v unused="$unused" '
          { u = index(unused, " " $1 " ") ? "unused" : "in use"
            shown = length($1) > 44 ? substr($1, 1, 12) "…" substr($1, length($1) - 30) : $1
            printf "%s\t%s%-44s%s %-8s %s%-7s %s%s\n", $1, (u == "unused" ? dim : name), shown, rst, $2, dim, u, $3, rst }'
      ;;
    networks)
      command docker network ls --format '{{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}' |
        awk -F'\t' -v dim="$dim" -v rst="$rst" -v name="$name" '
          { printf "%s\t%s%-32s%s %-10s %s%-6s %s%s\n", $1, name, $2, rst, $3, dim, $4, $1, rst }'
      ;;
    compose)
      docker compose version > /dev/null 2>&1 || { printf 'docker: docker compose is not installed\n' >&2; return 2; }
      command docker compose ls -a --format json | docker::compose_rows "$dim" "$rst" "$name" "$run" "$stop"
      ;;
    *)
      printf 'docker: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

# docker::compose_rows <colors...>: `docker compose ls --format json` (one array) -> rows, without jq
docker::compose_rows() {
  python3 -c '
import json, sys
dim, rst, name, run, stop = sys.argv[1:6]
try:
    projects = json.load(sys.stdin) or []
except ValueError:
    projects = []
for p in projects:
    project, status, files = p.get("Name", ""), p.get("Status", ""), p.get("ConfigFiles", "")
    color = run if status.startswith("running") else stop
    print(f"{project}\t{name}{project:<28}{rst} {color}{status:<20}{rst} {dim}{files}{rst}")
' "$@"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" docker
  docker::source "$@"
}
