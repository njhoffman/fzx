#!/usr/bin/env bash
# cron menu entries, where crontab is installed (scripts: where a run-parts directory exists)

cron::manifest() {
  fzx::entry cron "Cron jobs, next run first"
  fzx::entry cron:user "Your crontab"
  fzx::entry cron:scripts "cron.daily and the other run-parts scripts"
}

cron::applicable() {
  case "$1" in
    cron:scripts) [[ -d /etc/cron.daily || -d /etc/cron.hourly ]] ;;
    *) command -v crontab > /dev/null ;;
  esac
}

# cron::summary <target>: how many entries (yours: or that there is no crontab)
cron::summary() {
  local n
  case "$1" in
    cron:user)
      n="$(command crontab -l 2> /dev/null | grep -cEv '^[[:space:]]*(#|$|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=)')" || :
      if command crontab -l > /dev/null 2>&1; then printf '%s entries\n' "${n:-0}"; else echo "no crontab"; fi
      ;;
    cron:scripts)
      n=0
      local d f
      for d in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
        for f in "$d"/*; do [[ -f "$f" && -x "$f" ]] && n=$((n + 1)); done
      done
      printf '%s scripts\n' "$n"
      ;;
  esac
}
