#!/usr/bin/env bash
# cron actions on the selected ids. Your crontab is changed through `crontab -l` / `crontab -` (cron reads it
# again on its own), another user's through `sudo crontab -u USER`, system files through sudo (sed, chmod)
# and sudoedit. Run-now runs an entry as cron would: as its user, in its home, with only cron's environment
# (HOME, LOGNAME, SHELL=/bin/sh, PATH=/usr/bin:/bin, then the crontab's own VAR= lines).

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

# cron::_flip <line>: stdin with the line commented out, or back in
cron::_flip() {
  awk -v n="$1" 'NR == n { if ($0 ~ /^[[:space:]]*#/) sub(/^[[:space:]]*#+[[:space:]]*/, ""); else $0 = "#" $0 } { print }'
}

# cron::_sudo_n: CRON_SUDO, the prefix for a change in the background (disable: no terminal to ask on):
# none as root, `sudo -n` when it is cached; fails with a hint otherwise
cron::_sudo_n() {
  CRON_SUDO=(command)
  ((EUID == 0)) && return 0
  if command sudo -n true 2> /dev/null; then
    CRON_SUDO=(command sudo -n)
    return 0
  fi
  printf 'cron: needs root: run sudo -v first\n' >&2
  return 1
}

# cron::_toggle <kind> <file> <line>: comment the line out, or back in: your crontab through crontab,
# another user's through `sudo crontab -u`, a system file in place through sudo sed
cron::_toggle() {
  local kind="$1" file="$2" line="$3" tab u
  case "$kind" in
    user)
      tab="$(command crontab -l 2> /dev/null)" || { printf 'cron: no crontab\n' >&2; return 1; }
      cron::_flip "$line" <<< "$tab" | command crontab -
      ;;
    spool)
      cron::_sudo_n || return 1
      u="${file##*/}"
      tab="$("${CRON_SUDO[@]}" crontab -u "$u" -l 2> /dev/null)" || { printf 'cron: no crontab for %s\n' "$u" >&2; return 1; }
      cron::_flip "$line" <<< "$tab" | "${CRON_SUDO[@]}" crontab -u "$u" -
      ;;
    *)
      cron::_sudo_n || return 1
      if sed -n "${line}p" "$file" | grep -q '^[[:space:]]*#'; then
        "${CRON_SUDO[@]}" sed -i "${line}s/^[[:space:]]*#\{1,\}[[:space:]]*//" "$file"
      else
        "${CRON_SUDO[@]}" sed -i "${line}s/^/#/" "$file"
      fi
      ;;
  esac
}

# cron::_home <user>: the user's home from the password database (yours: $HOME when it has none)
cron::_home() {
  local h
  h="$(getent passwd "$1" 2> /dev/null | cut -d: -f6)"
  [[ -z "$h" && "$1" == "${USER:-$(id -un)}" ]] && h="$HOME"
  printf '%s\n' "${h:-/}"
}

# cron::_as <user> <command...>: run as the user: directly when that is who runs fzx, else through sudo
# (in the foreground: it may ask)
cron::_as() {
  local u="$1"
  shift
  if [[ "$u" == "$(id -un)" ]]; then "$@"; else command sudo -u "$u" "$@"; fi
}

# cron::_cron_env <user> <home> <crontab env lines...>: CRON_ENV, the environment cron gives a command:
# its own variables, then the crontab's (a later one wins); CRON_SHELL from SHELL
cron::_cron_env() {
  local u="$1" home="$2" kv
  shift 2
  local -A seen=()
  local -a order=()
  for kv in "HOME=$home" "LOGNAME=$u" "SHELL=/bin/sh" "PATH=/usr/bin:/bin" "$@"; do
    [[ "$kv" == *=* ]] || continue
    [[ -n "${seen[${kv%%=*}]+x}" ]] || order+=("${kv%%=*}")
    seen[${kv%%=*}]="${kv#*=}"
  done
  CRON_ENV=()
  for kv in "${order[@]}"; do CRON_ENV+=("$kv=${seen[$kv]}"); done
  CRON_SHELL="${seen[SHELL]:-/bin/sh}"
}

