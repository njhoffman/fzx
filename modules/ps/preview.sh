#!/usr/bin/env bash
# ps preview: details, full command line and direct children for one pid.
# Reads /proc directly where possible; pstree and extra ps calls scan all of /proc and cost 100ms+ each.

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

  command ps -o pid,ppid,user,lstart,etime,%cpu,%mem,rss,vsz,nlwp,stat -p "$pid"

  printf '\n'
  mapfile -d '' -t cmdline < "/proc/$pid/cmdline" 2> /dev/null
  if ((${#cmdline[@]})); then
    printf '%s\n' "${cmdline[*]}"
  else
    printf '[%s]\n' "$(< "/proc/$pid/comm")"
  fi

  read -r -a children < <(cat "/proc/$pid/task/"*/children 2> /dev/null)
  if ((${#children[@]})); then
    printf '\nchildren:\n'
    for child in "${children[@]}"; do
      comm="$(< "/proc/$child/comm")" 2> /dev/null || continue
      printf '  %-8s %s\n' "$child" "$comm"
    done
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && ps::preview "$@"
