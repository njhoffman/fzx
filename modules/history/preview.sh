#!/usr/bin/env bash
# history preview: the full command, its latest run (time, status, duration, directory, host, session),
# how often it ran and failed, and the directories it ran in most
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# history::preview <history id>
history::preview() {
  local id="${1:-}" argv row when status secs dir host session runs failed first dirs
  local B=$'\e[1m' D=$'\e[2m' R=$'\e[0m' RED=$'\e[31m' WHT=$'\e[38;5;255m' MAG=$'\e[35m' GRN=$'\e[32m'
  [[ "$id" =~ ^[0-9]+$ ]] || return 0
  argv="$(history::argv "$id" | tr -d '\0')"
  row="$(history::sql "
    select strftime('%Y-%m-%d %H:%M', h.start_time, 'unixepoch', 'localtime'), ifnull(h.exit_status, 'none'),
      ifnull(h.duration, ''), ifnull(places.dir, ''), ifnull(places.host, ''), h.session,
      (select count(*) from history where command_id = h.command_id),
      (select count(*) from history where command_id = h.command_id and exit_status != 0),
      (select strftime('%Y-%m-%d', min(start_time), 'unixepoch', 'localtime') from history where command_id = h.command_id)
    from history h left join places on places.id = h.place_id where h.id = $id")"
  IFS=$'\x1f' read -r when status secs dir host session runs failed first <<< "$row"

  if command -v bat > /dev/null; then
    printf '%s\n' "$argv" | command bat --color=always --style=plain --language=zsh --paging=never \
      --terminal-width="${FZF_PREVIEW_COLUMNS:-80}" --wrap=auto
  else
    printf '%s%s%s\n' "$B" "$argv" "$R"
  fi
  printf '%s%s%s\n' "$D" "$(printf '%*s' "${FZF_PREVIEW_COLUMNS:-60}" '' | tr ' ' '-')" "$R"

  local status_icon=failed
  case "$status" in 0) status_icon=ok ;; none) status_icon=state ;; esac
  case "$status" in
    0) status="${GRN}0${R}" ;;
    none) status="${MAG}unknown${R}" ;;
    *) status="${RED}${status}${R}" ;;
  esac
  if [[ -z "$secs" ]]; then secs="${MAG}unknown${R}"
  elif ((secs > 300)); then secs="${RED}${secs}s${R}"
  elif ((secs > 60)); then secs="${WHT}${secs}s${R}"
  else secs="${secs}s"; fi
  # labels with their icons (lib/icons.sh), padded to one width
  local lb=1 l_when l_status l_secs l_dir l_host l_runs
  [[ -n "${NO_COLOR+x}" ]] && lb=""
  fzx::require icons
  fzx::icon_label clock "last run " "$lb" l_when
  fzx::icon_label "$status_icon" "status   " "$lb" l_status
  fzx::icon_label duration "duration " "$lb" l_secs
  fzx::icon_label folder "directory" "$lb" l_dir
  fzx::icon_label host "host     " "$lb" l_host
  fzx::icon_label threads "runs     " "$lb" l_runs
  printf '%s  %s\n' "$l_when" "$when"
  printf '%s  %s\n' "$l_status" "$status"
  printf '%s  %s\n' "$l_secs" "$secs"
  printf '%s  %s\n' "$l_dir" "${dir/#$HOME/\~}"
  printf '%s  %s   %ssession %s%s\n' "$l_host" "$host" "$D" "$session" "$R"
  printf '%s  %s' "$l_runs" "$runs"
  ((failed)) && printf '   %s%s failed%s' "$RED" "$failed" "$R"
  printf '   %ssince %s%s\n' "$D" "$first" "$R"

  dirs="$(history::sql "
    select count(*), places.dir from history h join places on places.id = h.place_id
    where h.command_id = (select command_id from history where id = $id)
    group by places.dir order by count(*) desc limit 8")"
  if [[ -n "$dirs" ]]; then
    local l_dirs
    fzx::icon_label folder directories "$lb" l_dirs
    printf '\n%s\n' "$l_dirs"
    awk -F'\x1f' -v home="$HOME" -v dim="$D" -v rst="$R" '
      { d = $2; if (index(d, home) == 1) d = "~" substr(d, length(home) + 1); printf "  %s%5d%s  %s\n", dim, $1, rst, d }' <<< "$dirs"
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" history
  history::preview "$@"
}
