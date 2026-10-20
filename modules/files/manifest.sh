#!/usr/bin/env bash
# files menu entries

files::manifest() {
  fzx::entry files "Files under this directory"
  fzx::entry files:dirs "Directories under this directory"
  fzx::entry files:grep "Search file contents as you type"
}

files::applicable() {
  case "$1" in
    files:grep) command -v rg > /dev/null ;;
    *) command -v fd > /dev/null || command -v fdfind > /dev/null ;;
  esac
}

files::summary() {
  local fd=fd n
  command -v fd > /dev/null || fd=fdfind
  case "$1" in
    files) n="$("$fd" --type f --hidden --exclude .git . | wc -l)" && printf '%s files\n' "${n// /}" ;;
    files:dirs) n="$("$fd" --type d --hidden --exclude .git . | wc -l)" && printf '%s directories\n' "${n// /}" ;;
    *) return 1 ;;
  esac
}
