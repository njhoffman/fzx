#!/usr/bin/env bash
# git: status, log, branches, tags, stash, reflog and work trees of a repository.
# `fzx -m git[:log|:branches|:tags|:stash|:reflog|:worktrees] [--all] [--rev REV] [DIR]`; `git:commit
# --rev REV` (ctrl-o on a commit) lists the files it changed. Enter prints paths, hashes or names.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# "repo  branch  ↑ahead ↓behind upstream" for the header
git::header() {
  local branch upstream counts ahead behind header
  branch="$(git::g symbolic-ref --quiet --short HEAD 2> /dev/null || git::g rev-parse --short HEAD)"
  header="${GIT_TOP##*/}  $branch"
  if upstream="$(git::g rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2> /dev/null)" &&
    counts="$(git::g rev-list --left-right --count 'HEAD...@{upstream}' 2> /dev/null)"; then
    read -r ahead behind <<< "$counts"
    header+="  ↑$ahead ↓$behind $upstream"
  fi
  if [[ "${FZX_MODE:-}" == commit ]]; then
    header+="  $(git::g log -1 --format='%h %s' "$GIT_REV" -- 2> /dev/null)"
  elif [[ -n "$GIT_REV" ]]; then
    header+="  ${FZX_MODE:-log} of $GIT_REV"
  fi
  ((GIT_ALL)) && header+="  all refs"
  printf '%s' "$header"
}

# shellcheck disable=SC2034  # FZX_ACTION_ARGS*: read by lib/actions.sh
git::opts() {
  git::args "${FZX_ARGS[@]}" || return
  # module args travel with every callback, before "--" and the selected ids
  local a=""
  ((${#FZX_ARGS[@]})) && printf -v a '%q ' "${FZX_ARGS[@]}"
  a+="--"
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    "--header=$(git::header)"
    --preview "$(fzx::cb preview "$a" '{1}' '{3}')"
    "--preview-window=right,60%,nohidden"
  )
  # the actions (components.tsv) get the module args too
  FZX_ACTION_ARGS="$a {+1}"
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[git.into]}" "transform:$(fzx::cb transform into "$a" '{1}')" \
      "branches, tags: the log; log, reflog, stash: the commit's files; worktrees: status"
    fzx::bind "${FZX_KEYS[git.view]}" "transform:$(fzx::cb transform view)" "status, commit: preview the diff or the blame"
  fi
}

fzx::module_main "$@"
