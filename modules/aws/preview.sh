#!/usr/bin/env bash
# aws preview, from the row's own details (source.sh): an instance's state, addresses, network and tags
# without a request; a log group's size and retention, then the latest events of its newest stream.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# aws::_row <label> <value>: one line, left out when AWS sent no value
aws::_row() {
  [[ -n "$2" && "$2" != None ]] || return 0
  printf '%s%-10s%s %s\n' "$_D" "$1" "$_R" "$2"
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
  local bytes retention created class when stream ts msg
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
  stream="$(aws::cli logs describe-log-streams "--log-group-name=$1" --order-by LastEventTime --descending \
    --limit 1 --no-paginate --query 'logStreams[0].logStreamName' --output text 2>&1)" || {
    printf '\n%s\n' "$stream"
    return 0
  }
  if [[ -z "$stream" || "$stream" == None ]]; then
    printf '\n%sno events%s\n' "$_D" "$_R"
    return 0
  fi
  printf '\n%slatest events%s  %s%s%s\n' "$_B" "$_R" "$_D" "$stream" "$_R"
  aws::cli logs get-log-events "--log-group-name=$1" "--log-stream-name=$stream" --no-start-from-head \
    --limit "${FZX_AWS_LOG_LINES:-40}" --query 'events[].[timestamp, message]' --output text 2>&1 |
    while IFS=$'\t' read -r ts msg; do
      # a message of several lines: only the first has a timestamp
      if [[ "$ts" =~ ^[0-9]{13}$ ]]; then
        aws::_ms "$ts" when
        printf '%s%s%s %s\n' "$_D" "$when" "$_R" "$msg"
      else
        printf '%s\n' "$ts${msg:+$'\t'$msg}"
      fi
    done
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
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" aws
  aws::preview "$@"
}
