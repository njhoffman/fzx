#!/usr/bin/env bash
# packages defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/packages/config.sh
# apt and snap actions run through sudo when fzx is not root (in the foreground, so it can prompt).

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS FZX_ICON_MODES

# prompt icon (Nerd Font: nf-oct-package); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=$''
FZX_ICON_MODES[apt]=$''
FZX_ICON_MODES[available]=$''
FZX_ICON_MODES[upgradable]=$'\U000f0060'
FZX_ICON_MODES[snap]=$''
FZX_ICON_MODES[flatpak]=$''
FZX_ICON_MODES[pipx]=$''
FZX_ICON_MODES[cargo]=$''
FZX_ICON_MODES[pnpm]=$''
FZX_ICON_MODES[gem]=$''

# the icons' colors in the menu
FZX_COLORS[packages_icon]="38;5;137"
FZX_COLORS[packages_icon_apt]="38;5;161"
FZX_COLORS[packages_icon_available]="38;5;161"
FZX_COLORS[packages_icon_upgradable]="38;5;179"
FZX_COLORS[packages_icon_snap]="38;5;208"
FZX_COLORS[packages_icon_flatpak]="38;5;74"
FZX_COLORS[packages_icon_pipx]="38;5;67"
FZX_COLORS[packages_icon_cargo]="38;5;173"
FZX_COLORS[packages_icon_pnpm]="38;5;178"
FZX_COLORS[packages_icon_gem]="38;5;160"

# rows and previews
FZX_COLORS[packages_name]='38;5;252'
FZX_COLORS[packages_title]='1;38;5;255'
FZX_COLORS[packages_version]='38;5;110'
FZX_COLORS[packages_dim]='38;5;244'
FZX_COLORS[packages_key]='38;5;244'
FZX_COLORS[packages_installed]='38;5;114'
FZX_COLORS[packages_missing]='38;5;240'
FZX_COLORS[packages_upgrade]='38;5;179'

# gem homes listed in the gem mode, "scope:glob" (scope user or system); the gems apt installs under
# /usr/lib/ruby and rubygems-integration belong to apt and are left out
FZX_PACKAGES_GEM_DIRS=("user:$HOME/.local/share/gem/ruby/*" "system:/var/lib/gems/*" "system:/usr/local/lib/ruby/gems/*")

# rows are long (name, version, size, summary) and so are the descriptions: below until 190 columns
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "190:right,50%")
FZX_POPUP_LAYOUTS=("0:center,100%" "140:center,95%,90%" "220:center,90%,85%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
