#!/usr/bin/env bash
# systemd defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/systemd/config.sh
# Actions on system units run through sudo when fzx is not root (in the foreground, so it can prompt).

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

