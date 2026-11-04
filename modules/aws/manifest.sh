#!/usr/bin/env bash
# aws menu entries, wherever the CLI is installed: credentials are not checked here, since that takes a
# request, and a list that cannot be read says why

aws::manifest() {
  fzx::entry aws "AWS EC2 instances"
  fzx::entry aws:logs "AWS CloudWatch log groups"
}

aws::applicable() { command -v aws > /dev/null; }

# aws::summary <target>: how many, from one request; nothing when it fails
aws::summary() {
  source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
  local out
  case "$1" in
    aws)
      out="$(aws::cli ec2 describe-instances --query 'Reservations[].Instances[].State.Name' --output text 2> /dev/null)" || return 0
      printf '%s\n' "$out" | tr -s '[:space:]' '\n' |
        awk '$1 == "running" { r++ } $1 == "stopped" { s++ } END { printf "%d running, %d stopped\n", r, s }'
      ;;
    aws:logs)
      out="$(aws::cli logs describe-log-groups --query 'logGroups[].storedBytes' --output text 2> /dev/null)" || return 0
      printf '%s\n' "$out" | wc -w | awk '{ printf "%d log group%s\n", $1, $1 == 1 ? "" : "s" }'
      ;;
  esac
}
