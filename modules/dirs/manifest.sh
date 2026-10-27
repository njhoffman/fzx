#!/usr/bin/env bash
# dirs menu entries

dirs::manifest() {
  fzx::entry dirs "Every directory under ~ (fd)"
  fzx::entry dirs:bookmarks "Named directories"
}

dirs::applicable() {
  case "$1" in
    dirs:bookmarks) ((${#FZX_DIRS_BOOKMARKS[@]})) ;;
    *) command -v fd > /dev/null || command -v fdfind > /dev/null ;;
  esac
}
