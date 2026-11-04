#!/usr/bin/env bash
# aws actions on the selected ids of the current mode. Only start, stop and reboot of EC2 instances change
# anything in AWS, each confirmed first; nothing here terminates or deletes. Rows with an empty id (an empty or
# unreadable list) are skipped.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# aws::console_url <mode> <region> <id>: the resource's page in the AWS console. The console reads a log
# group's name with its / and # encoded twice, as $252F and $2523
aws::console_url() {
  local base="https://$2.console.aws.amazon.com" id="$3"
  case "$1" in
    ec2) printf '%s/ec2/home?region=%s#InstanceDetails:instanceId=%s\n' "$base" "$2" "$id" ;;
    logs)
      id="${id//\//\$252F}"
      id="${id//#/\$2523}"
      printf '%s/cloudwatch/home?region=%s#logsV2:log-groups/log-group/%s\n' "$base" "$2" "$id"
      ;;
    ecs) printf '%s/ecs/v2/clusters/%s?region=%s\n' "$base" "$id" "$2" ;;
    eks) printf '%s/eks/home?region=%s#/clusters/%s\n' "$base" "$2" "$id" ;;
    rds) printf '%s/rds/home?region=%s#database:id=%s;is-cluster=false\n' "$base" "$2" "$id" ;;
    volumes) printf '%s/ec2/home?region=%s#VolumeDetails:volumeId=%s\n' "$base" "$2" "$id" ;;
    vpcs) printf '%s/vpcconsole/home?region=%s#VpcDetails:VpcId=%s\n' "$base" "$2" "$id" ;;
    subnets) printf '%s/vpcconsole/home?region=%s#SubnetDetails:subnetId=%s\n' "$base" "$2" "$id" ;;
    sgs) printf '%s/ec2/home?region=%s#SecurityGroup:groupId=%s\n' "$base" "$2" "$id" ;;
    db-subnets) printf '%s/rds/home?region=%s#db-subnet-group:id=%s\n' "$base" "$2" "$id" ;;
    cache) printf '%s/elasticache/home?region=%s#/redis/%s\n' "$base" "$2" "$id" ;;
    cache-subnets) printf '%s/elasticache/home?region=%s#/subnet-groups\n' "$base" "$2" ;;
  esac
}

# aws::logs_merged <group...>: follow several log groups at once, each line prefixed with its group's name
# in its own color; ctrl-c stops them all
aws::logs_merged() {
  local id i=0 pids=() colors=(81 114 255 147 117 159) prefix
  for id in "$@"; do
    printf -v prefix '\e[38;5;%sm[%s]\e[0m ' "${colors[i % 6]}" "$id"
    aws::cli logs tail "$id" --follow --format short --since "${FZX_AWS_TAIL_SINCE:-1h}" 2>&1 |
      awk -v p="$prefix" '{ print p $0; fflush() }' &
    pids+=("$!")
    i=$((i + 1))
  done
  printf '\e[2mfollowing %s log groups (ctrl-c returns)\e[0m\n' "$#"
  wait "${pids[@]}" 2> /dev/null
  kill "${pids[@]}" 2> /dev/null
}

# aws::json: stdin colored when jq is there, into the pager
aws::json() { { if command -v jq > /dev/null; then jq -C .; else cat; fi; } | ${PAGER:-less -R}; }

# aws::_not_here <action> <mode>: refuse an action the mode has no use for
aws::_not_here() {
  printf 'aws: %s does not apply to %s\n' "$1" "$2" >&2
  return 2
}

# aws::_report <rc>: show a failure until a key is pressed; execute would otherwise wipe it at once
aws::_report() {
  (($1 == 0)) && return 0
  [[ -t 1 ]] || return "$1"
  printf '\n\e[31mfailed (exit %s)\e[0m, press a key ' "$1"
  IFS= read -rsn1 < /dev/tty || :
  return "$1"
}