# cron::_run_entry <id>: one entry now, as its user, in its home, with cron's environment; % in the
# command starts its stdin; an anacron job through `anacron -d -f -n` (in the foreground, forced, no delay)
cron::_run_entry() {
  local id="$1" kind file line rec user cmd input state home envl=() job dir
  cron::split "$id" kind file line
  rec="$(cron::record "$id")"
  [[ -n "$rec" ]] || { printf 'cron: line %s is no longer an entry\n' "$line" >&2; return 1; }
  IFS=$'\x1f' read -r _ _ user _ cmd _ _ state <<< "${rec//$'\t'/$'\x1f'}"
  if [[ "$state" == anacron* ]]; then
    IFS=: read -r _ _ _ job <<< "$state"
    printf '\e[2m$ anacron -d -f -n %s\e[0m\n' "$job"
    cron::_as root anacron -d -f -n -t "$file" "$job"
    return
  fi
  { IFS= read -r -d '' cmd; IFS= read -r -d '' input; } < <(cron::_command "$cmd"; printf '\0')
  home="$(cron::_home "$user")"
  mapfile -t envl < <(cron::env "$id")
  cron::_cron_env "$user" "$home" "${envl[@]}"
  dir="$home"
  [[ -d "$dir" ]] || dir=/
  printf '\e[2m$ %s\e[0m\n\e[2m(as %s in %s, cron'"'"'s environment: %s)\e[0m\n' "$cmd" "$user" "$dir" "${CRON_ENV[*]}"
  cron::_as "$user" env -i -C "$dir" "${CRON_ENV[@]}" "$CRON_SHELL" -c "$cmd" <<< "$input"
}

# cron::_run_script <file>: a run-parts script now, as root from /, with the environment the first system
# crontab (/etc/crontab) gives its jobs
cron::_run_script() {
  local file="$1" f envl=()
  [[ -f "$file" ]] || { printf 'cron: no script %s\n' "$file" >&2; return 1; }
  for f in ${FZX_CRON_SYSTEM_FILES:-/etc/crontab /etc/cron.d}; do
    [[ -f "$f" ]] || continue
    mapfile -t envl < <(awk '/^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]*=[[:space:]]*/, "=", l); print l }' "$f")
    break
  done
  cron::_cron_env root "$(cron::_home root)" "${envl[@]}"
  printf '\e[2m$ %s\e[0m\n\e[2m(as root in /, cron'"'"'s environment: %s)\e[0m\n' "$file" "${CRON_ENV[*]}"
  cron::_as root env -i -C / "${CRON_ENV[@]}" "$file"
}

# cron::action <action> <id...>
cron::action() {
  local action="${1:-}" id kind file line rec rc=0
  shift
  case "$action" in
    edit)
      id="${1:-}"
      [[ -n "$id" ]] || return 0
      cron::split "$id" kind file line
      if [[ "$kind" == user ]]; then
        command crontab -e || { rc=$?; cron::wait; }
      elif [[ "$kind" == spool ]]; then
        command sudo crontab -u "${file##*/}" -e || { rc=$?; cron::wait; }
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
        if [[ "$kind" == script ]]; then
          # run-parts skips a script that is not executable
          cron::_sudo_n || { rc=1; continue; }
          if [[ -x "$file" ]]; then "${CRON_SUDO[@]}" chmod -x -- "$file" || rc=$?; else "${CRON_SUDO[@]}" chmod +x -- "$file" || rc=$?; fi
          continue
        fi
        rec="$(cron::record "$id")"
        [[ -n "$rec" ]] || { printf 'cron: line %s is no longer an entry\n' "$line" >&2; rc=1; continue; }
        cron::_toggle "$kind" "$file" "$line" || rc=$?
      done
      ;;
    run)
      for id; do
        cron::split "$id" kind file line
        if [[ "$kind" == script ]]; then
          cron::_run_script "$file" || rc=$?
        else
          cron::_run_entry "$id" || rc=$?
        fi
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
