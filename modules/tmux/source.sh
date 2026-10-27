#!/usr/bin/env bash
# Every mode emits id<TAB>display. IDs for tmux objects are stable across renames.

# shellcheck disable=SC2034  # TMUX_IDS is consumed by preview.sh and actions.sh
tmux::args() {
  declare -ga TMUX_IDS=()
  declare -g TMUX_TARGET_PANE="${FZX_TMUX_PANE:-${TMUX_PANE:-}}"
  declare -ga TMUX_REFERENCE_ARGS=()
  declare -g TMUX_SESSION_PREFIX="${FZX_TMUX_SESSION_PREFIX:-}"
  while (($#)); do
    case "$1" in
      --pane)
        [[ "${2:-}" =~ ^%[0-9]+$ ]] || {
          printf 'tmux: --pane needs a pane id (%%N)\n' >&2
          return 2
        }
        TMUX_TARGET_PANE="$2"
        shift 2
        ;;
      --table | --option-scope | --options-file | --data-file)
        [[ -n "${2:-}" && "$2" != -* ]] || { printf 'tmux: %s needs a value\n' "$1" >&2; return 2; }
        TMUX_REFERENCE_ARGS+=("$1" "$2"); shift 2
        ;;
      --user-only | --builtin-only) TMUX_REFERENCE_ARGS+=("$1"); shift ;;
      --prefix)
        [[ -n "${2:-}" ]] || { printf 'tmux: --prefix needs a session-name prefix\n' >&2; return 2; }
        TMUX_SESSION_PREFIX="$2"; shift 2
        ;;
      --) shift; TMUX_IDS=("$@"); return 0 ;;
      *) printf 'tmux: unknown argument: %s\n' "$1" >&2; return 2 ;;
    esac
  done
}

# Colors follow fzx's config layering; the Python helper only receives resolved values.
tmux::reference() {
  local role name
  local -a colors=()
  declare -gA FZX_COLORS
  for role in name value scope key changed dim title flag; do
    name="tmux_$role"
    [[ -z "${FZX_COLORS[$name]:-}" ]] || colors+=("FZX_TMUX_COLOR_${role^^}=${FZX_COLORS[$name]}")
  done
  command env "${colors[@]}" python3 "$(dirname "${BASH_SOURCE[0]}")/reference.py" "$@" \
    --pane "$TMUX_TARGET_PANE" "${TMUX_REFERENCE_ARGS[@]}"
}

# tmux::capture <pane>: the pane's screen as it shows now (copy mode's view when scrolled), for the
# sessions, windows and panes previews. Extraction from panes is the capture module.
tmux::capture() {
  local target=(-t "${1:-$TMUX_TARGET_PANE}") pos height
  [[ -n "${1:-$TMUX_TARGET_PANE}" ]] || target=()
  read -r height pos < <(command tmux display-message -p "${target[@]}" '#{pane_height} #{scroll_position}')
  [[ "$pos" =~ ^[0-9]+$ ]] || pos=0
  [[ "$height" =~ ^[1-9][0-9]*$ ]] || height=24
  command tmux capture-pane -p -J -S "$((-pos))" -E "$((height - 1 - pos))" "${target[@]}"
}

tmux::_source() {
  tmux::args "$@" || return
  local mode="${FZX_MODE:-sessions}"
  case "$mode" in
    sessions)
      local sessions id display
      sessions="$(command tmux list-sessions -F $'#{session_id}\t#{session_name}  #{session_windows} windows  #{?session_attached,attached,detached}')" || return
      while IFS=$'\t' read -r id display; do
        [[ -z "$TMUX_SESSION_PREFIX" || "$display" == "$TMUX_SESSION_PREFIX"* ]] && printf '%s\t%s\n' "$id" "$display"
      done <<< "$sessions"
      return 0
      ;;
    windows)
      command tmux list-windows -a -F $'#{session_id}:#{window_id}\t#{session_name}:#{window_index} #{window_name}  #{window_panes} panes  #{window_flags}'
      ;;
    panes)
      command tmux list-panes -a -F $'#{pane_id}\t#{session_name}:#{window_index}.#{pane_index} #{window_name}  #{pane_current_command}  #{pane_current_path}  #{pane_title}'
      ;;
    buffers)
      command tmux list-buffers -F $'#{buffer_name}\t#{buffer_name}  #{buffer_size} bytes  #{buffer_sample}'
      ;;
    *) printf 'tmux: unknown mode: %s\n' "$mode" >&2; return 2 ;;
  esac
}

tmux::source() {
  tmux::args "$@" || return
  local mode="${FZX_MODE:-sessions}"
  case "$mode" in
    keys | commands | options | variables | styles | formats | status | hooks)
      tmux::reference list "$mode"
      ;;
    *)
      tmux::_source "$@" | tmux::reference stream "$mode"
      local result=("${PIPESTATUS[@]}")
      ((result[0] == 0)) || return "${result[0]}"
      return "${result[1]}"
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && tmux::source "$@"
