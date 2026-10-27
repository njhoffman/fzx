#!/usr/bin/env bash
# keybindings menu entries

keybindings::manifest() {
  fzx::entry keybindings "zsh key bindings"
  fzx::entry keybindings:tmux "tmux key bindings"
  fzx::entry keybindings:fzf "fzf key bindings"
}

keybindings::applicable() {
  case "$1" in
    keybindings) command -v zsh > /dev/null ;;
    keybindings:tmux) command -v tmux > /dev/null && command tmux list-sessions > /dev/null 2>&1 ;;
    *) return 0 ;;
  esac
}

# zsh from the saved dump only: a fresh one would start an interactive zsh
keybindings::summary() {
  local file
  case "$1" in
    keybindings)
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
      keybindings::zsh_dump_path file
      [[ -s "$file" ]] || return 0
      awk -F'\t' '$1 == "bind" { n++; if (!seen[$2]++) m++ } END { printf "%d bindings in %d keymaps\n", n, m }' "$file"
      ;;
    keybindings:tmux)
      # shellcheck source=../tmux/manifest.sh
      source "$(dirname "${BASH_SOURCE[0]}")/../tmux/manifest.sh"
      command tmux list-keys | tmux::summary_keys
      ;;
    keybindings:fzf)
      fzx::require keys
      printf '%s of yours, %s fzf defaults\n' "$(fzx::user_binds 2> /dev/null | awk -F'\t' '$1 != ""' | wc -l)" \
        "$(printf '%s\n' "$FZX_FZF_DEFAULT_BINDS" | wc -l)"
      ;;
  esac
}
