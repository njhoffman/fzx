#!/usr/bin/env bash
# i3 actions. Windows and the scratchpad (con ids): focus, move (to a workspace, asked), scratch (to the
# scratchpad), float (toggle), kill, show (scratchpad); workspaces (names): switch, output (move to another
# output, asked), rename (asked).

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# i3::msg <command>: one i3 command; fails, saying i3's error, when i3 reports one
i3::msg() {
  local out
  out="$(command i3-msg -- "$1" 2>&1)" || { printf 'i3: %s\n' "$out" >&2; return 1; }
  [[ "$out" == *'"success":false'* ]] && { printf 'i3: %s: %s\n' "$1" "$out" >&2; return 1; }
  return 0
}

# i3::_q <text> <var>: the text as an i3 command string, double-quoted
i3::_q() {
  local _q="${1//\\/\\\\}"
  printf -v "$2" '"%s"' "${_q//\"/\\\"}"
}

# i3::action <name> [ids...]
i3::action() {
  local action="${1:-}" id dest q rc=0
  shift
  (($#)) || return 0
  case "$action" in
    focus | show)
      # the first one: focusing several leaves the last
      if [[ "$action" == show ]]; then i3::msg "[con_id=$1] scratchpad show" || rc=1; else i3::msg "[con_id=$1] focus" || rc=1; fi
      ;;
    move)
      fzx::require ask
      fzx::ask "$FZX_STATE_DIR/i3/workspaces" "move to the workspace:" dest || return 0
      i3::_q "$dest" q
      for id; do i3::msg "[con_id=$id] move container to workspace $q" || rc=1; done
      ;;
    scratch) for id; do i3::msg "[con_id=$id] move scratchpad" || rc=1; done ;;
    float) for id; do i3::msg "[con_id=$id] floating toggle" || rc=1; done ;;
    kill) for id; do i3::msg "[con_id=$id] kill" || rc=1; done ;;
    switch)
      i3::_q "$1" q
      i3::msg "workspace $q" || rc=1
      ;;
    output)
      local out
      fzx::require ask
      fzx::ask "$FZX_STATE_DIR/i3/outputs" "move workspace $1 to the output (left, right, or a name: $(command i3-msg -t get_outputs 2> /dev/null | command jq -r '[.[] | select(.active) | .name] | join(" ")')):" out || return 0
      i3::_q "$1" q
      i3::msg "workspace $q; move workspace to output $out" || rc=1
      ;;
    rename)
      local name n
      fzx::require ask
      fzx::ask "$FZX_STATE_DIR/i3/workspace-names" "rename workspace $1 to:" name || return 0
      i3::_q "$1" q
      i3::_q "$name" n
      i3::msg "rename workspace $q to $n" || rc=1
      ;;
    *)
      printf 'i3: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" i3
  i3::action "$@"
}
