#!/usr/bin/env bash
# keybindings defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/keybindings/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰌌"

# bindings change with the shell's config: read them on every open
FZX_PERSIST=none

# the zsh dump (shell/fzx.zsh refreshes it whenever an fzx widget runs) is used while younger than this
# many seconds; older or missing, an interactive `zsh -ic` dumps them (about a second)
FZX_KEYBINDINGS_ZSH_TTL="${FZX_KEYBINDINGS_ZSH_TTL:-86400}"
# widgets bound to these are not listed
FZX_KEYBINDINGS_ZSH_SKIP=(self-insert self-insert-unmeta undefined-key digit-argument)

FZX_COLORS[keys_map]='38;5;250'
FZX_COLORS[keys_key]='1;38;5;255'
FZX_COLORS[keys_widget]='38;5;117'
FZX_COLORS[keys_user]='38;5;147'
