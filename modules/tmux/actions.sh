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

# Actions receive the original module args, --, then selected IDs.
tmux::action() {
  local action="${1:-}" mode="${FZX_MODE:-sessions}" id value target
  shift
  tmux::args "$@" || return
  case "$action" in
    next-session | prev-session) tmux::cycle_session "$action"; return ;;
    scratch) tmux::helper popup-shell.sh; return ;;
    nvim-layout) tmux::helper nvim-layout.sh; return ;;
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
      # Reference and extraction screens never execute their rows as tmux commands.
      case "$mode" in sessions | windows | panes | buffers) ;; *) return 0 ;; esac
      for id in "${TMUX_IDS[@]}"; do
        tmux::object_id "$id" || { printf 'tmux: invalid %s id: %s\n' "$mode" "$id" >&2; return 2; }
      done
      ;;
    paste) ;;
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
      case "$mode" in buffers | lines | urls | paths | words | hashes | ips) ;; *) return 0 ;; esac
      [[ -n "$TMUX_TARGET_PANE" ]] || {
        printf 'tmux: paste needs --pane %%N or an invoking tmux pane\n' >&2
        return 2
      }
      if [[ "$mode" == buffers ]]; then
        for id in "${TMUX_IDS[@]}"; do
          command tmux paste-buffer -p -b "$id" -t "$TMUX_TARGET_PANE" || return
        done
      else
        # Give each callback a private buffer; no send-keys interpretation or Enter.
        local buffer="fzx-$BASHPID-$RANDOM" rc
        # A single pipeline feeds all selections, preserving their spaces and quotes.
        {
          printf '%s' "${TMUX_IDS[0]}"
          for id in "${TMUX_IDS[@]:1}"; do printf '\n%s' "$id"; done
        } | command tmux load-buffer -b "$buffer" - || return
        command tmux paste-buffer -p -d -b "$buffer" -t "$TMUX_TARGET_PANE"
        rc=$?
        ((rc == 0)) || command tmux delete-buffer -b "$buffer" 2> /dev/null
        return "$rc"
      fi
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
  fzx::nav goto tmux:lines --pane "$pane" --scope pane
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && tmux::action "$@"
