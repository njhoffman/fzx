#!/usr/bin/env bash
# todos actions. edit and done take item ids ("file\x1fstart line\x1ftitle"); paste takes a tmux pane and
# the printable lines.
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# todos::done <id>: check the item's box, only when the line still holds that open item (the file may have
# changed since the list was read). The file is rewritten through a temporary file in its directory with
# its mode kept, then renamed over it.
todos::done() {
  local file start title found tmp
  IFS=$'\x1f' read -r file start title <<< "$1"
  [[ -f "$file" && "$start" =~ ^[0-9]+$ ]] || { printf 'todos: not an item id: %s\n' "$1" >&2; return 2; }
  found="$(todos::parse "$file" | awk -F'\t' -v n="$start" '$1 == n { print $4 }')"
  if [[ "$found" != "$title" ]] || ! sed -n "${start}p" "$file" | grep -q '^- \[ \] '; then
    printf 'todos: %s:%s is no longer the open item "%s" (the file changed; reload)\n' "$file" "$start" "$title" >&2
    return 1
  fi
  tmp="$(mktemp "${file%/*}/.todos-done.XXXXXX")" || return
  if ! awk -v n="$start" 'NR == n { sub(/^- \[ \] /, "- [x] ") } { print }' "$file" > "$tmp" ||
    ! chmod --reference="$file" -- "$tmp" || ! mv -f -- "$tmp" "$file"; then
    rm -f -- "$tmp"
    return 1
  fi
}

# todos::action <edit|done|paste> <args...>
todos::action() {
  local action="${1:-}" id file start _title pane editor
  shift
  case "$action" in
    edit)
      IFS=$'\x1f' read -r file start _title <<< "${1:-}"
      [[ -f "$file" ]] || return 0
      # $EDITOR can name a shell function (a script cannot run one): fall back to nvim, then vi
      read -ra editor <<< "${VISUAL:-${EDITOR:-vi}}"
      type -P "${editor[0]}" > /dev/null || editor=("$(type -P nvim || echo vi)")
      "${editor[@]}" "+$start" -- "$file"
      ;;
    done)
      for id in "$@"; do todos::done "$id" || return; done
      ;;
    paste)
      pane="${1:-}"
      shift
      [[ "$pane" =~ ^%[0-9]+$ ]] || { printf 'todos: --paste needs a tmux pane id (%%N): %s\n' "$pane" >&2; return 2; }
      (($#)) || return 0
      # bracketed paste: the lines arrive as typed text, nothing is submitted. The tmux server pastes 0.3s
      # later, not this process: in a popup (a pane of its own in tmux 3.9) the target's shell may still be
      # running the command that opened it, and /todo-pop's hook has not returned yet.
      printf '%s\n' "$@" | tmux load-buffer -b fzx-todos - &&
        tmux run-shell -b -d 0.3 "tmux paste-buffer -p -d -b fzx-todos -t $pane"
      ;;
    *)
      printf 'todos: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" todos
  todos::action "$@"
}
