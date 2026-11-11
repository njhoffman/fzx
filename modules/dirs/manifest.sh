#!/usr/bin/env bash
# dirs menu entries

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :

dirs::manifest() {
  fzx::entry dirs "Every directory under ~ (fd)"
  fzx::entry dirs:bookmarks "Named directories"
}

dirs::applicable() {
  case "$1" in
    dirs:bookmarks) [[ -n "$(dirs::bookmarks)" ]] ;;
    *) command -v fd > /dev/null || command -v fdfind > /dev/null ;;
  esac
}

# no summary for the fd walk of ~: it can take longer than the summary timeout
dirs::summary() {
  [[ "$1" == dirs:bookmarks ]] || return 0
  printf '%s\n' "$(fzx::plural "$(dirs::bookmarks | wc -l)" bookmark)"
}
