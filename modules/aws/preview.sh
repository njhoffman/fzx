#!/usr/bin/env bash
# aws preview, from the row's own details (source.sh): an EC2 or RDS instance's without a request; a log group's
# size and retention, then the latest events of its newest stream; an ECS cluster's counts, then its services; an
# EKS cluster's details, then its node groups. Under fzx what takes a request is kept in the session for
# FZX_AWS_PREVIEW_TTL seconds, so moving back to a row is immediate.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# aws::_row <label> <value>: one line, left out when AWS sent no value
aws::_row() {
  [[ -n "$2" && "$2" != None ]] || return 0
  printf '%s%-10s%s %s\n' "$_D" "$1" "$_R" "$2"
}

# aws::_cached <key> <command...>: the command's output, kept in the session while it is younger than
# FZX_AWS_PREVIEW_TTL. Only a whole, successful answer is kept: fzf kills a preview when the cursor moves on, and
# the next read (ctrl-r) empties the directory. Standalone, or with a ttl of 0, the command just runs
aws::_cached() {
  local key="$1" ttl="${FZX_AWS_PREVIEW_TTL:-60}" dir file now mtime rc=0
  shift
  if [[ -z "${FZX_SESSION_DIR:-}" ]] || ((ttl <= 0)); then
    "$@"
    return
  fi
  dir="$FZX_SESSION_DIR/aws_preview"
  file="$dir/$(printf '%s' "$key" | md5sum | cut -d' ' -f1)"
  if [[ -f "$file" ]]; then
    printf -v now '%(%s)T' -1
    mtime="$(stat -c %Y -- "$file")"
    if ((now - mtime < ttl)); then
      cat -- "$file"
      return 0
    fi
  fi
  mkdir -p -- "$dir" || return
  "$@" > "$file.$BASHPID" || rc=$?
  cat -- "$file.$BASHPID"
  if ((rc == 0)); then mv -f -- "$file.$BASHPID" "$file"; else rm -f -- "$file.$BASHPID"; fi
  return "$rc"
}

# aws::_ms <milliseconds since the epoch> <var>: as a local date and time
aws::_ms() {
  local _s="${1%???}"
  if [[ "$1" =~ ^[0-9]{4,}$ ]]; then printf -v "$2" '%(%F %T)T' "$_s"; else printf -v "$2" '%s' "$1"; fi
}

# aws::preview_ec2 <id> <name> <details>
aws::preview_ec2() {
  local state type public private zone launched image vpc subnet key groups tags
  IFS=$'\x1f' read -r state type public private zone launched image vpc subnet key groups tags <<< "$3"
  printf '%s%s%s  %s\n\n' "$_B" "$2" "$_R" "$state"
  aws::_row id "$1"
  aws::_row type "$type"
  aws::_row public "$public"
  aws::_row private "$private"
  aws::_row zone "$zone"
  aws::_row launched "$launched"
  aws::_row image "$image"
  aws::_row vpc "$vpc"
  aws::_row subnet "$subnet"
  aws::_row key "$key"
  aws::_row groups "$groups"
  aws::_row tags "$tags"
}

# aws::preview_logs <group> <details>
aws::preview_logs() {
  local bytes retention created class when
  IFS=$'\x1f' read -r bytes retention created class <<< "$2"
  aws::_ms "$created" when
  printf '%s%s%s\n\n' "$_B" "$1" "$_R"
  aws::_row stored "$bytes bytes"
  case "$retention" in
    None) aws::_row retention "never expires" ;;
    1) aws::_row retention "1 day" ;;
    *) aws::_row retention "$retention days" ;;
  esac
  aws::_row class "$class"
  aws::_row created "$when"
  aws::_cached "logs:$1" aws::_log_events "$1"
}

# aws::_log_events <group>: the latest events of its newest stream; false when they cannot be read, with the
# error in place of the events
aws::_log_events() {
  local stream out ts msg when
  stream="$(aws::cli logs describe-log-streams "--log-group-name=$1" --order-by LastEventTime --descending \
    --limit 1 --no-paginate --query 'logStreams[0].logStreamName' --output text 2>&1)" || {
    printf '\n%s\n' "$stream"
    return 1
  }
  if [[ -z "$stream" || "$stream" == None ]]; then
    printf '\n%sno events%s\n' "$_D" "$_R"
    return 0
  fi
  printf '\n%slatest events%s  %s%s%s\n' "$_B" "$_R" "$_D" "$stream" "$_R"
  out="$(aws::cli logs get-log-events "--log-group-name=$1" "--log-stream-name=$stream" --no-start-from-head \
    --limit "${FZX_AWS_LOG_LINES:-40}" --query 'events[].[timestamp, message]' --output text 2>&1)" || {
    printf '%s\n' "$out"
    return 1
  }
  while IFS=$'\t' read -r ts msg; do
    # a message of several lines: only the first has a timestamp
    if [[ "$ts" =~ ^[0-9]{13}$ ]]; then
      aws::_ms "$ts" when
      printf '%s%s%s %s\n' "$_D" "$when" "$_R" "$msg"
    else
      printf '%s\n' "$ts${msg:+$'\t'$msg}"
    fi
  done <<< "$out"
}

