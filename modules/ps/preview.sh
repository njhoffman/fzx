#!/usr/bin/env bash
# ps preview: details, full command line and direct children for one pid.
# Reads /proc directly where possible; pstree and extra ps calls scan all of /proc and cost 100ms+ each.

# ps::human <kb>: 512K, 88M, 1.2G
ps::human() {
  awk -v kb="$1" 'BEGIN { if (kb !~ /^[0-9]+$/) print kb; else if (kb < 1024) print kb "K"
    else if (kb < 1048576) printf "%.0fM\n", kb / 1024; else printf "%.1fG\n", kb / 1048576 }'
}

# ps::preview <pid>
ps::preview() {
  local pid="${1:-}" cmdline child comm children=()
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    printf 'not a pid: %s\n' "$pid"
    return 1
  fi
  if [[ ! -d "/proc/$pid" ]]; then
    printf 'process %s has exited\n' "$pid"
    return 0
  fi

  local L=$'\e[38;5;244m' P=$'\e[1;38;5;141m' W=$'\e[1;38;5;255m' C=$'\e[38;5;81m' B=$'\e[38;5;110m' G=$'\e[38;5;252m' R=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && L="" P="" W="" C="" B="" G="" R=""
  local _pid ppid user etime cpu mem rss vsz nlwp stat lstart pcomm state word i
  # one ps call; lstart has spaces, so it comes last
  read -r _pid ppid user etime cpu mem rss vsz nlwp stat lstart < <(command ps -o pid=,ppid=,user=,etime=,%cpu=,%mem=,rss=,vsz=,nlwp=,stat=,lstart= -p "$pid")
  pcomm=""
  [[ -r "/proc/$ppid/comm" ]] && pcomm="$(< "/proc/$ppid/comm")"
  case "${stat:0:1}" in
    R) state="running" ;; S) state="sleeping" ;; D) state="disk wait" ;; Z) state="zombie" ;; T) state="stopped" ;;
    t) state="traced" ;; I) state="idle" ;; *) state="" ;;
  esac
  printf '%spid%s %s%s%s  %sparent%s %s%s%s %s%s  %suser%s %s%s%s\n' "$L" "$R" "$P" "$pid" "$R" "$L" "$R" "$P" "$ppid" "$R" \
    "$C" "${pcomm:+($pcomm)}$R" "$L" "$R" "$B" "$user" "$R"
  printf '%sstate%s %s%s %s%s  %sthreads%s %s  %sstarted%s %s  %selapsed%s %s\n' "$L" "$R" "$W" "$stat" "$state" "$R" \
    "$L" "$R" "$nlwp" "$L" "$R" "$lstart" "$L" "$R" "$etime"
  printf '%scpu%s %s%%  %smem%s %s%%  %srss%s %s  %svsz%s %s\n' "$L" "$R" "$cpu" "$L" "$R" "$mem" "$L" "$R" \
    "$(ps::human "$rss")" "$L" "$R" "$(ps::human "$vsz")"

  printf '\n'
  mapfile -d '' -t cmdline < "/proc/$pid/cmdline" 2> /dev/null
  if ((${#cmdline[@]})); then
    # the program bold, options blue, paths light grey, one argument per word as the list colors them
    printf '%s%s%s' "$W" "${cmdline[0]}" "$R"
    for ((i = 1; i < ${#cmdline[@]}; i++)); do
      word="${cmdline[i]}"
      if [[ "$word" == -* ]]; then printf ' %s%s%s' "$B" "$word" "$R"
      elif [[ "$word" == */* ]]; then printf ' %s%s%s' "$G" "$word" "$R"
      else printf ' %s' "$word"; fi
    done
    printf '\n'
  else
    printf '%s[%s]%s\n' "$C" "$(< "/proc/$pid/comm")" "$R"
  fi

  read -r -a children < <(cat "/proc/$pid/task/"*/children 2> /dev/null)
  if ((${#children[@]})); then
    printf '\n%schildren%s\n' "$L" "$R"
    for child in "${children[@]}"; do
      comm="$(< "/proc/$child/comm")" 2> /dev/null || continue
      printf '  %s%-8s%s %s\n' "$P" "$child" "$R" "$comm"
    done
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && ps::preview "$@"
