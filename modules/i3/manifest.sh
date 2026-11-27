#!/usr/bin/env bash
# i3 menu entries, where i3 answers on its socket

i3::manifest() {
  fzx::entry i3 "i3 windows"
  fzx::entry i3:workspaces "i3 workspaces"
  fzx::entry i3:scratchpad "i3 scratchpad windows"
}

i3::applicable() {
  command -v i3-msg > /dev/null && command -v jq > /dev/null && command i3-msg -t get_version > /dev/null 2>&1
}

# i3::summary <target>: how many windows, workspaces or scratchpad windows
i3::summary() {
  # shellcheck source=./source.sh
  source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :
  case "$1" in
    i3:workspaces) i3::workspaces | awk -F'\037' "$FZX_AWK_PLURAL"'$1 != "__i3_scratch" { n++ } END { print plural(n, "workspace") }' ;;
    i3:scratchpad) i3::tree_windows | awk -F'\037' "$FZX_AWK_PLURAL"'$2 == "__i3_scratch" { n++ } END { print plural(n, "window") }' ;;
    *) i3::tree_windows | awk -F'\037' "$FZX_AWK_PLURAL"'$2 != "__i3_scratch" { n++ } END { print plural(n, "window") }' ;;
  esac
}

# the summaries are cached once for every directory: they describe the desktop, not the directory
i3::summary_global() { :; }
