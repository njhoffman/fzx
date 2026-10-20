#!/usr/bin/env bash
# git: status, log, branches and stash of a repository. `fzx -m git[:log|:branches|:stash] [--all]
# [--rev REV] [DIR]`. Enter prints paths, hashes, ref names or stash names.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

git::modes() {
  FZX_MODES=(status log branches stash)
}

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
  [[ -n "$GIT_REV" ]] && header+="  log of $GIT_REV"
  ((GIT_ALL)) && header+="  all refs"
  printf '%s' "$header"
}

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
    --no-sort
    "--header=$(git::header)"
    --preview "$(fzx::cb preview "$a" {1})"
    --preview-window=right,60%,nohidden
  )
  fzx::bind "${FZX_KEYS[git.stage]}" "execute($(fzx::cb action stage "$a" {+1}))+reload($(fzx::cb source))" \
    "status: stage the selected files"
  fzx::bind "${FZX_KEYS[git.unstage]}" "execute($(fzx::cb action unstage "$a" {+1}))+reload($(fzx::cb source))" \
    "status: unstage the selected files"
  fzx::bind "${FZX_KEYS[git.edit]}" "execute($(fzx::cb action edit "$a" {+1}))+reload($(fzx::cb source))" \
    "status: open the selected files in \$EDITOR"
  if fzx::in_session; then
    # switching changes the header (current branch), so restart the interface afterwards
    fzx::bind "${FZX_KEYS[git.switch]}" "execute($(fzx::cb action switch "$a" {1}))+transform($(fzx::cb nav resume))" \
      "branches: switch to the branch (remote: create a tracking branch)"
    fzx::bind "${FZX_KEYS[git.into]}" "transform:$(fzx::cb transform into "$a" {1})" "branches: open the branch's log"
  fi
}

fzx::module_main "$@"
