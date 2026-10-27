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
