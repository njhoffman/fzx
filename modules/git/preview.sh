#!/usr/bin/env bash
# git preview, by mode: a file's diff against HEAD (untracked files in full), a commit, a branch's
# recent history, or a stash.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# diffs go through FZX_GIT_DIFF_FILTER when set (e.g. delta)
git::diff_filter() {
  if [[ -n "${FZX_GIT_DIFF_FILTER:-}" ]]; then
    eval "$FZX_GIT_DIFF_FILTER"
  else
    cat
  fi
}

# git::preview [module args...] -- <id>
git::preview() {
  git::split "$@" || return
  local id="${GIT_IDS[0]:-}"
  case "${FZX_MODE:-status}" in
    status)
      if git::g ls-files --error-unmatch -- "$id" > /dev/null 2>&1; then
        { git::g diff --color=always --cached -- "$id"; git::g diff --color=always -- "$id"; } | git::diff_filter
      elif [[ -f "$id" ]]; then
        printf '\e[31muntracked\e[0m\n\n'
        command cat -- "$id"
      else
        printf 'deleted: %s\n' "$id"
      fi
      ;;
    log) git::g show --color=always --stat --patch "$id" -- | git::diff_filter ;;
    branches) git::g log --color=always --graph --oneline --decorate --max-count=40 "$id" -- ;;
    stash) git::g stash show --color=always --stat --patch "$id" | git::diff_filter ;;
    *)
      printf 'git: unknown mode: %s\n' "$FZX_MODE"
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && git::preview "$@"
