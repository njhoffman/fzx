#!/usr/bin/env bash
# aws defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/aws/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_COLORS FZX_ICON_MODES

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON=""
FZX_ICON_MODES[logs]=""
FZX_ICON_MODES[ecs]=""
FZX_ICON_MODES[eks]="󱃾"
FZX_ICON_MODES[rds]=""

# the icon's color in the menu
FZX_COLORS[aws_icon]="38;5;208"
FZX_COLORS[aws_icon_logs]="38;5;110"
FZX_COLORS[aws_icon_ecs]="38;5;173"
FZX_COLORS[aws_icon_eks]="38;5;68"
FZX_COLORS[aws_icon_rds]="38;5;75"

# seconds for the CLI to connect and to read an answer, and how many times it tries
FZX_AWS_TIMEOUT="${FZX_AWS_TIMEOUT:-10}"
FZX_AWS_ATTEMPTS="${FZX_AWS_ATTEMPTS:-2}"
# describe-cluster requests at a time, for the EKS list
FZX_AWS_JOBS="${FZX_AWS_JOBS:-8}"
# seconds a preview's request (log events, ECS services, EKS node groups) is kept in the session; 0: not kept
FZX_AWS_PREVIEW_TTL="${FZX_AWS_PREVIEW_TTL:-60}"
# events of the latest stream in a log group's preview
FZX_AWS_LOG_LINES="${FZX_AWS_LOG_LINES:-40}"
# how far back following a log group starts
FZX_AWS_TAIL_SINCE="${FZX_AWS_TAIL_SINCE:-1h}"

# lists come over the network: the session keeps them across mode switches (ctrl-r reads them again)
FZX_PERSIST=session

FZX_COLORS[aws_name]='1;38;5;111'
FZX_COLORS[aws_running]='38;5;114'
FZX_COLORS[aws_pending]='38;5;252'
FZX_COLORS[aws_stopped]='38;5;203'

# an instance's details are short, but log events are long: below until 160 columns
FZX_PREVIEW_LAYOUTS=("0:down,55%,border-top" "160:right,50%")
# wide content: a larger popup than the default
FZX_POPUP_LAYOUTS=("0:center,100%" "140:center,95%,90%" "220:center,90%,85%")

# the menu group this module is listed under (menu mode groups)
FZX_MENU_GROUP=system
