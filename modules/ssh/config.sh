#!/usr/bin/env bash
# ssh defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/ssh/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰣀"
# the icon's color in the menu
FZX_COLORS[ssh_icon]="38;5;110"

# host names, rows never used and labels, a key known_hosts has
FZX_COLORS[ssh_host]="38;5;117"
FZX_COLORS[ssh_dim]="38;5;244"
FZX_COLORS[ssh_known]="38;5;114"

# where the hosts come from: ssh's config (its Include files too), known_hosts, zsh-histdb's database
FZX_SSH_CONFIG="${FZX_SSH_CONFIG:-$HOME/.ssh/config}"
FZX_SSH_KNOWN_HOSTS="${FZX_SSH_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
FZX_SSH_HISTDB="${FZX_SSH_HISTDB:-${HISTDB_FILE:-$HOME/.histdb/zsh-history.db}}"
# how many of the commands that named the host the preview lists
FZX_SSH_PREVIEW_COMMANDS="${FZX_SSH_PREVIEW_COMMANDS:-8}"

# short details, rows read whole: below until 150, then on the right
FZX_PREVIEW_LAYOUTS=("0:down,45%,border-top" "150:right,45%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system

# send and fetch copy with rsync (-a, with its progress) when this is installed, else scp -r; empty: scp
FZX_SSH_RSYNC="${FZX_SSH_RSYNC-rsync}"
