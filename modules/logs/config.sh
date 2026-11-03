#!/usr/bin/env bash
# logs defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/logs/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""

# the icon's color in the menu
FZX_COLORS[logs_icon]="38;5;152"


# named log files; missing or unreadable ones are skipped
declare -gA FZX_LOGS_FILES=(
  [auth]=/var/log/auth.log
  [dmesg]=/var/log/dmesg
  [kern]=/var/log/kern.log
  [syslog]=/var/log/syslog
  [mpd]="$HOME/.mpd/mpd.log"
)

# globs whose matches are listed by file name
FZX_LOGS_GLOBS=(
  "$HOME/.local/state/nvim/*.log"
  "$HOME/.local/share/nvim/*.log"
  "$HOME/.cache/nvim/*.log"
  "/tmp/*.log"
)

# a dot before each file, in its age's color (green under a minute, darker under an hour and a day, grey
# older); "" leaves it out
FZX_LOGS_AGE_DOT="●"

# lines shown in the preview and before following
FZX_LOGS_LINES=200

# the preview follows the log while the row has focus (0: a snapshot)
FZX_LOGS_PREVIEW_FOLLOW=1
# how often (seconds) a followed preview asks fzf's socket whether its row still has focus, so a follow
# left behind (the pane or popup closed under fzf, become()) stops instead of running on
FZX_LOGS_FOLLOW_CHECK="${FZX_LOGS_FOLLOW_CHECK:-2}"

# files and container logs pass through this, line by line; () shows them plain (files: bat's log
# highlighting). ccze -A, or grcat with one of grc's configs: (grcat conf.log)
FZX_LOGS_COLORIZER=(ccze -A)

# lines of `systemctl status` pinned above a unit's journal
FZX_LOGS_STATUS_LINES=8

# log lines are long in the list and the preview alike: the preview stays below at every width
FZX_PREVIEW_LAYOUTS=("0:down,60%,border-top")
# wide content: a larger popup than the default
FZX_POPUP_LAYOUTS=("0:center,100%" "140:center,95%,90%" "220:center,90%,85%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system

# --freeze-left (config/defaults.sh): files: the age, the marks and the name stay
declare -gA FZX_FREEZE_COLS
FZX_FREEZE_COLS[files]=38
