#!/usr/bin/env bash
# man menu entries

man::manifest() {
  fzx::entry man "Man pages of commands"
  fzx::entry man:all "Every man page"
  fzx::entry man:tldr "tldr pages"
}

man::applicable() {
  case "$1" in
    man:tldr) command -v tldr > /dev/null ;;
    *) command -v man > /dev/null ;;
  esac
}

# the lists' own lengths (man -k takes a fraction of a second)
man::summary() {
  local n
  # shellcheck source=./source.sh
  source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
  case "$1" in
    man) n="$(FZX_MODE=commands man::source | wc -l)" && printf '%s commands\n' "${n// /}" ;;
    man:all) n="$(FZX_MODE=all man::source | wc -l)" && printf '%s pages\n' "${n// /}" ;;
    man:tldr)
      # the page names alone: reading every page for its description takes seconds
      local dir p names=()
      man::tldr_dir dir
      [[ -n "$dir" && -d "$dir/pages.en" ]] || return 0
      for p in common "${FZX_MAN_TLDR_PLATFORMS[@]}"; do
        [[ -d "$dir/pages.en/$p" ]] && names+=("$dir/pages.en/$p"/*.md)
      done
      printf '%s\n' "${names[@]##*/}" | sort -u | awk 'END { printf "%d pages\n", NR }'
      ;;
  esac
}
