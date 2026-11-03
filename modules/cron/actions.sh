#!/usr/bin/env bash
# cron actions on the selected ids. Your crontab is changed through `crontab -l` / `crontab -` (cron reads it
# again on its own); system files and scripts are only edited, through sudoedit. Running and disabling
# system entries is left out on purpose: they run as root, with cron's environment.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# cron::wait: keep the output on screen until a key (foreground actions return to fzf at once)
cron::wait() {
  [[ -t 1 ]] || return 0
  printf '\n\e[2m(press a key)\e[0m'
  read -rsn1 < /dev/tty || :
}

# cron::_command <command>: cron's command field as sh runs it: the part before the first unescaped % is
# the command, the rest its stdin with % as newlines (\% is a literal %). Prints the command, a NUL and
# the stdin
cron::_command() {
  awk 'BEGIN { RS = "\001" } {
    s = $0; sub(/\n$/, "", s); out = ""; input = ""; inp = 0
    for (i = 1; i <= length(s); i++) {
      ch = substr(s, i, 1)
      if (ch == "\\" && substr(s, i + 1, 1) == "%") { if (inp) input = input "%"; else out = out "%"; i++; continue }
      if (ch == "%") { if (inp) input = input "\n"; else inp = 1; continue }
      if (inp) input = input ch; else out = out ch
    }
    printf "%s%c%s", out, 0, input
  }' <<< "$1"
}

# cron::_toggle <line>: comment your crontab's line out, or back in
cron::_toggle() {
  local tab
  tab="$(command crontab -l 2> /dev/null)" || { printf 'cron: no crontab\n' >&2; return 1; }
  awk -v n="$1" 'NR == n { if ($0 ~ /^[[:space:]]*#/) sub(/^[[:space:]]*#+[[:space:]]*/, ""); else $0 = "#" $0 } { print }' \
    <<< "$tab" | command crontab -
}

# cron::action <action> <id...>
cron::action() {
  local action="${1:-}" id kind file line rec rc=0 cmd input
  shift
  case "$action" in
    edit)
      id="${1:-}"
      [[ -n "$id" ]] || return 0
      cron::split "$id" kind file line
      if [[ "$kind" == user ]]; then
        command crontab -e || { rc=$?; cron::wait; }
      else
        ((line > 0)) || line=1
        # the editor at the line, the file written back as root
        SUDO_EDITOR="${SUDO_EDITOR:-${VISUAL:-${EDITOR:-vi}}} +$line" command sudoedit -- "$file" || { rc=$?; cron::wait; }
      fi
      ;;
    disable)
      # commenting a line in or out moves no other line, so each id still names its line
      for id; do
        cron::split "$id" kind file line
        if [[ "$kind" != user ]]; then
          printf 'cron: only your crontab'"'"'s entries (edit system files with ctrl-e)\n' >&2
          rc=2
          continue
        fi
        rec="$(cron::record "$id")"
        [[ -n "$rec" ]] || { printf 'cron: line %s is no longer an entry\n' "$line" >&2; rc=1; continue; }
        cron::_toggle "$line" || rc=$?
      done
      ;;
    run)
      for id; do
        cron::split "$id" kind file line
        if [[ "$kind" != user ]]; then
          printf 'cron: %s runs as root: run it from a root shell\n' "$file:$line" >&2
          rc=2
          continue
        fi
        rec="$(cron::record "$id")"
        [[ -n "$rec" ]] || { printf 'cron: line %s is no longer an entry\n' "$line" >&2; rc=1; continue; }
        IFS=$'\t' read -r _ _ _ _ cmd _ <<< "$rec"
        { IFS= read -r -d '' cmd; IFS= read -r -d '' input; } < <(cron::_command "$cmd"; printf '\0')
        printf '\e[2m$ %s\e[0m\n' "$cmd"
        (cd ~ && /bin/sh -c "$cmd" <<< "$input") || rc=$?
      done
      ((rc)) && printf '\n\e[31mexit %s\e[0m' "$rc"
      cron::wait
      ;;
    *)
      printf 'cron: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" cron
  cron::action "$@"
}
