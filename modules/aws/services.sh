#!/usr/bin/env bash
# aws source for ecs, eks and rds, sourced by source.sh; rows as described there. Details per mode:
#   ecs  status services running pending instances arn
#   eks  status version platform endpoint created role vpc subnets
#   rds  status engine version class zone address port multi-az storage type public encrypted created cluster vpc

# what these lists' rows share: AWS_AWK (awk -v) and AWS_AWK_LIB (cell(), clip()); hl: the sorted column
aws::_awk_setup() {
  local hl="${FZX_COLORS[sorted]:-4}"
  AWS_AWK=(-v dim="$(aws::color dim '38;5;244')" -v rst=$'\e[0m' -v name="$(aws::color aws_name '1;38;5;111')"
    -v run="$(aws::color aws_running '38;5;114')" -v pend="$(aws::color aws_pending '38;5;252')"
    -v stop="$(aws::color aws_stopped '38;5;203')" -v sort="${FZX_SORT:-}" -v hl=$'\e['"${hl}m")
  # shellcheck disable=SC2016  # awk's fields
  AWS_AWK_LIB='
    function cell(color, text, w, on) { return on ? color hl text rst sprintf("%" (w - length(text) > 0 ? w - length(text) : 0) "s", "") : color sprintf("%-" w "s", text) rst }
    function clip(text, w) { return length(text) > w ? substr(text, 1, w - 1) "…" : text }'
}

# aws::_words <var> <text>: its whitespace-separated words into the array <var> (the CLI's text output has one
# line per page)
aws::_words() {
  local -n _w="$1"
  read -r -d '' -a _w <<< "$2" || :
}

aws::_source_ecs() {
  local out arns=() i rows="" batch rc=0
  fzx::require header
  fzx::header_print 1 NAME NAME 32 0 STATUS 10 0 SERVICES 8 1 RUNNING 7 1 PENDING 7 1 INSTANCES 0 0
  aws::_read "ECS clusters" out ecs list-clusters --query 'clusterArns[]' --output text || return 1
  aws::_words arns "$out"
  if ((${#arns[@]} == 0)); then
    aws::note "no ECS clusters in $(aws::region)"
    return 0
  fi
  # DescribeClusters takes 100 at a time
  for ((i = 0; i < ${#arns[@]}; i += 100)); do
    aws::_read "ECS clusters" batch ecs describe-clusters --clusters "${arns[@]:i:100}" --output text --query \
      'clusters[].[clusterName, status, activeServicesCount, runningTasksCount, pendingTasksCount, registeredContainerInstancesCount, clusterArn]' || {
      rc=1
      continue
    }
    rows+="$batch"$'\n'
  done
  aws::_awk_setup
  printf '%s' "$rows" |
    awk -F'\t' "${AWS_AWK[@]}" "$AWS_AWK_LIB"'
      NF { c = $2 == "ACTIVE" ? run : $2 == "FAILED" ? stop : pend
        printf "%s\t%s\t%s %s %8s %7s %7s %s%s%s\t%s\t%s\037%s\037%s\037%s\037%s\037%s\n", tolower($1), $1, cell(name, clip($1, 32), 32, sort == "name"),
          cell(c, $2, 10, 0), $3, $4, $5, dim, $6, rst, $1, $2, $3, $4, $5, $6, $7 }' |
    LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
  return "$rc"
}

aws::_source_eks() {
  local out names=() n i=0 rc=0 tmp f
  fzx::require header
  fzx::header_print 1 NAME NAME 32 0 STATUS 10 0 VERSION 8 0 ENDPOINT 0 0
  aws::_read "EKS clusters" out eks list-clusters --query 'clusters[]' --output text || return 1
  aws::_words names "$out"
  if ((${#names[@]} == 0)); then
    aws::note "no EKS clusters in $(aws::region)"
    return 0
  fi
  tmp="$(mktemp -d)" || return 2
  # one request per cluster, FZX_AWS_JOBS at a time: each CLI process takes over a second to start
  for n in "${names[@]}"; do
    # shellcheck disable=SC2016  # the backticks are JMESPath literals
    aws::cli eks describe-cluster --name "$n" --output text --query \
      'cluster.[name, status, version, platformVersion, endpoint, createdAt, roleArn, resourcesVpcConfig.vpcId, join(`", "`, resourcesVpcConfig.subnetIds || `[]`)]' \
      > "$tmp/$i.out" 2> "$tmp/$i.err" || : > "$tmp/$i.failed" &
    i=$((i + 1))
    ((i % ${FZX_AWS_JOBS:-8} == 0)) && wait
  done
  wait
  aws::_awk_setup
  cat -- "$tmp"/*.out |
    awk -F'\t' "${AWS_AWK[@]}" "$AWS_AWK_LIB"'
      NF { c = $2 == "ACTIVE" ? run : ($2 == "FAILED" || $2 == "DELETING") ? stop : pend
        printf "%s\t%s\t%s %s %-8s %s%s%s\t%s\t%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", tolower($1), $1, cell(name, clip($1, 32), 32, sort == "name"),
          cell(c, $2, 10, 0), ($3 == "None" ? "-" : $3), dim, ($5 == "None" ? "-" : $5), rst, $1, $2, $3, $4, $5, $6, $7, $8, $9 }' |
    LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
  for f in "$tmp"/*.failed; do
    [[ -e "$f" ]] || continue
    aws::failed "EKS cluster" "${f%.failed}.err"
    rc=1
  done
  rm -rf -- "$tmp"
  return "$rc"
}

aws::_source_rds() {
  local out sort="${FZX_SORT:-state}"
  fzx::require header
  fzx::header_print 1 "$([[ "$sort" == name ]] && echo NAME || echo STATE)" NAME 32 0 ENGINE 24 0 CLASS 16 0 STATE 13 0 ENDPOINT 0 0
  aws::_read "RDS instances" out rds describe-db-instances --output text --query \
    'DBInstances[].[DBInstanceIdentifier, DBInstanceStatus, Engine, EngineVersion, DBInstanceClass, AvailabilityZone, Endpoint.Address, Endpoint.Port, MultiAZ, AllocatedStorage, StorageType, PubliclyAccessible, StorageEncrypted, InstanceCreateTime, DBClusterIdentifier, DBSubnetGroup.VpcId]' ||
    return 1
  if [[ -z "$out" ]]; then
    aws::note "no RDS instances in $(aws::region)"
    return 0
  fi
  aws::_awk_setup
  printf '%s\n' "$out" |
    awk -F'\t' "${AWS_AWK[@]}" -v sort="$sort" "$AWS_AWK_LIB"'
      { c = $2 == "available" ? run : ($2 == "stopped" || $2 ~ /failed|incompatible/) ? stop : pend
        rank = $2 == "available" ? 0 : c == pend ? 1 : 2
        key = sort == "name" ? tolower($1) : rank
        details = $2
        for (f = 3; f <= 16; f++) details = details "\037" $f
        printf "%s\t%s\t%s %-24s %-16s %s %s%s%s\t%s\t%s\n", key, $1, cell(name, clip($1, 32), 32, sort == "name"), clip($3 " " $4, 24), $5,
          cell(c, $2, 13, sort == "state"), dim, ($7 == "None" ? "-" : $7), rst, $1, details }' |
    LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
}
