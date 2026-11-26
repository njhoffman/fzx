#!/usr/bin/env bash
# claude actions on project paths, and the background scan (claude::transform refresh)

[[ -n "${_FZX_CORE_LOADED:-}" ]] || source "${FZX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/core.sh"
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# claude::wait: keep output on screen until a key (foreground actions return to fzf at once)
claude::wait() {
  [[ -t 1 ]] || return 0
  printf '\n\e[2m(press a key)\e[0m'
  read -rsn1 < /dev/tty || :
}

# claude::launch <claude args> <dir...>: Claude Code in each directory. The actions run through become(),
# so fzf (and a popup around it) is gone once they return; nothing goes to stdout, which would be fzx's
# result. In tmux with FZX_CLAUDE_WORKSPACE installed: `workspace claude [--continue] DIR` per project,
# which goes to the Claude already running there (its terminal gets the focus) or starts one in the
# project's main-<name> session, made when missing. In tmux without it: a new window per project named
# after it. Elsewhere in this terminal, the first directory only.
# <claude args> is one word list, split on spaces ("" for none, "--continue").
claude::launch() {
  local args="$1" dir cmd ws="${FZX_CLAUDE_WORKSPACE:-}"
  shift
  read -ra cmd <<< "${FZX_CLAUDE_CMD:-claude} $args"
  if [[ -n "${TMUX:-}" ]] && command -v tmux > /dev/null; then
    if [[ -n "$ws" && -x "$ws" ]]; then
      local opts=()
      [[ " $args " == *" --continue "* ]] && opts=(--continue)
      for dir in "$@"; do
        "$ws" claude "${opts[@]}" "$dir" >&2 || return
      done
      return 0
    fi
    for dir in "$@"; do
      tmux new-window -c "$dir" -n "${dir##*/}" -- "${cmd[@]}" >&2
    done
    return 0
  fi
  (($# > 1)) && printf 'claude: not in tmux: starting in %s only\n' "${1/#$HOME/\~}" >&2
  (cd -- "$1" && "${cmd[@]}")
}

# claude::transform refresh: bound as start:+bg-transform; a reload when the scan changed the cache
claude::transform() {
  case "${1:-}" in
    refresh)
      # fzx::cb lives in lib/opts.sh, which a callback does not load by itself
      fzx::require opts
      claude::refresh && printf 'reload:%s' "$(fzx::cb source)"
      ;;
    *)
      printf 'claude: unknown transform: %s\n' "${1:-}" >&2
      return 2
      ;;
  esac
  return 0
}

# claude::action <claude|resume|edit|card|rescan> <dir...>
claude::action() {
  local action="${1:-}" dir
  shift
  if [[ "$action" == rescan ]]; then
    printf 'scanning Claude Code projects...\n'
    claude::refresh force || :
    return 0
  fi
  [[ -n "${1:-}" ]] || return 0
  for dir in "$@"; do
    [[ -d "$dir" ]] || { printf 'claude: no such directory: %s\n' "$dir" >&2; return 2; }
  done
  case "$action" in
    claude) claude::launch "" "$@" ;;
    resume) claude::launch --continue "$@" ;;
    edit) (cd -- "$1" && ${EDITOR:-nvim} .) ;;
    card)
      command -v claude-projects > /dev/null || { printf 'claude: claude-projects is not on PATH\n' >&2; return 127; }
      for dir in "$@"; do
        claude-projects show --pretty "$dir"
        printf '\n'
      done | ${PAGER:-less -R}
      ;;
    *)
      printf 'claude: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" claude
  claude::action "$@"
}
