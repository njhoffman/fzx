#!/usr/bin/env bash
# aws menu entries, wherever the CLI is installed: credentials are not checked here, since that takes a
# request, and a list that cannot be read says why

aws::manifest() {
  fzx::entry aws "AWS EC2 instances"
  fzx::entry aws:logs "AWS CloudWatch log groups"
  fzx::entry aws:ecs "AWS ECS clusters"
  fzx::entry aws:eks "AWS EKS clusters"
  fzx::entry aws:rds "AWS RDS instances"
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
    aws:ecs)
      out="$(aws::cli ecs list-clusters --query 'clusterArns[]' --output text 2> /dev/null)" || return 0
      printf '%s\n' "$out" | wc -w | awk '{ printf "%d cluster%s\n", $1, $1 == 1 ? "" : "s" }'
      ;;
    aws:eks)
      out="$(aws::cli eks list-clusters --query 'clusters[]' --output text 2> /dev/null)" || return 0
      printf '%s\n' "$out" | wc -w | awk '{ printf "%d cluster%s\n", $1, $1 == 1 ? "" : "s" }'
      ;;
    aws:rds)
      out="$(aws::cli rds describe-db-instances --query 'DBInstances[].DBInstanceStatus' --output text 2> /dev/null)" || return 0
      printf '%s\n' "$out" | tr -s '[:space:]' '\n' |
        awk '$1 == "available" { a++ } NF { n++ } END { printf "%d available of %d\n", a, n }'
      ;;
  esac
}
