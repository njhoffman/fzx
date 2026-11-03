#!/usr/bin/env bash
# cron defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/cron/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰃰"
declare -gA FZX_ICON_MODES
FZX_ICON_MODES[scripts]="󰯂"
# the icon's color in the menu
FZX_COLORS[cron_icon]="38;5;180"
FZX_COLORS[cron_icon_scripts]="38;5;150"

# the schedule column, the user column and an entry cron rejects
FZX_COLORS[cron_schedule]="38;5;110"
FZX_COLORS[cron_user]="38;5;180"
FZX_COLORS[cron_invalid]="38;5;203"

# where the system's entries are: files and directories of crontabs with a user field, anacron's table and
# its timestamps, and the run-parts directories
FZX_CRON_SYSTEM_FILES="${FZX_CRON_SYSTEM_FILES:-/etc/crontab /etc/cron.d}"
FZX_CRON_ANACRONTAB="${FZX_CRON_ANACRONTAB:-/etc/anacrontab}"
FZX_CRON_ANACRON_SPOOL="${FZX_CRON_ANACRON_SPOOL:-/var/spool/anacron}"

# every user's crontab, read with a cached sudo (all and system modes; yours is read through crontab -l):
# empty is Debian's /var/spool/cron/crontabs where it exists, else cronie's /var/spool/cron
FZX_CRON_SPOOL_DIR="${FZX_CRON_SPOOL_DIR:-}"

# whether cron takes CRON_TZ= lines (next runs then follow the zone): 1, 0, or empty for "when cronie's
# crond is installed" (Debian's cron ignores CRON_TZ)
FZX_CRON_HONORS_TZ="${FZX_CRON_HONORS_TZ:-}"
FZX_CRON_SCRIPT_DIRS="${FZX_CRON_SCRIPT_DIRS:-/etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.yearly}"
# how many next runs the preview lists
FZX_CRON_PREVIEW_RUNS="${FZX_CRON_PREVIEW_RUNS:-5}"

# "in 5m" goes stale: read again on every load (one systemd-analyze call)
FZX_PERSIST=none

# command lines are what is read: the preview below until the rows have room
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "220:right,35%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
