#!/usr/bin/env bash
# cron preview: an entry's command (highlighted as sh), its schedule, user and file, and its next runs from
# systemd-analyze; an anacron job's period, delay and last run; a script's file

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
# shellcheck source=../../lib/render.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/render.sh"

# cron::runs <count> <expr...>: the next runs of the expressions together, earliest first, in local time
# (read from systemd-analyze's UTC lines: zone abbreviations such as CST are ambiguous to date -d)
cron::runs() {
  local n="$1" e t
  shift
  for e in "$@"; do
    [[ -n "$e" ]] || continue
    command systemd-analyze calendar --iterations="$n" "$e" 2> /dev/null |
      awk '/\(in UTC\):/ { sub(/.*\(in UTC\): /, ""); print }'
  done | while IFS= read -r t; do command date -d "$t" +%s 2> /dev/null; done | sort -n -u | head -n "$n" |
    while IFS= read -r t; do command date -d "@$t" '+%a %Y-%m-%d %H:%M'; done
}

# cron::preview <id>
cron::preview() {
  local id="${1:-}" kind file line rec
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" x=$'\e['"${FZX_COLORS[cron_invalid]:-38;5;203}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" x="" r=""
  [[ -n "$id" ]] || return 0
  cron::split "$id" kind file line
  if [[ "$kind" == script ]]; then
    printf '%s%s%s\n' "$b" "$file" "$r"
    local dir="${file%/*}"
    printf '%srun by%s    run-parts %s (%s)\n' "$d" "$r" "$dir" "${dir##*/cron.}"
    cron::_ignored "${file##*/}" && printf '%s%s%s\n' "$x" "skipped: run-parts ignores names outside [A-Za-z0-9_-]" "$r"
    [[ -x "$file" ]] || printf '%s%s%s\n' "$x" "skipped: not executable" "$r"
    echo
    fzx::render_text --language sh --name "$file" -- "$file" 2> /dev/null || cat -- "$file"
    return 0
  fi
  rec="$(cron::record "$id")"
  [[ -n "$rec" ]] || { printf 'the entry is no longer at %s:%s\n' "$file" "$line"; return 0; }
  local _id _k user sched cmd e1 e2 state
  # (a tab is IFS whitespace: empty fields would merge)
  IFS=$'\x1f' read -r _id _k user sched cmd e1 e2 state <<< "${rec//$'\t'/$'\x1f'}"
  printf '%s\n' "$cmd" | fzx::render_text --language sh --style plain --wrap 2> /dev/null || printf '%s\n' "$cmd"
  echo
  if [[ "$state" == anacron:* ]]; then
    local period delay job last="" spool="${FZX_CRON_ANACRON_SPOOL:-/var/spool/anacron}"
    IFS=: read -r _ period delay job <<< "$state"
    [[ -e "$spool/$job" ]] && last="$(command date -d "@$(stat -c %Y "$spool/$job")" '+%a %Y-%m-%d %H:%M' 2> /dev/null)"
    printf '%speriod%s    %s\n' "$d" "$r" "$([[ "$period" =~ ^[0-9]+$ ]] && { ((period == 1)) && echo "every day" || echo "every $period days"; } || echo "$period")"
    printf '%sdelay%s     %s minutes after anacron starts\n' "$d" "$r" "$delay"
    printf '%sjob%s       %s\n' "$d" "$r" "$job"
    printf '%slast run%s  %s\n' "$d" "$r" "${last:-never (or unknown)}"
  else
    printf '%sschedule%s  %s\n' "$d" "$r" "$sched"
    printf '%suser%s      %s\n' "$d" "$r" "$user"
  fi
  printf '%sfile%s      %s\n' "$d" "$r" "$([[ "$file" == - ]] && echo "your crontab (crontab -e)" || echo "$file"):$line"
  case "$state" in
    disabled) printf '\n%sdisabled: commented out (alt-d enables it)%s\n' "$d" "$r" ;;
    reboot) printf '\n%sruns when cron starts (at boot)%s\n' "$d" "$r" ;;
    invalid) printf '\n%scron rejects this schedule%s\n' "$x" "$r" ;;
    anacron:*) ;;
    *)
      local runs
      runs="$(cron::runs "${FZX_CRON_PREVIEW_RUNS:-5}" "$e1" "$e2")"
      if [[ -n "$runs" ]]; then
        printf '\n%snext runs%s\n' "$d" "$r"
        local runl
        mapfile -t runl <<< "$runs"
        printf '  %s\n' "${runl[@]}"
      else
        printf '\n%snever runs (no such date)%s\n' "$d" "$r"
      fi
      [[ -n "$e2" ]] && printf '\n%sday of month or day of week: cron runs on either%s\n' "$d" "$r"
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" cron
  cron::preview "$@"
}