# aws::preview_ecs <cluster> <details>
aws::preview_ecs() {
  local status services running pending instances arn
  IFS=$'\x1f' read -r status services running pending instances arn <<< "$2"
  printf '%s%s%s  %s\n\n' "$_B" "$1" "$_R" "$status"
  aws::_row services "$services"
  aws::_row running "$running tasks"
  aws::_row pending "$pending tasks"
  aws::_row instances "$instances"
  aws::_row arn "$arn"
  aws::_cached "ecs:$1" aws::_ecs_services "$1"
}

# aws::_ecs_services <cluster>: its services with their task counts (DescribeServices takes 10 at a time: the
# first 10, and how many more); false when they cannot be read
aws::_ecs_services() {
  local out arns=() rows
  out="$(aws::cli ecs list-services --cluster "$1" --query 'serviceArns[]' --output text 2>&1)" || {
    printf '\n%s\n' "$out"
    return 1
  }
  aws::_words arns "$out"
  if ((${#arns[@]} == 0)); then
    printf '\n%sno services%s\n' "$_D" "$_R"
    return 0
  fi
  printf '\n%sservices%s\n' "$_B" "$_R"
  rows="$(aws::cli ecs describe-services --cluster "$1" --services "${arns[@]:0:10}" --output text \
    --query 'services[].[serviceName, status, runningCount, desiredCount]' 2>&1)" || {
    printf '%s\n' "$rows"
    return 1
  }
  printf '%s\n' "$rows" | awk -F'\t' '{ printf "  %-32s %-10s %s/%s tasks\n", $1, $2, $3, $4 }'
  ((${#arns[@]} <= 10)) || printf '  %sand %s more%s\n' "$_D" "$((${#arns[@]} - 10))" "$_R"
}

# aws::preview_eks <cluster> <details>
aws::preview_eks() {
  local status version platform endpoint created role vpc subnets
  IFS=$'\x1f' read -r status version platform endpoint created role vpc subnets <<< "$2"
  printf '%s%s%s  %s\n\n' "$_B" "$1" "$_R" "$status"
  aws::_row version "$version"
  aws::_row platform "$platform"
  aws::_row endpoint "$endpoint"
  aws::_row created "$created"
  aws::_row role "$role"
  aws::_row vpc "$vpc"
  aws::_row subnets "$subnets"
  aws::_cached "eks:$1" aws::_eks_nodegroups "$1"
}

# aws::_eks_nodegroups <cluster>: their names; false when they cannot be read
aws::_eks_nodegroups() {
  local out groups=() g
  out="$(aws::cli eks list-nodegroups --cluster-name "$1" --query 'nodegroups[]' --output text 2>&1)" || {
    printf '\n%s\n' "$out"
    return 1
  }
  aws::_words groups "$out"
  if ((${#groups[@]} == 0)); then
    printf '\n%sno node groups%s\n' "$_D" "$_R"
    return 0
  fi
  printf '\n%snode groups%s\n' "$_B" "$_R"
  for g in "${groups[@]}"; do printf '  %s\n' "$g"; done
}

# aws::preview_rds <instance> <details>
aws::preview_rds() {
  local status engine version class zone address port multiaz storage type public encrypted created cluster vpc
  IFS=$'\x1f' read -r status engine version class zone address port multiaz storage type public encrypted created cluster vpc <<< "$2"
  printf '%s%s%s  %s\n\n' "$_B" "$1" "$_R" "$status"
  [[ "$version" == None ]] && version="" || version=" $version"
  aws::_row engine "$engine$version"
  aws::_row class "$class"
  aws::_row zone "$zone"
  if [[ "$address" != None ]]; then aws::_row endpoint "$address:$port"; fi
  aws::_row multi-az "$multiaz"
  [[ "$type" == None ]] && type="" || type=" $type"
  if [[ "$storage" != None ]]; then aws::_row storage "$storage GiB$type"; fi
  aws::_row public "$public"
  aws::_row encrypted "$encrypted"
  aws::_row created "$created"
  aws::_row cluster "$cluster"
  aws::_row vpc "$vpc"
}

# aws::preview <id> <name> <details>: an empty id is a row explaining an empty or unreadable list
aws::preview() {
  local _B=$'\e[1m' _D=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" _R=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && _B="" _D="" _R=""
  if [[ -z "${1:-}" ]]; then
    printf '%s\n' "${2:-}"
    return 0
  fi
  case "${FZX_MODE:-ec2}" in
    ec2) aws::preview_ec2 "$1" "${2:-}" "${3:-}" ;;
    logs) aws::preview_logs "$1" "${3:-}" ;;
    ecs) aws::preview_ecs "$1" "${3:-}" ;;
    eks) aws::preview_eks "$1" "${3:-}" ;;
    rds) aws::preview_rds "$1" "${3:-}" ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" aws
  aws::preview "$@"
}
