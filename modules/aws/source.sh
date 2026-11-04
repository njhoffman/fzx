#!/usr/bin/env bash
# aws source: "id<TAB>display<TAB>name<TAB>details" per mode, the name being what ctrl-y copies and the details
# (0x1f-separated) what the preview draws, so moving the cursor asks AWS nothing for an instance.
#   ec2   (toggle running; sort state or name): state name type public-ip private-ip zone launched image vpc
#         subnet key groups tags
#   logs  (sort name or size): bytes retention created class
#   ecs, eks, rds: services.sh; volumes, vpcs, subnets, sgs, db-subnets, cache, cache-subnets, profiles: resources.sh
# A list that cannot be read, or has nothing in it, is a row with an empty id and the whole message as its
# name. A failed read returns 1, so it is not cached. The CLI's "None" marks a value AWS did not send.

# shellcheck source=./services.sh
source "$(dirname "${BASH_SOURCE[0]}")/services.sh"
# shellcheck source=./resources.sh
source "$(dirname "${BASH_SOURCE[0]}")/resources.sh"

# aws::_selected: AWS_SEL_KIND (profile, vault; empty: what the CLI resolves unaided) and AWS_SEL_NAME, from
# what the profiles mode saved in $FZX_STATE_DIR/aws/profile; read once per process
aws::_selected() {
  [[ -z "${AWS_SEL_READ:-}" ]] || return 0
  AWS_SEL_READ=1 AWS_SEL_KIND="" AWS_SEL_NAME=""
  local file="${FZX_STATE_DIR:-}/aws/profile"
  [[ -r "$file" ]] && read -r AWS_SEL_KIND AWS_SEL_NAME < "$file"
  return 0
}

# aws::cli <args...>: the AWS CLI with no pager, bounded waits (FZX_AWS_TIMEOUT, FZX_AWS_ATTEMPTS) and the
# profile chosen in the profiles mode. --profile wins over AWS_ACCESS_KEY_ID in the environment, which
# AWS_PROFILE does not; aws-vault exec sets those variables itself
aws::cli() {
  local run=(command aws) flags=(--cli-connect-timeout "${FZX_AWS_TIMEOUT:-10}" --cli-read-timeout "${FZX_AWS_TIMEOUT:-10}")
  aws::_selected
  case "$AWS_SEL_KIND" in
    profile) flags+=(--profile "$AWS_SEL_NAME") ;;
    vault) run=(env -u AWS_VAULT aws-vault exec "$AWS_SEL_NAME" -- aws) ;;
  esac
  AWS_PAGER="" AWS_MAX_ATTEMPTS="${FZX_AWS_ATTEMPTS:-2}" "${run[@]}" "${flags[@]}" "$@"
}

# aws::region: the Region the CLI uses (empty: none configured)
aws::region() {
  local r="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  aws::_selected
  [[ -n "$r" || -z "$AWS_SEL_NAME" ]] || r="$(aws::_config_region "$AWS_SEL_NAME")"
  [[ -n "$r" ]] || r="$(command aws configure get region 2> /dev/null)"
  printf '%s' "$r"
}

# aws::clean: stdin without what would move the cursor or clear the screen: console output and log events are
# text from elsewhere (a boot's firmware clears the screen). Colors stay, as do tabs and newlines; carriage returns
# and the other control characters go
aws::clean() {
  LC_ALL=C sed -E $'s/\x1b\\[[0-9;:=?<>]*[A-Za-ln-z]//g; s/\x1b\\][^\x07\x1b]*(\x07|\x1b\\\\)//g; s/\x1b[^[]//g' | LC_ALL=C tr -d '\000-\010\013-\032\034-\037\177'
}

# aws::color <name> <default SGR>: an escape sequence from FZX_COLORS
aws::color() { printf '\e[%sm' "${FZX_COLORS[$1]:-$2}"; }

