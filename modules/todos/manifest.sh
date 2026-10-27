#!/usr/bin/env bash
# todos menu entries

todos::manifest() {
  fzx::entry todos "TODO items of this repository"
  fzx::entry todos:all "TODO items of every repository"
}

todos::applicable() {
  case "$1" in
    todos)
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
      todos::here > /dev/null
      ;;
    *) return 0 ;;
  esac
}

# open items, and how many of them are urgent (p1) or overdue
todos::summary() {
  local mode=here files file
  [[ "$1" == todos:all ]] && mode=all
  # shellcheck source=./source.sh
  source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
  mapfile -t files < <(FZX_MODE="$mode" todos::files)
  ((${#files[@]})) || return 0
  for file in "${files[@]}"; do FZX_TOGGLES="" todos::parse "$file"; done |
    awk -F'\t' -v files="${#files[@]}" -v mode="$mode" '{ n++; if ($7 == 1) u++; if ($6 == 1) o++ }
      END { printf "%d open%s, %d urgent, %d overdue\n", n, mode == "all" ? " in " files " files" : "", u, o }'
}
