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

  local P=$'\e[1;38;5;141m' W=$'\e[1;38;5;255m' C=$'\e[38;5;81m' B=$'\e[38;5;110m' G=$'\e[38;5;252m' R=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && P="" W="" C="" B="" G="" R=""
  local _pid ppid user etime cpu mem rss vsz nlwp stat lstart pcomm state word i
  # one ps call; lstart has spaces, so it comes last
  read -r _pid ppid user etime cpu mem rss vsz nlwp stat lstart < <(command ps -o pid=,ppid=,user=,etime=,%cpu=,%mem=,rss=,vsz=,nlwp=,stat=,lstart= -p "$pid")
  pcomm=""
  [[ -r "/proc/$ppid/comm" ]] && pcomm="$(< "/proc/$ppid/comm")"
  case "${stat:0:1}" in
    R) state="running" ;; S) state="sleeping" ;; D) state="disk wait" ;; Z) state="zombie" ;; T) state="stopped" ;;
    t) state="traced" ;; I) state="idle" ;; *) state="" ;;
  esac
  # labels with their icons (lib/icons.sh); lc is the label color
  local lc='38;5;244' l_pid l_parent l_user l_state l_threads l_started l_elapsed l_cpu l_mem l_rss l_vsz
  [[ -n "${NO_COLOR+x}" ]] && lc=""
  fzx::require icons
  fzx::icon_label command pid "$lc" l_pid
  fzx::icon_label parent parent "$lc" l_parent
  fzx::icon_label user user "$lc" l_user
  fzx::icon_label state state "$lc" l_state
  fzx::icon_label threads threads "$lc" l_threads
  fzx::icon_label clock started "$lc" l_started
  fzx::icon_label duration elapsed "$lc" l_elapsed
  fzx::icon_label cpu cpu "$lc" l_cpu
  fzx::icon_label memory mem "$lc" l_mem
  fzx::icon_label nothing rss "$lc" l_rss
  fzx::icon_label nothing vsz "$lc" l_vsz
  printf '%s %s%s%s  %s %s%s%s %s%s  %s %s%s%s\n' "$l_pid" "$P" "$pid" "$R" "$l_parent" "$P" "$ppid" "$R" \
    "$C" "${pcomm:+($pcomm)}$R" "$l_user" "$B" "$user" "$R"
  printf '%s %s%s %s%s  %s %s  %s %s  %s %s\n' "$l_state" "$W" "$stat" "$state" "$R" "$l_threads" "$nlwp" \
    "$l_started" "$lstart" "$l_elapsed" "$etime"
  printf '%s %s%%  %s %s%%  %s %s  %s %s\n' "$l_cpu" "$cpu" "$l_mem" "$mem" "$l_rss" "$(ps::human "$rss")" \
    "$l_vsz" "$(ps::human "$vsz")"

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
    local l_children
    fzx::icon_label parent children "$lc" l_children
    printf '\n%s\n' "$l_children"
    for child in "${children[@]}"; do
      comm="$(< "/proc/$child/comm")" 2> /dev/null || continue
      printf '  %s%-8s%s %s\n' "$P" "$child" "$R" "$comm"
    done
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  ps::preview "$@"
}
