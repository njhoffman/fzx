#!/usr/bin/env bash
# git actions (bound with execute, in the foreground) and the ctrl-o transform.
# Each action applies to one mode and does nothing in the others, so one binding serves every mode.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# show a failure until a key is pressed; execute would otherwise wipe it at once
git::_report() {
  local rc="$1"
  ((rc == 0)) && return 0
  printf '\n\e[31mfailed (exit %s)\e[0m, press a key ' "$rc"
  IFS= read -rsn1 < /dev/tty || :
  return "$rc"
}

# git::action <stage|unstage|switch|edit> [module args...] -- <ids...>
git::action() {
  local action="${1:-}"
  shift
  git::split "$@" || return
  set -- "${GIT_IDS[@]}"
  (($#)) || return 0
  case "$action:${FZX_MODE:-status}" in
    stage:status) git::g add -- "$@" ;;
    unstage:status) git::g restore --staged -- "$@" ;;
    edit:status) "${EDITOR:-vi}" -- "$@" ;;
    switch:branches)
      local ref="${1:-}"
      if git::g show-ref --verify --quiet "refs/heads/$ref"; then
        git::g switch -- "$ref"
      else
        git::g switch --track -- "$ref"
      fi
      ;;
    stage:* | unstage:* | edit:* | switch:*) return 0 ;;
    *)
      printf 'git: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  git::_report $?
}

# git::transform into [module args...] -- <id>: branches open the branch's log as a child session
git::transform() {
  local name="${1:-}"
  shift
  case "$name" in
    into)
      git::split "$@" || return
      [[ "${FZX_MODE:-}" == branches && -n "${GIT_IDS[0]:-}" ]] || return 0
      fzx::require nav
      fzx::nav goto git:log --rev "${GIT_IDS[0]}" "$GIT_TOP"
      ;;
    *)
      printf 'git: unknown transform: %s\n' "$name" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && git::action "$@"
