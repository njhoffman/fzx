#!/usr/bin/env bash
# workspaces menu entries, inside tmux with the workspace command (FZX_WORKSPACE_CMD)

workspaces::manifest() {
  fzx::entry workspaces "tmux workspaces: sessions and recent dirs"
  fzx::entry workspaces:recent "tmux workspaces: recent directories"
}

workspaces::applicable() {
  [[ -n "${TMUX:-}" && -x "${FZX_WORKSPACE_CMD:-$HOME/.config/tmux/scripts/workspace}" ]]
}

# workspaces::summary <target>: how many are open and how many recent directories have no session
workspaces::summary() {
  "${FZX_WORKSPACE_CMD:-$HOME/.config/tmux/scripts/workspace}" list 2> /dev/null |
    command awk -F'\t' '$5 == "open" { o++ } $5 == "closed" && $1 ~ /^\// { c++ }
      END { printf "%d open, %d recent\n", o, c }'
}

# the summaries are cached once for every directory: they describe the machine, not the directory
workspaces::summary_global() { :; }
