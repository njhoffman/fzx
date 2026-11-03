#!/usr/bin/env bash
# browser defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/browser/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰖟"
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[bookmarks]="󰃀"
# the icon's color in the menu
FZX_COLORS[browser_icon]="38;5;75"
FZX_COLORS[browser_icon_bookmarks]="38;5;180"

# the profile column: Chromium-family browsers and Firefox
FZX_COLORS[browser_chrome]="38;5;75"
FZX_COLORS[browser_firefox]="38;5;209"

# Chromium-family browsers: [name]=config directory (its profiles are the directories with a History or
# Bookmarks file) and [name]=the command that opens a URL in one of them (with --profile-directory=DIR).
# Directories that do not exist are skipped; the chrome toggle covers them all
declare -gA FZX_BROWSER_CHROMIUM_DIRS FZX_BROWSER_CHROMIUM_CMDS
: "${FZX_BROWSER_CHROMIUM_DIRS[chrome]:=$HOME/.config/google-chrome}"
: "${FZX_BROWSER_CHROMIUM_DIRS[chromium]:=$HOME/.config/chromium}"
: "${FZX_BROWSER_CHROMIUM_DIRS[brave]:=$HOME/.config/BraveSoftware/Brave-Browser}"
: "${FZX_BROWSER_CHROMIUM_DIRS[vivaldi]:=$HOME/.config/vivaldi}"
: "${FZX_BROWSER_CHROMIUM_CMDS[chrome]:=google-chrome}"
: "${FZX_BROWSER_CHROMIUM_CMDS[chromium]:=chromium}"
: "${FZX_BROWSER_CHROMIUM_CMDS[brave]:=brave-browser}"
: "${FZX_BROWSER_CHROMIUM_CMDS[vivaldi]:=vivaldi}"

# Firefox: the directory with profiles.ini, and the command that opens a URL (with -P PROFILE). Empty picks
# one per profile: Developer Edition's (firefox-devedition, /usr/lib/firefox-devedition/firefox) for the
# profiles it names dev-edition-*, else firefox
FZX_BROWSER_FIREFOX_DIR="${FZX_BROWSER_FIREFOX_DIR:-$HOME/.mozilla/firefox}"
FZX_BROWSER_FIREFOX_CMD="${FZX_BROWSER_FIREFOX_CMD:-}"

# history entries read per profile, the most recent first
FZX_BROWSER_HISTORY_MAX="${FZX_BROWSER_HISTORY_MAX:-5000}"

# the databases are copied (the browsers lock them) and read again after five minutes
FZX_PERSIST=cache:5m

# long rows (title and URL) and short details: below until 160
FZX_PREVIEW_LAYOUTS=("0:down,30%,border-top" "160:right,35%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=other
