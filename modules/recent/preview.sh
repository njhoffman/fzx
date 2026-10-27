#!/usr/bin/env bash
# recent preview: a file or directory as the files module shows it; a directory that is a git work tree
# gets its branch and change count first
# shellcheck source=../files/preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/../files/preview.sh"

# recent::preview <path>
recent::preview() {
  local branch
  if [[ -d "${1:-}" ]] && branch="$(command git -C "$1" symbolic-ref --quiet --short HEAD 2> /dev/null)"; then
    printf '\e[1mgit\e[0m %s  %s changes\n' "$branch" "$(command git -C "$1" status --porcelain 2> /dev/null | wc -l)"
  fi
  files::preview "$@"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && recent::preview "$@"
