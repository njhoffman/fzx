#!/usr/bin/env bash
# dirs menu entries

dirs::manifest() {
  fzx::entry dirs "Frecent directories (zoxide)"
  fzx::entry dirs:recent "Recently visited directories (fasd)"
}

dirs::applicable() {
  case "$1" in
    dirs:recent) command -v fasd > /dev/null ;;
    *) command -v zoxide > /dev/null ;;
  esac
}

dirs::summary() {
  case "$1" in
    dirs) printf '%s known directories\n' "$(command zoxide query --list 2> /dev/null | wc -l)" ;;
    *) return 0 ;;
  esac
}