# aws::_use <profile>: use it from now on (- : back to what the CLI resolves unaided). What the session kept was
# read as the other profile
aws::_use() {
  local vault kind=profile
  mkdir -p -- "$FZX_STATE_DIR/aws" || return
  if [[ "$1" == - ]]; then
    rm -f -- "$FZX_STATE_DIR/aws/profile"
  else
    vault="$(aws::_vault_profiles)"
    grep -qxF -- "$1" <<< "$vault" && kind=vault
    printf '%s %s\n' "$kind" "$1" > "$FZX_STATE_DIR/aws/profile"
  fi
  [[ -z "${FZX_SESSION_DIR:-}" ]] || rm -rf -- "$FZX_SESSION_DIR"/data/* "$FZX_SESSION_DIR/aws_preview"
}

# aws::action <action> <id...>
aws::action() {
  local action="${1:-}" mode="${FZX_MODE:-ec2}" id ids=() rc=0 region
  shift
  for id in "$@"; do [[ -z "$id" ]] || ids+=("$id"); done
  ((${#ids[@]})) || return 0
  case "$action:$mode" in
    console:profiles | inspect:profiles) aws::_not_here "$action" "$mode" || rc=$? ;;
    console:*)
      region="$(aws::region)"
      [[ -n "$region" ]] || { printf 'aws: no Region configured\n' >&2; return 2; }
      fzx::require builtin
      for id in "${ids[@]}"; do fzx::open_url "$(aws::console_url "$mode" "$region" "$id")" || rc=$?; done
      ;;
    logs:ec2)
      for id in "${ids[@]}"; do
        printf '=== %s\n' "$id"
        aws::cli ec2 get-console-output --instance-id "$id" --latest --query Output --output text 2>&1 || rc=$?
      done | aws::clean | ${PAGER:-less -R}
      ;;
    logs:logs)
      # ctrl-c ends the follow, not fzx
      trap : INT
      if ((${#ids[@]} == 1)); then
        printf '\e[2maws logs tail %s --follow (ctrl-c returns)\e[0m\n' "${ids[0]}"
        aws::cli logs tail "${ids[0]}" --follow --format short --since "${FZX_AWS_TAIL_SINCE:-1h}" || rc=$?
      else
        aws::logs_merged "${ids[@]}"
      fi
      trap - INT
      ;;
    inspect:ec2) aws::cli ec2 describe-instances --instance-ids "${ids[@]}" --output json 2>&1 | aws::json ;;
    inspect:logs)
      # the API takes a prefix: only the exact group
      for id in "${ids[@]}"; do
        aws::cli logs describe-log-groups "--log-group-name-prefix=$id" --output json \
          --query "logGroups[?logGroupName=='$id'] | [0]" 2>&1
      done | aws::json
      ;;
    inspect:ecs) aws::cli ecs describe-clusters --clusters "${ids[@]}" --output json 2>&1 | aws::json ;;
    inspect:eks)
      for id in "${ids[@]}"; do aws::cli eks describe-cluster --name "$id" --output json 2>&1; done | aws::json
      ;;
    inspect:rds)
      for id in "${ids[@]}"; do aws::cli rds describe-db-instances --db-instance-identifier "$id" --output json 2>&1; done | aws::json
      ;;
    inspect:volumes) aws::cli ec2 describe-volumes --volume-ids "${ids[@]}" --output json 2>&1 | aws::json ;;
    inspect:vpcs) aws::cli ec2 describe-vpcs --vpc-ids "${ids[@]}" --output json 2>&1 | aws::json ;;
    inspect:subnets) aws::cli ec2 describe-subnets --subnet-ids "${ids[@]}" --output json 2>&1 | aws::json ;;
    inspect:sgs) aws::cli ec2 describe-security-groups --group-ids "${ids[@]}" --output json 2>&1 | aws::json ;;
    inspect:db-subnets)
      for id in "${ids[@]}"; do aws::cli rds describe-db-subnet-groups --db-subnet-group-name "$id" --output json 2>&1; done | aws::json
      ;;
    inspect:cache)
      for id in "${ids[@]}"; do aws::cli elasticache describe-cache-clusters --cache-cluster-id "$id" --show-cache-node-info --output json 2>&1; done | aws::json
      ;;
    inspect:cache-subnets)
      for id in "${ids[@]}"; do aws::cli elasticache describe-cache-subnet-groups --cache-subnet-group-name "$id" --output json 2>&1; done | aws::json
      ;;
    start:ec2 | stop:ec2 | reboot:ec2)
      aws::cli ec2 "$action-instances" --instance-ids "${ids[@]}" --output text --query 'length(@)' > /dev/null || rc=$?
      aws::_report "$rc" || :
      ;;
    use:profiles) aws::_use "${ids[0]}" ;;
    login:profiles)
      [[ "${ids[0]}" != - ]] || { printf 'aws: the environment has no aws-vault login\n' >&2; return 2; }
      command -v aws-vault > /dev/null || { printf 'aws: aws-vault is not installed\n' >&2; return 2; }
      env -u AWS_VAULT aws-vault login "${ids[0]}" || rc=$?
      ;;
    logs:* | start:* | stop:* | reboot:* | use:* | login:*) aws::_not_here "$action" "$mode" || rc=$? ;;
    *)
      printf 'aws: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" aws
  aws::action "$@"
}