# aws::note <text>: a row for a list with nothing to show
aws::note() { printf '\t%s%s\e[0m\t%s\t\n' "$(aws::color dim '38;5;244')" "$1" "$1"; }

# aws::failed <what> <stderr file>: the row and the log line for a list that cannot be read, naming the
# way out when the credentials are what failed
aws::failed() {
  local what="$1" msg hint=""
  msg="$(grep -m1 '[^[:space:]]' "$2")"
  [[ -n "$msg" ]] || msg="the aws command failed"
  printf 'aws: cannot list %s: %s\n' "$what" "$msg" >&2
  case "$msg" in
    *ExpiredToken* | *InvalidClientTokenId* | *AuthFailure* | *'Unable to locate credentials'* | *'aws login'* | *UnrecognizedClient*)
      hint=" (aws login signs in)"
      ;;
    *'specify a region'*) hint=" (aws configure set region REGION)" ;;
  esac
  printf '\t%scannot list %s:\e[0m %s%s\t%s%s\t\n' "$(aws::color aws_stopped '38;5;203')" "$what" "$msg" "$hint" "$msg" "$hint"
}

aws::source() {
  command -v aws > /dev/null || { printf 'aws: the aws command is not installed\n' >&2; return 2; }
  # what previews kept from before this read (ctrl-r) is older than the list
  [[ -z "${FZX_SESSION_DIR:-}" ]] || rm -rf -- "$FZX_SESSION_DIR/aws_preview"
  case "${FZX_MODE:-ec2}" in
    ec2) aws::_source_ec2 ;;
    logs) aws::_source_logs ;;
    ecs) aws::_source_ecs ;;
    eks) aws::_source_eks ;;
    rds) aws::_source_rds ;;
    profiles) aws::_source_profiles ;;
    volumes | vpcs | subnets | sgs | db-subnets | cache | cache-subnets) aws::_source_table "$FZX_MODE" ;;
    *)
      printf 'aws: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

# aws::_read <what> <var> <args...>: the CLI's output into <var>; on failure the error row, and false
aws::_read() {
  local _what="$1" _var="$2" _err _out _rc=0
  shift 2
  _err="$(mktemp)" || return 2
  _out="$(aws::cli "$@" 2> "$_err")" || _rc=$?
  ((_rc == 0)) || aws::failed "$_what" "$_err"
  rm -f -- "$_err"
  printf -v "$_var" '%s' "$_out"
  return "$_rc"
}

