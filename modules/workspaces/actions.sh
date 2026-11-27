#!/usr/bin/env bash
# workspaces actions on the selected keys (session names, or recent directories' roots)
#   open:   workspace open KEY (the first), on WORKSPACE_CLIENT when set, else this client
#   reset:  workspace reset --yes NAME, each open session (it is rebuilt from its layout)
#   kill:   each open session, through family-stay.sh kill (its clients stay in the family)
#   forget: workspace forget DIR, each recent directory

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# workspaces::state <key>: the state `workspace type` gives the key (open or closed)
workspaces::state() {
  local cmd line
  cmd="$(workspaces::cmd)" || return 1
  line="$("$cmd" type "$1" 2> /dev/null)" || return 1
  printf '%s' "${line##*$'\t'}"
}

workspaces::action() {
  local action="${1:-}" cmd key rc=0 stay
  shift
  [[ "${1:-}" == -- ]] && shift
  cmd="$(workspaces::cmd)" || { printf 'workspaces: no workspace command (FZX_WORKSPACE_CMD)\n' >&2; return 2; }
  case "$action" in
    open)
      [[ -n "${1:-}" ]] || return 0
      "$cmd" open ${WORKSPACE_CLIENT:+-c "$WORKSPACE_CLIENT"} "$1"
      ;;
    reset | kill)
      stay="$(dirname "$(readlink -f "$cmd")")/family-stay.sh"
      for key; do
        if [[ "$key" == /* || "$(workspaces::state "$key")" != open ]]; then
          printf 'workspaces: %s is not an open session\n' "$key" >&2
          rc=1
          continue
        fi
        if [[ "$action" == reset ]]; then
          "$cmd" reset --yes ${WORKSPACE_CLIENT:+-c "$WORKSPACE_CLIENT"} "$key" || rc=1
        elif [[ -x "$stay" ]]; then
          "$stay" kill "$key" || rc=1
        else
          command tmux kill-session -t "=$key" || rc=1
        fi
      done
      ;;
    forget)
      for key; do
        if [[ "$key" != /* ]]; then
          printf 'workspaces: %s is a session, not a recent directory\n' "$key" >&2
          rc=1
          continue
        fi
        "$cmd" forget "$key" || rc=1
      done
      ;;
    *)
      printf 'workspaces: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" workspaces
  workspaces::action "$@"
}
