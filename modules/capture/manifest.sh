#!/usr/bin/env bash
# capture menu entries

capture::manifest() {
  fzx::entry capture "Lines in this pane (visible first)"
  fzx::entry capture:urls "URLs in this pane"
  fzx::entry capture:paths "Paths in this pane"
  fzx::entry capture:words "Words and identifiers in this pane"
  fzx::entry capture:hashes "Hexadecimal hashes in this pane"
  fzx::entry capture:ips "IP addresses (IPv4, IPv6) in this pane"
}

capture::applicable() { [[ -n "${TMUX:-}" ]] && command -v tmux > /dev/null; }

# capture::summary_key: the pane the entries read (the active one, under the menu's popup too) and how far
# its history and cursor have moved, so another pane, or new output, has its own summary
capture::summary_key() {
  command tmux display-message -p '#{pane_id}:#{history_size}:#{cursor_y}' 2> /dev/null
}

# capture::summary <target>: how many rows the entry would list from that pane
capture::summary() {
  local mode=lines n
  [[ "$1" == *:* ]] && mode="${1#*:}"
  n="$(env -u FZX_SESSION -u FZX_SESSION_DIR FZX_MODE="$mode" "$(dirname "${BASH_SOURCE[0]}")/source.sh" 2> /dev/null | wc -l)" || return 1
  case "$mode" in
    lines) printf '%s\n' "$(fzx::plural "$n" line)" ;;
    urls) printf '%s\n' "$(fzx::plural "$n" URL)" ;;
    paths) printf '%s\n' "$(fzx::plural "$n" path)" ;;
    words) printf '%s\n' "$(fzx::plural "$n" word)" ;;
    hashes) printf '%s\n' "$(fzx::plural "$n" hash hashes)" ;;
    ips) printf '%s\n' "$(fzx::plural "$n" address addresses)" ;;
    *) printf '%s\n' "$n" ;;
  esac
}
