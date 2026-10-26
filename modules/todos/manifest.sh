#!/usr/bin/env bash
# todos menu entries

todos::manifest() {
  fzx::entry todos "TODO items of this repository"
  fzx::entry todos:all "TODO items of every repository"
}

todos::applicable() {
  case "$1" in
    todos) local top; top="$(git rev-parse --show-toplevel 2> /dev/null)" || top="$PWD"; [[ -f "$top/TODO.md" ]] ;;
    *) return 0 ;;
  esac
}

todos::summary() {
  local top
  case "$1" in
    todos)
      top="$(git rev-parse --show-toplevel 2> /dev/null)" || top="$PWD"
      printf '%s open\n' "$(grep -c '^- \[ \] ' "$top/TODO.md" 2> /dev/null)"
      ;;
  esac
}
