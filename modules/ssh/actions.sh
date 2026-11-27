#!/usr/bin/env bash
# ssh actions on the selected targets ([user@]host): connect (a tmux window, else this terminal), here (this
# terminal), send and fetch (rsync, else scp; they ask the paths), copy-id (ssh-copy-id), edit (~/.ssh/config)

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# ssh::_here <target>: ssh on the terminal fzx was started from (FZX_TTY in tests)
ssh::_here() {
  local tty="${FZX_TTY:-/dev/tty}"
  command ssh "$1" <> "$tty" >&0 2>&0
}

# ssh::connect <target...>: each in a new tmux window named after its host (after the origin pane's window
# from the M-o popup); outside tmux the first one in this terminal
ssh::connect() {
  local t name rc=0
  if [[ -z "${TMUX:-}" ]] || ! command -v tmux > /dev/null; then
    ssh::_here "$1"
    return
  fi
  for t; do
    name="${t#*@}"
    name="${name%%.*}"
    if [[ -n "${FZX_ORIGIN_PANE:-}" ]]; then
      command tmux new-window -a -t "$FZX_ORIGIN_PANE" -n "$name" ssh "$t" || rc=1
    else
      command tmux new-window -n "$name" ssh "$t" || rc=1
    fi
  done
  return "$rc"
}

# ssh::_copy <from> <to>: rsync -a with its progress (FZX_SSH_RSYNC, when installed), else scp -r
ssh::_copy() {
  local rsync="${FZX_SSH_RSYNC-rsync}"
  if [[ -n "$rsync" ]] && command -v "$rsync" > /dev/null; then
    command "$rsync" -a --info=progress2 -- "$1" "$2"
  else
    command scp -r -- "$1" "$2"
  fi
}

# ssh::send <target>: a local path (asked, tab completes) to a directory there (asked, default ~)
ssh::send() {
  local path dest
  fzx::require ask
  fzx::ask "$FZX_STATE_DIR/ssh/send-paths" "send to $1, local path:" path || return 0
  path="${path/#\~/$HOME}"
  [[ -e "$path" ]] || { printf 'ssh: no such file or directory: %s\n' "$path" >&2; return 1; }
  fzx::ask "$FZX_STATE_DIR/ssh/send-dests" "into the directory on $1 (empty: ~):" dest || dest=""
  ssh::_copy "$path" "$1:${dest}"
}

# ssh::fetch <target>: a path there (asked) into a local directory (asked, default here)
ssh::fetch() {
  local path dest
  fzx::require ask
  fzx::ask "$FZX_STATE_DIR/ssh/fetch-paths" "fetch from $1, remote path:" path || return 0
  fzx::ask "$FZX_STATE_DIR/ssh/fetch-dests" "into the local directory (empty: $PWD):" dest || dest="."
  dest="${dest/#\~/$HOME}"
  ssh::_copy "$1:$path" "$dest"
}

# ssh::edit <target>: ~/.ssh/config in $EDITOR at the host's Host line, else at its end
ssh::edit() {
  local conf="${FZX_SSH_CONFIG:-$HOME/.ssh/config}" host="${1#*@}" line editor=()
  line="$([[ -f "$conf" ]] && awk -v h="$host" 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i == h) { print NR; exit } }' "$conf")"
  [[ -n "$line" ]] || line="$([[ -f "$conf" ]] && wc -l < "$conf" || echo 1)"
  read -ra editor <<< "${VISUAL:-${EDITOR:-vi}}"
  type -P "${editor[0]}" > /dev/null || editor=("$(type -P nvim || echo vi)")
  mkdir -p -- "${conf%/*}"
  "${editor[@]}" "+${line:-1}" -- "$conf"
}

# ssh::action <name> <targets...>
ssh::action() {
  local action="${1:-}"
  shift
  (($#)) || return 0
  case "$action" in
    connect) ssh::connect "$@" ;;
    here) ssh::_here "$1" ;;
    send) ssh::send "$1" ;;
    fetch) ssh::fetch "$1" ;;
    copy-id) command ssh-copy-id "$1" ;;
    edit) ssh::edit "$1" ;;
    *)
      printf 'ssh: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" ssh
  ssh::action "$@"
}