aws::_source_ec2() {
  local out dim rst=$'\e[0m' name run pend stop hl="${FZX_COLORS[sorted]:-4}" sort="${FZX_SORT:-state}" filter=() none="no EC2 instances"
  dim="$(aws::color dim '38;5;244')" name="$(aws::color aws_name '1;38;5;111')"
  run="$(aws::color aws_running '38;5;114')" pend="$(aws::color aws_pending '38;5;252')"
  stop="$(aws::color aws_stopped '38;5;203')"
  if [[ " ${FZX_TOGGLES:-} " == *" running "* ]]; then
    filter=(--filters 'Name=instance-state-name,Values=running')
    none="no running EC2 instances"
  fi
  fzx::require icons header
  fzx::icon_vars running paused stopped
  fzx::header_print 1 "$([[ "$sort" == name ]] && echo NAME || echo STATE)" \
    "" 1 0 NAME 28 0 ID 19 0 TYPE 13 0 STATE 13 0 IP 0 0
  # shellcheck disable=SC2016  # the backticks are JMESPath literals
  aws::_read "EC2 instances" out ec2 describe-instances "${filter[@]}" --output text --query \
    'Reservations[].Instances[].[InstanceId, State.Name, Tags[?Key==`Name`].Value | [0], InstanceType, PublicIpAddress, PrivateIpAddress, Placement.AvailabilityZone, LaunchTime, ImageId, VpcId, SubnetId, KeyName, join(`", "`, (SecurityGroups || `[]`)[].GroupName), join(`", "`, (Tags || `[]`)[].join(`"="`, [Key, Value]))]' ||
    return 1
  if [[ -z "$out" ]]; then
    aws::note "$none in $(aws::region)"
    return 0
  fi
  printf '%s\n' "$out" |
    awk -F'\t' "${FZX_ICON_VARS[@]}" -v dim="$dim" -v rst="$rst" -v name="$name" -v run="$run" -v pend="$pend" -v stop="$stop" \
      -v sort="$sort" -v hl=$'\e['"${hl}m" '
      function cell(color, text, w, on) { return on ? color hl text rst sprintf("%" (w - length(text) > 0 ? w - length(text) : 0) "s", "") : color sprintf("%-" w "s", text) rst }
      { label = ($3 == "None" || $3 == "") ? "-" : $3
        shown = length(label) > 28 ? substr(label, 1, 27) "…" : label
        if ($2 == "running") { c = run; i = icon_running; rank = 0 }
        else if ($2 == "pending" || $2 == "stopping" || $2 == "shutting-down") { c = pend; i = icon_paused; rank = 1 }
        else if ($2 == "stopped") { c = stop; i = icon_stopped; rank = 2 }
        else { c = dim; i = icon_stopped; rank = 3 }
        if (i == "") i = "●"
        ip = ($5 != "None" && $5 != "") ? $5 : ($6 != "None" && $6 != "") ? $6 : "-"
        details = $2
        for (f = 4; f <= 14; f++) details = details "\037" $f
        key = sort == "name" ? tolower(label) : rank
        printf "%s\t%s\t%s%s%s %s %s%-19s%s %-13s %s %s\t%s\t%s\n", key, $1, c, i, rst, cell(name, shown, 28, sort == "name"), dim, $1, rst, $4,
          cell(c, $2, 13, sort == "state"), ip, (label == "-" ? $1 : label), details }' |
    LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
}

aws::_source_logs() {
  local out dim rst=$'\e[0m' name hl="${FZX_COLORS[sorted]:-4}" sort="${FZX_SORT:-name}"
  dim="$(aws::color dim '38;5;244')" name="$(aws::color aws_name '1;38;5;111')"
  fzx::require header
  fzx::header_print 1 "$([[ "$sort" == size ]] && echo SIZE || echo NAME)" NAME 48 0 SIZE 9 1 RETENTION 0 0
  aws::_read "log groups" out logs describe-log-groups --output text --query \
    'logGroups[].[logGroupName, storedBytes, retentionInDays, creationTime, logGroupClass]' || return 1
  if [[ -z "$out" ]]; then
    aws::note "no log groups in $(aws::region)"
    return 0
  fi
  printf '%s\n' "$out" |
    awk -F'\t' -v dim="$dim" -v rst="$rst" -v name="$name" -v sort="$sort" -v hl=$'\e['"${hl}m" '
      function human(b) { return b >= 1e9 ? sprintf("%.1f GB", b / 1e9) : b >= 1e6 ? sprintf("%.1f MB", b / 1e6) : b >= 1e3 ? sprintf("%.1f KB", b / 1e3) : b " B" }
      { shown = length($1) > 48 ? "…" substr($1, length($1) - 46) : $1
        bytes = $2 + 0
        size = sprintf("%9s", human(bytes))
        key = sort == "size" ? sprintf("%016d", 1e15 - bytes) : tolower($1)
        printf "%s\t%s\t%s%s%-48s%s %s%s%s %s%s%s\t%s\t%s\037%s\037%s\037%s\n", key, $1, name, (sort == "name" ? hl : ""), shown, rst,
          (sort == "size" ? hl : ""), size, rst, dim, ($3 == "None" ? "never expires" : $3 == 1 ? "1 day" : $3 " days"), rst, $1, bytes, $3, $4, $5 }' |
    LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" aws
  aws::source "$@"
}
