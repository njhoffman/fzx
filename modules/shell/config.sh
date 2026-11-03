#!/usr/bin/env bash
# shell defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/shell/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the menu's icons for modes that open different lists
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[aliases]="󰌹"
FZX_ICON_MODES[functions]="󰊕"
FZX_ICON_MODES[params]="󰫧"
FZX_ICON_MODES[completions]="󰌒"
# the icons' colors in the menu
FZX_COLORS[shell_icon]="38;5;114"
FZX_COLORS[shell_icon_aliases]="38;5;180"
FZX_COLORS[shell_icon_functions]="38;5;117"
FZX_COLORS[shell_icon_params]="38;5;75"
FZX_COLORS[shell_icon_completions]="38;5;150"

# the shell changes: read it on every open
FZX_PERSIST=none

# the zsh dump (shell/fzx.zsh writes it at the first prompt; its shell widget before opening the module) is
# used while younger than this many seconds; older or missing, an interactive `zsh -ic` dumps the shell
FZX_SHELL_DUMP_TTL="${FZX_SHELL_DUMP_TTL:-86400}"
# parameters whose upper-cased names match this extended regular expression have their values masked (the
# reveal toggle shows exported ones). The zsh side reads FZX_SHELL_SECRETS from its own environment, with
# the same default: set it there too (zshrc) when you change it
FZX_SHELL_SECRETS="${FZX_SHELL_SECRETS:-TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|APIKEY|_KEY\$|PASS\$}"

FZX_COLORS[shell_name]='1;38;5;117'
FZX_COLORS[shell_kind]='38;5;180'
FZX_COLORS[shell_value]='38;5;250'
FZX_COLORS[shell_export]='1;38;5;75'
FZX_COLORS[shell_masked]='38;5;203'

# the completions mode lists zsh-complete's bindings (~/.shell's completion manager): the command (empty:
# zsh-complete on PATH, else $SHELL_ROOT or ~/.shell's scripts/zsh-complete). Listing them takes it 15s or
# more, so its list is kept in $FZX_CACHE_DIR/shell/completions.tsv this many seconds; alt-R asks again
FZX_SHELL_ZSH_COMPLETE="${FZX_SHELL_ZSH_COMPLETE:-}"
FZX_SHELL_COMPLETIONS_TTL="${FZX_SHELL_COMPLETIONS_TTL:-86400}"
# the provider column: the curated ones (static, generated, local), the system's, the rest (plugins, fetched
# sources, carapace, bash)
FZX_COLORS[shell_provider_own]='38;5;114'
FZX_COLORS[shell_provider_system]='38;5;244'
FZX_COLORS[shell_provider]='38;5;180'

# names are short and tldr pages want about 70 columns: the preview moves right from 110
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "110:right,60%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=shell
