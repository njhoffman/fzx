#!/usr/bin/env bash
# git preview, by mode: a file's diff against HEAD (untracked files in full), a commit, a branch's
# recent history, a tag, a stash, a work tree's status, or a file's change in a commit. In status and
# commit alt-v switches the file previews to blame (state/git_view, or FZX_GIT_VIEW standalone).

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# diffs go through FZX_GIT_DIFF_FILTER: "auto" (also when unset) is delta when installed, "" none
git::diff_filter() {
  local filter="${FZX_GIT_DIFF_FILTER-auto}"
  if [[ "$filter" == auto ]]; then
    if command -v delta > /dev/null; then
      command delta --paging=never --width="${FZF_PREVIEW_COLUMNS:-80}"
    else
      command cat
    fi
  elif [[ -n "$filter" ]]; then
    eval "$filter"
  else
    command cat
  fi
}

# git::view <var>: diff or blame
git::view() {
  local _v="${FZX_GIT_VIEW:-}"
  if [[ -z "$_v" && -n "${FZX_SESSION_DIR:-}" ]] && declare -F fzx::state_get > /dev/null; then
    fzx::state_get git_view _v 2> /dev/null || _v=""
  fi
  [[ "$_v" == blame ]] || _v="diff"
  printf -v "$1" '%s' "$_v"
}

# git::blame [rev] -- <path>: lines colored by age, newest brightest
git::blame() {
  git::g -c color.ui=always -c color.blame.highlightRecent='244,1 year ago,250,1 month ago,255' \
    blame --date=short --color-by-age "$@"
}

git::preview_status() {
  local id="$1" view="$2"
  if git::g ls-files --error-unmatch -- "$id" > /dev/null 2>&1; then
    if [[ "$view" == blame ]]; then
      git::blame -- "$id"
    else
      { git::g diff --color=always --cached -- "$id"; git::g diff --color=always -- "$id"; } | git::diff_filter
    fi
  elif [[ -f "$id" ]]; then
    printf '\e[31muntracked\e[0m\n\n'
    command cat -- "$id"
  else
    printf 'deleted: %s\n' "$id"
  fi
}

# a file of the --rev commit (orig: the name before a rename)
git::preview_commit() {
  local id="$1" orig="$2" view="$3" base rel="${1#"$GIT_TOP"/}"
  git::commit_base base
  if [[ "$view" == blame ]]; then
    if git::g cat-file -e "$GIT_REV:$rel" 2> /dev/null; then
      git::blame "$GIT_REV" -- "$rel"
    else
      printf 'deleted in %s: %s\n' "$GIT_REV" "$rel"
    fi
  elif [[ -n "$base" ]]; then
    git::g diff --color=always -M "$base" "$GIT_REV" -- ${orig:+"$orig"} "$rel" | git::diff_filter
  else
    git::g show --color=always --format= "$GIT_REV" -- "$rel" | git::diff_filter
  fi
}

# git::preview [module args...] -- <id> [extra]
git::preview() {
  git::split "$@" || return
  local id="${GIT_IDS[0]:-}" view
  git::view view
  case "${FZX_MODE:-status}" in
    status) git::preview_status "$id" "$view" ;;
    commit) git::preview_commit "$id" "${GIT_IDS[1]:-}" "$view" ;;
    log | reflog) git::g show --color=always --stat --patch "$id" -- | git::diff_filter ;;
    branches) git::g log --color=always --graph --oneline --decorate --max-count=40 "$id" -- ;;
    tags) git::g show --color=always --stat "$id" -- ;;
    stash) git::g stash show --color=always --stat --patch "$id" | git::diff_filter ;;
    worktrees)
      GIT_TOP="$id" git::g -c color.status=always status --short --branch
      printf '\n'
      GIT_TOP="$id" git::g log --color=always --oneline --decorate --max-count=20 --
      ;;
    *)
      printf 'git: unknown mode: %s\n' "$FZX_MODE"
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && git::preview "$@"
