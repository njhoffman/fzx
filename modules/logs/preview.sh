#!/usr/bin/env bash
# logs preview: the last FZX_LOGS_LINES lines of a file, unit journal or container, following new lines
# while the row has focus (FZX_LOGS_PREVIEW_FOLLOW; fzf stops it on the next focus change, logs::_watch
# when fzf is gone or became something else). Files and
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
  [[ -z "${NO_COLOR:+x}" && ${#_cz[@]} -gt 0 ]] && command -v "${_cz[0]}" > /dev/null
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

# logs::_focused: the text of fzf's focused row, from its --listen socket (FZF_SOCK, or FZF_PORT); fails
# when there is no socket to ask or nothing answers (fzf exited, or became another program)
logs::_focused() {
  local out
  if [[ -n "${FZF_SOCK:-}" ]]; then
    out="$(command curl -s -m 1 --unix-socket "$FZF_SOCK" 'http://localhost?limit=0' 2> /dev/null)" || return 1
  elif [[ -n "${FZF_PORT:-}" ]]; then
    out="$(command curl -s -m 1 ${FZF_API_KEY:+-H "x-api-key: $FZF_API_KEY"} "http://localhost:$FZF_PORT?limit=0" 2> /dev/null)" || return 1
  else
    return 1
  fi
  command jq -r '.current.text // ""' <<< "$out" 2> /dev/null
}

# logs::_kill_tree <pid>: the process and everything under it (tail and the colorizer run in the
# pipeline's function subshells, so they are grandchildren)
logs::_kill_tree() {
  local c
  for c in $(command pgrep -P "$1" 2> /dev/null); do logs::_kill_tree "$c"; done
  kill -TERM "$1" 2> /dev/null
}

# logs::_watch <kind> <target> <pid>: stop the follow (pid) once its row loses focus or fzf stops answering.
# fzf ends a preview on a focus change, but not one left behind by become() or by fzf exiting: a follow
# of a quiet log never writes again, so it never gets the SIGPIPE that would end it
logs::_watch() {
  local want="$1"$'\t'"$2" cur
  while sleep "${FZX_LOGS_FOLLOW_CHECK:-2}"; do
    kill -0 "$3" 2> /dev/null || return 0
    cur="$(logs::_focused)" || break
    [[ "$cur" == "$want" || "$cur" == "$want"$'\t'* ]] || break
  done
  logs::_kill_tree "$3"
}

# logs::view <kind> <target> <follow 0|1>: the log as the preview and the follow action show it. A followed
# preview (_LOGS_PREVIEW set; not the follow action, which fzf runs with execute and cannot answer its socket
# meanwhile) under an fzf that can be asked what has focus (its --listen socket, curl and jq) is watched and
# stopped when it should be; elsewhere fzf alone ends it
logs::view() {
  local kind="$1" target="$2" follow="$3" pid watcher
  if ((follow)) && [[ -n "${_LOGS_PREVIEW:-}" && -n "${FZF_SOCK:-}${FZF_PORT:-}" && -z "${_LOGS_WATCHED:-}" ]] &&
    command -v curl > /dev/null && command -v jq > /dev/null; then
    _LOGS_WATCHED=1 logs::view "$@" &
    pid=$!
    logs::_watch "$kind" "$target" "$pid" &
    watcher=$!
    wait "$pid"
    kill "$watcher" 2> /dev/null
    return 0
  fi
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
  _LOGS_PREVIEW=1 logs::view "${1:-}" "${2:-}" "$([[ "${FZX_LOGS_PREVIEW_FOLLOW:-1}" == 1 ]] && echo 1 || echo 0)"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && logs::preview "$@"
