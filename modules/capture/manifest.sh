#!/usr/bin/env bash
# capture menu entries

capture::manifest() {
  fzx::entry capture "Lines in this pane (visible first)"
  fzx::entry capture:urls "URLs in this pane"
  fzx::entry capture:paths "Paths in this pane"
  fzx::entry capture:words "Words and identifiers in this pane"
  fzx::entry capture:hashes "Hexadecimal hashes in this pane"
  fzx::entry capture:ips "IPv4 addresses in this pane"
}

capture::applicable() { [[ -n "${TMUX:-}" ]] && command -v tmux > /dev/null; }
