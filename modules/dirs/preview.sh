#!/usr/bin/env bash
# dirs preview: the directory's git branch (when it is a work tree) and its contents

# dirs::preview <path>
dirs::preview() {
  local dir="${1:-}" branch
  if [[ ! -d "$dir" ]]; then
    printf 'no such directory: %s\n' "$dir"
    return 1
  fi
  if branch="$(command git -C "$dir" symbolic-ref --quiet --short HEAD 2> /dev/null)"; then
    printf '\e[1mgit\e[0m %s  %s changes\n\n' "$branch" "$(command git -C "$dir" status --porcelain 2> /dev/null | wc -l)"
  fi
  if command -v eza > /dev/null; then
    command eza --color=always --icons --group-directories-first -a --tree --level=1 -- "$dir"
  else
    command ls -la --color=always -- "$dir"
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && dirs::preview "$@"
