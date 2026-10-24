#!/usr/bin/env bash
# Every mode emits id<TAB>display. IDs for tmux objects are stable across renames.

# shellcheck disable=SC2034  # TMUX_IDS is consumed by preview.sh and actions.sh
tmux::args() {
  declare -ga TMUX_IDS=()
  declare -g TMUX_TARGET_PANE="${FZX_TMUX_PANE:-${TMUX_PANE:-}}"
  declare -g TMUX_CAPTURE_SCOPE="${FZX_TMUX_SCOPE:-pane}"
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
      --scope)
        case "${2:-}" in pane | window | session | all) ;; *) printf 'tmux: invalid --scope\n' >&2; return 2 ;; esac
        TMUX_CAPTURE_SCOPE="$2"; shift 2
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

tmux::capture() {
  local pane="${1:-$TMUX_TARGET_PANE}" lines="${FZX_TMUX_LINES:-2000}"
  [[ "$lines" =~ ^[1-9][0-9]*$ ]] || {
    printf 'tmux: FZX_TMUX_LINES must be a positive integer\n' >&2
    return 2
  }
  local target=()
  [[ -n "$pane" ]] && target=(-t "$pane")
  local bounds=(-S "-$lines")
  if [[ " ${FZX_TOGGLES:-} " == *' visible '* ]]; then
    local pos height
    read -r height pos < <(command tmux display-message -p "${target[@]}" '#{pane_height} #{scroll_position}')
    [[ "$pos" =~ ^[0-9]+$ ]] || pos=0
    [[ "$height" =~ ^[1-9][0-9]*$ ]] || height=24
    bounds=(-S "$((-pos))" -E "$((height - 1 - pos))")
  fi
  command tmux capture-pane -p -J "${bounds[@]}" "${target[@]}"
}

# Plain capture keeps text literal: no command execution or automatic pasting.
tmux::extract() {
  case "$1" in
    lines) awk 'NF { gsub(/\t/, "    "); print $0 "\t" $0 }' ;;
    urls)
      awk '{
        while (match($0, /(https?|ftp|file):\/\/[^[:space:]<>"\047]+/)) {
          s = substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH)
          sub(/[.,;!?)\]}]+$/, "", s)
          if (!seen[s]++) print s "\t" s
        }
      }'
      ;;
    paths)
      awk '{
        for (i = 1; i <= NF; i++) {
          s = $i
          if (s ~ /:\/\//) continue
          sub(/^[\047"(<\[]+/, "", s); sub(/[\047")>\],;]+$/, "", s)
          if ((s ~ /\// || s ~ /^[[:alnum:]_-]+\.[[:alnum:]_.-]+(:[0-9]+)*$/) &&
              s ~ /^[~./[:alnum:]_-]/ && !seen[s]++) print s "\t" s
        }
      }'
      ;;
    words | hashes | ips)
      awk -v kind="$1" '{
        pattern = kind == "words" ? "[[:alnum:]_]+([.-][[:alnum:]_]+)*" :
          kind == "hashes" ? "[[:xdigit:]]+" : "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"
        while (match($0, pattern)) {
          s = substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH)
          if (kind == "hashes" && (length(s) < 7 || length(s) > 64 || s !~ /[a-fA-F]/)) continue
          if (kind == "ips") {
            split(s, parts, "."); valid = 1
            for (i = 1; i <= 4; i++) if (parts[i] > 255) valid = 0
            if (!valid) continue
          }
          if (!seen[s]++) print s "\t" s
        }
      }'
      ;;
  esac
}

tmux::captured_rows() {
  local mode="$1" pane panes out scope=() target=()
  [[ -n "$TMUX_TARGET_PANE" ]] && target=(-t "$TMUX_TARGET_PANE")
  case "$TMUX_CAPTURE_SCOPE" in
    pane)
      panes="${TMUX_TARGET_PANE:-$(command tmux display-message -p '#{pane_id}')}"
      [[ -n "$panes" ]] || return 1
      ;;
    *)
      case "$TMUX_CAPTURE_SCOPE" in session) scope=(-s) ;; all) scope=(-a) ;; esac
      panes="$(command tmux list-panes "${scope[@]}" "${target[@]}" -F '#{pane_id}')" || return
      ;;
  esac
  local rows="" part
  while IFS= read -r pane; do
    out="$(tmux::capture "$pane")" || return
    part="$(printf '%s\n' "$out" | tmux::extract "$mode" | awk -v pane="$pane" '
      { p = index($0, "\t"); print substr($0, 1, p) pane "  " substr($0, p + 1) }')"
    [[ -z "$part" ]] || rows+="$part"$'\n'
  done <<< "$panes"
  printf '%s' "$rows" | awk -F '\t' '!seen[$1]++'
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
    lines | urls | paths | words | hashes | ips) tmux::captured_rows "$mode" ;;
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
