#!/usr/bin/env bash
# history preview: the full command, its latest run (time, status, duration, directory, host, session),
# how often it ran and failed, and the directories it ran in most
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# history::preview <history id>
history::preview() {
  local id="${1:-}" argv row when status secs dir host session runs failed first dirs
  local B=$'\e[1m' D=$'\e[2m' R=$'\e[0m' RED=$'\e[31m' YEL=$'\e[33m' MAG=$'\e[35m' GRN=$'\e[32m'
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

  case "$status" in
    0) status="${GRN}0${R}" ;;
    none) status="${MAG}unknown${R}" ;;
    *) status="${RED}${status}${R}" ;;
  esac
  if [[ -z "$secs" ]]; then secs="${MAG}unknown${R}"
  elif ((secs > 300)); then secs="${RED}${secs}s${R}"
  elif ((secs > 60)); then secs="${YEL}${secs}s${R}"
  else secs="${secs}s"; fi
  printf '%slast run%s   %s\n' "$B" "$R" "$when"
  printf '%sstatus%s     %s\n' "$B" "$R" "$status"
  printf '%sduration%s   %s\n' "$B" "$R" "$secs"
  printf '%sdirectory%s  %s\n' "$B" "$R" "${dir/#$HOME/\~}"
  printf '%shost%s       %s   %ssession %s%s\n' "$B" "$R" "$host" "$D" "$session" "$R"
  printf '%sruns%s       %s' "$B" "$R" "$runs"
  ((failed)) && printf '   %s%s failed%s' "$RED" "$failed" "$R"
  printf '   %ssince %s%s\n' "$D" "$first" "$R"

  dirs="$(history::sql "
    select count(*), places.dir from history h join places on places.id = h.place_id
    where h.command_id = (select command_id from history where id = $id)
    group by places.dir order by count(*) desc limit 8")"
  if [[ -n "$dirs" ]]; then
    printf '\n%sdirectories%s\n' "$B" "$R"
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
