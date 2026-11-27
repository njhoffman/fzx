#!/usr/bin/env bash
# snippets menu entries, the history where something was pasted

snippets::manifest() {
  fzx::entry snippets "Snippets you saved"
  fzx::entry snippets:history "Paste history (capture, tmux buffers)"
}

snippets::applicable() {
  local dir
  fzx::require snippets
  fzx::snippets_dir dir
  case "$1" in
    snippets:history) [[ -n "$(command ls -A -- "$dir/history" 2> /dev/null)" ]] ;;
    *) return 0 ;;
  esac
}

# snippets::summary <target>: how many snippets, or pastes kept
snippets::summary() {
  local dir n
  fzx::require snippets
  fzx::snippets_dir dir
  case "$1" in
    snippets:history)
      n="$(command ls -1 -- "$dir/history" 2> /dev/null | wc -l)"
      printf '%s\n' "$(fzx::plural "$n" paste)"
      ;;
    *)
      n="$(command ls -1 -- "$dir/saved" 2> /dev/null | wc -l)"
      printf '%s\n' "$(fzx::plural "$n" snippet)"
      ;;
  esac
}

# the summaries are cached once for every directory: they describe the machine, not the directory
snippets::summary_global() { :; }
