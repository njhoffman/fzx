#!/usr/bin/env bash
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

tmux::object_id() {
  case "${FZX_MODE:-sessions}" in
    sessions) [[ "$1" =~ ^\$[0-9]+$ ]] ;;
    windows) [[ "$1" =~ ^(\$[0-9]+:)?@[0-9]+$ ]] ;;
    panes) [[ "$1" =~ ^%[0-9]+$ ]] ;;
    buffers) [[ -n "$1" ]] ;;
    *) return 1 ;;
  esac
}

tmux::ask() {
  printf '%s' "$1" > /dev/tty
  IFS= read -r "$2" < /dev/tty
}

tmux::helper() {
  local script="$1"
  shift
  local path="${FZX_TMUX_HELPERS:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts}/$script"
  [[ -x "$path" ]] || { printf 'tmux: helper is not installed: %s\n' "$path" >&2; return 1; }
  "$path" "$@"
}

tmux::cycle_session() {
  local direction="$1" current id name index=-1 i sessions=() rows
  local prefix="${TMUX_SESSION_PREFIX:-${TMUX_PREFIX:-}}"
  local origin=()
  [[ -z "$TMUX_TARGET_PANE" ]] || origin=(-t "$TMUX_TARGET_PANE")
  current="$(command tmux display-message -p "${origin[@]}" '#{session_id}')" || return
  rows="$(command tmux list-sessions -F $'#{session_id}\t#{session_name}')" || return
  while IFS=$'\t' read -r id name; do
    [[ -z "$prefix" || "$name" == "$prefix"* ]] && sessions+=("$id")
  done <<< "$rows"
  ((${#sessions[@]})) || { printf 'tmux: no sessions match the prefix\n' >&2; return 1; }
  for i in "${!sessions[@]}"; do
    [[ "${sessions[i]}" != "$current" ]] || index="$i"
  done
  if [[ "$direction" == next-session ]]; then
    index=$(((index + 1) % ${#sessions[@]}))
  elif ((index < 0)); then
    index=$((${#sessions[@]} - 1))
  else
    index=$(((index + ${#sessions[@]} - 1) % ${#sessions[@]}))
  fi
  if [[ -n "${TMUX:-}" ]]; then
    command tmux switch-client -t "${sessions[index]}"
  else
    command tmux attach-session -t "${sessions[index]}"
  fi
}

# the whole reference list of a mode as plain text in nvim with tmux syntax (the tmux.* helpers' --nvim)
tmux::reference_nvim() {
  local mode="$1" file
  case "$mode" in
    keys | commands | options | variables | styles | formats | status | hooks) ;;
    *) printf 'tmux: nvim opens the reference lists (keys, commands, options, ...), not %s\n' "$mode" >&2; return 2 ;;
  esac
  file="$(mktemp "${TMPDIR:-/tmp}/fzx-tmux-$mode.XXXXXX")" || return
  tmux::reference list "$mode" | cut -f2 | sed $'s/\e\\[[0-9;:]*m//g' > "$file"
  "${FZX_TMUX_NVIM:-nvim}" -c 'setlocal buftype=nofile filetype=tmux' -- "$file"
  rm -f -- "$file"
}

# tmux::run_binding <metadata json>: keys mode, the first selection: the binding runs as if its key were
# pressed (send-keys -K on the client, after switch-client -T for a table other than root), so its command
# is parsed and targeted by tmux exactly as from the keyboard. fzx exits first (become): the replay waits
# FZX_TMUX_RUN_DELAY (0.3s) in a detached process, so a popup is gone before the key arrives. Copy-mode
# tables and unassigned keys are refused; a binding that kills something asks first, unless tmux's own
# confirm-before wraps it.
tmux::run_binding() {
  local table key command session client
  [[ -n "${TMUX:-}" ]] || { printf 'tmux: run needs to be inside tmux\n' >&2; return 2; }
  IFS=$'\t' read -r table key command < <(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
if d.get("unassigned") or not d.get("command"):
    sys.exit(1)
print(d["table"], d["key"], " ".join(d["command"].split()), sep="\t")' "$1") || {
    printf 'tmux: nothing is bound to that key\n' >&2
    return 2
  }
  case "$table" in
    copy-mode | copy-mode-vi) printf 'tmux: %s bindings run only in copy mode\n' "$table" >&2; return 2 ;;
  esac
  if [[ " $command" =~ [[:space:]\;]kill- && "$command" != confirm-before* ]]; then
    fzx::require builtin
    fzx::confirm "Run $table $key:" "$command" || return 0
  fi
  local origin=() detach=(setsid -f)
  [[ -z "$TMUX_TARGET_PANE" ]] || origin=(-t "$TMUX_TARGET_PANE")
  session="$(command tmux display-message -p "${origin[@]}" '#{session_id}')" || return
  # the session's most recently active client
  client="$(command tmux list-clients -t "$session" -F '#{client_activity} #{client_name}' | sort -rn | head -1)"
  client="${client#* }"
  [[ -n "$client" ]] || { printf 'tmux: no client is attached to %s\n' "$session" >&2; return 2; }
  command -v setsid > /dev/null || detach=(nohup)
  # shellcheck disable=SC2016  # expanded by the detached bash
  "${detach[@]}" bash -c '
    sleep "$1"
    [[ "$3" == root ]] || command tmux switch-client -c "$2" -T "$3"
    command tmux send-keys -K -c "$2" -- "$4"' _ "${FZX_TMUX_RUN_DELAY:-0.3}" "$client" "$table" "$key" \
    < /dev/null > /dev/null 2>&1 &
}

# Actions receive the original module args, --, then selected IDs.
tmux::action() {
  local action="${1:-}" mode="${FZX_MODE:-sessions}" id value target
  shift
  tmux::args "$@" || return
  case "$action" in
    next-session | prev-session) tmux::cycle_session "$action"; return ;;
    scratch) tmux::helper popup-shell.sh; return ;;
    nvim-layout) tmux::helper nvim-layout.sh; return ;;
    nvim) tmux::reference_nvim "$mode"; return ;;
    run)
      [[ "$mode" == keys ]] || return 0
      ((${#TMUX_IDS[@]})) || return 0
      tmux::run_binding "${TMUX_IDS[0]}"
      return
      ;;
    theme-main | theme-float)
      target="$TMUX_TARGET_PANE"
      case "$mode" in
        sessions | windows | panes)
          if ((${#TMUX_IDS[@]})); then
            tmux::object_id "${TMUX_IDS[0]}" || return 2
            target="${TMUX_IDS[0]}"
          fi
          ;;
      esac
      local origin=()
      [[ -z "$target" ]] || origin=(-t "$target")
      target="$(command tmux display-message -p "${origin[@]}" '#{session_id}')" || return
      tmux::helper apply-theme.sh "$target" "${action#theme-}"
      return
      ;;
  esac
  ((${#TMUX_IDS[@]})) || return 0
  case "$action" in
    switch | kill | rename | move | swap | link | mark)
      # Reference screens never execute their rows as tmux commands (run, above, replays a key instead).
      case "$mode" in sessions | windows | panes | buffers) ;; *) return 0 ;; esac
      for id in "${TMUX_IDS[@]}"; do
        tmux::object_id "$id" || { printf 'tmux: invalid %s id: %s\n' "$mode" "$id" >&2; return 2; }
      done
      ;;
    paste | edit) ;;
    *) printf 'tmux: unknown action: %s\n' "$action" >&2; return 2 ;;
  esac
  id="${TMUX_IDS[0]}"
  case "$action" in
    switch)
      [[ "$mode" == buffers ]] && return 0
      target="$id"
      if [[ "$mode" != sessions ]]; then
        target="$(command tmux display-message -p -t "$id" '#{session_id}')" || return
        command tmux select-window -t "$id" || return
        [[ "$mode" != panes ]] || command tmux select-pane -t "$id" || return
      fi
      if [[ -n "${TMUX:-}" ]]; then
        command tmux switch-client -t "$target"
      else
        command tmux attach-session -t "$target"
      fi
      ;;
    kill)
      for id in "${TMUX_IDS[@]}"; do
        case "$mode" in
          sessions) command tmux kill-session -t "$id" ;;
          windows) command tmux kill-window -t "$id" ;;
          panes) command tmux kill-pane -t "$id" ;;
          buffers) command tmux delete-buffer -b "$id" ;;
        esac || return
      done
      ;;
    rename)
      [[ "$mode" != buffers ]] || return 0
      tmux::ask "New name for $id (blank cancels): " value || return 0
      [[ -n "$value" ]] || return 0
      case "$mode" in
        sessions) command tmux rename-session -t "$id" -- "$value" ;;
        windows) command tmux rename-window -t "$id" -- "$value" ;;
        panes) command tmux select-pane -t "$id" -T "$value" ;;
      esac
      ;;
    move)
      case "$mode" in
        windows)
          tmux::ask "Destination session ID (\$N), optionally :INDEX (blank cancels): " value || return 0
          [[ -n "$value" ]] || return 0
          [[ "$value" =~ ^\$[0-9]+(:[0-9]+)?$ ]] || { printf 'tmux: invalid destination\n' >&2; return 2; }
          [[ "$value" == *:* ]] || value+=:
          command tmux move-window -s "$id" -t "$value"
          ;;
        panes)
          tmux::ask 'Destination pane ID (%N; blank cancels): ' value || return 0
          [[ -n "$value" ]] || return 0
          [[ "$value" =~ ^%[0-9]+$ ]] || { printf 'tmux: invalid destination\n' >&2; return 2; }
          command tmux move-pane -s "$id" -t "$value"
          ;;
      esac
      ;;
    swap)
      case "$mode" in windows | panes) ;; *) return 0 ;; esac
      tmux::ask 'Destination ID (@N for a window, %N for a pane; blank cancels): ' value || return 0
      [[ -n "$value" ]] || return 0
      tmux::object_id "$value" || { printf 'tmux: invalid destination\n' >&2; return 2; }
      if [[ "$mode" == windows ]]; then
        command tmux swap-window -s "$id" -t "$value"
      else
        command tmux swap-pane -s "$id" -t "$value"
      fi
      ;;
    link)
      [[ "$mode" == windows ]] || return 0
      tmux::ask "Destination session ID (\$N; blank cancels): " value || return 0
      [[ -n "$value" ]] || return 0
      [[ "$value" =~ ^\$[0-9]+$ ]] || { printf 'tmux: invalid destination\n' >&2; return 2; }
      command tmux link-window -a -s "$id" -t "$value:"
      ;;
    mark)
      [[ "$mode" == panes ]] || return 0
      command tmux select-pane -m -t "$id"
      ;;
    paste)
      [[ "$mode" == buffers ]] || return 0
      [[ -n "$TMUX_TARGET_PANE" ]] || {
        printf 'tmux: paste needs --pane %%N or an invoking tmux pane\n' >&2
        return 2
      }
      for id in "${TMUX_IDS[@]}"; do
        command tmux paste-buffer -p -b "$id" -t "$TMUX_TARGET_PANE" || return
      done
      ;;
    edit)
      # the buffers as paste would send them, edited first; emptied (or :cq) pastes nothing
      [[ "$mode" == buffers ]] || return 0
      [[ -n "$TMUX_TARGET_PANE" ]] || {
        printf 'tmux: edit needs --pane %%N or an invoking tmux pane\n' >&2
        return 2
      }
      fzx::require builtin
      fzx::edit_text value < <(for id in "${TMUX_IDS[@]}"; do command tmux show-buffer -b "$id"; done) || return 0
      target="fzx-edit-$BASHPID"
      printf '%s' "$value" | command tmux load-buffer -b "$target" - || return
      command tmux paste-buffer -p -d -b "$target" -t "$TMUX_TARGET_PANE" || {
        command tmux delete-buffer -b "$target" 2> /dev/null
        return 1
      }
      ;;
  esac
}

tmux::transform() {
  local verb="${1:-}" pane
  shift
  [[ "$verb" == capture ]] || return 2
  tmux::args "$@" || return
  case "${FZX_MODE:-sessions}" in sessions | windows | panes) ;; *) return 0 ;; esac
  [[ -n "${TMUX_IDS[0]:-}" ]] || return 0
  tmux::object_id "${TMUX_IDS[0]}" || return 2
  pane="$(command tmux display-message -p -t "${TMUX_IDS[0]}" '#{pane_id}')" || return
  fzx::require nav
  fzx::nav goto capture:lines --pane "$pane"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  tmux::action "$@"
}
