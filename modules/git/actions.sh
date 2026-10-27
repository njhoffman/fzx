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

# git::transform <into|view> [module args...] -- <id>
#   into: ctrl-o. Branches and tags open their log, log, reflog and stash entries the files the commit
#         changed, a work tree its status; each as a child session
#   view: alt-v. Status and commit previews switch between the diff and the blame
git::transform() {
  local name="${1:-}" view=""
  shift
  case "$name" in
    into)
      git::split "$@" || return
      local id="${GIT_IDS[0]:-}"
      [[ -n "$id" ]] || return 0
      fzx::require nav
      case "${FZX_MODE:-}" in
        branches | tags) fzx::nav goto git:log --rev "$id" "$GIT_TOP" ;;
        log | reflog | stash) fzx::nav goto git:commit --rev "$id" "$GIT_TOP" ;;
        worktrees) fzx::nav goto git:status "$id" ;;
        *) return 0 ;;
      esac
      ;;
    view)
      [[ "${FZX_MODE:-}" == status || "${FZX_MODE:-}" == commit ]] || return 0
      fzx::state_get git_view view 2> /dev/null || view=""
      if [[ "$view" == blame ]]; then view="diff"; else view="blame"; fi
      fzx::state_set git_view "$view"
      printf 'change-preview-label( %s )+refresh-preview' "$view"
      ;;
    *)
      printf 'git: unknown transform: %s\n' "$name" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && git::action "$@"
