#!/usr/bin/env bash
# logs preview: the last FZX_LOGS_LINES lines of a file, unit journal or container, following new lines
# while the row has focus (FZX_LOGS_PREVIEW_FOLLOW, fzf stops it on the next focus change). Files and
# containers go through FZX_LOGS_COLORIZER (ccze -A by default), journals keep systemd's own colors, and a
# unit's journal has the top of its `systemctl status` above it, FZX_LOGS_STATUS_LINES lines and a rule:
# the units mode pins those lines as the preview's sticky header (module.sh).
# shellcheck source=../../lib/render.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/render.sh"

# logs::show <kind> <target> <follow 0|1>: print (or follow) a log
logs::show() {
  local kind="$1" target="$2" follow="$3" lines="${FZX_LOGS_LINES:-200}" f=()
  ((follow)) && f=(-f)
  case "$kind" in
    file)
      if ((follow)); then
        command tail -n "$lines" -F -- "$target"
      else
        command tail -n "$lines" -- "$target"
      fi
      ;;
    unit-user | unit-system)
      SYSTEMD_COLORS=1 command journalctl "--${kind#unit-}" -u "$target" -n "$lines" --no-pager "${f[@]}"
      ;;
    docker) command docker logs --tail "$lines" "${f[@]}" "$target" 2>&1 ;;
    *)
      printf 'logs: unknown kind: %s\n' "$kind" >&2
      return 2
      ;;
  esac
}

# logs::colorizer <var>: the colorizer command (an array) when it can run, else fails. FZX_LOGS_COLORIZER
# unset means ccze -A, an empty array means none.
logs::colorizer() {
  local -n _cz="$1"
  if declare -p FZX_LOGS_COLORIZER &> /dev/null; then
    _cz=("${FZX_LOGS_COLORIZER[@]}")
  else
    _cz=(ccze -A)
  fi
  [[ -z "${NO_COLOR+x}" && ${#_cz[@]} -gt 0 ]] && command -v "${_cz[0]}" > /dev/null
}

# logs::colorize: stdin through the colorizer, line by line so a followed log shows each line as it comes
# (stdbuf for C programs such as ccze, PYTHONUNBUFFERED for grcat); plain when there is none
logs::colorize() {
  local cz=()
  if logs::colorizer cz; then
    if command -v stdbuf > /dev/null; then
      PYTHONUNBUFFERED=1 command stdbuf -oL "${cz[@]}"
    else
      PYTHONUNBUFFERED=1 command "${cz[@]}"
    fi
  else
    command cat
  fi
}

# logs::status <unit-user|unit-system> <unit>: the top of the unit's status (the cgroup's process tree left
# out), exactly FZX_LOGS_STATUS_LINES lines, then a dim rule
logs::status() {
  local n="${FZX_LOGS_STATUS_LINES:-8}" width="${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}" rule
  SYSTEMD_COLORS=1 command systemctl "--${1#unit-}" status "$2" --no-pager -n 0 2> /dev/null |
    awk -v n="$n" '
      { plain = $0; gsub(/\033\[[0-9;]*m/, "", plain) }
      plain ~ /^ *(├|└|│)/ || plain ~ /^ *Invocation:/ || plain ~ /^ *$/ { next }
      k < n { print; k++ }
      END { for (; k < n; k++) print "" }'
  printf -v rule '%*s' "$width" ''
  printf '\e[%sm%s\e[0m\n' "${FZX_COLORS[dim]:-38;5;240}" "${rule// /─}"
}

# logs::view <kind> <target> <follow 0|1>: the log as the preview and the follow action show it
logs::view() {
  local kind="$1" target="$2" follow="$3"
  case "$kind" in
    file | docker)
      local cz=()
      if [[ "$kind" == file ]] && ! logs::colorizer cz && ! ((follow)); then
        # no colorizer: bat's log highlighting, which needs the whole text
        logs::show "$kind" "$target" 0 | fzx::render_text --language log --style plain
      else
        logs::show "$kind" "$target" "$follow" | logs::colorize
      fi
      ;;
    unit-user | unit-system)
      logs::status "$kind" "$target"
      logs::show "$kind" "$target" "$follow"
      ;;
    *) logs::show "$kind" "$target" "$follow" ;;
  esac
}

# logs::preview <kind> <target>
logs::preview() {
  logs::view "${1:-}" "${2:-}" "$([[ "${FZX_LOGS_PREVIEW_FOLLOW:-1}" == 1 ]] && echo 1 || echo 0)"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && logs::preview "$@"
