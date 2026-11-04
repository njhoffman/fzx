#!/usr/bin/env bash
# aws source and preview for the plain lists, sourced by source.sh: one table row per mode, one way to draw
# them. Hidden modes (components.tsv) open from the menu: volumes, vpcs, subnets, sgs, db-subnets, cache-subnets.
# shellcheck disable=SC2034  # AWS_* are read by the callers, source.sh, preview.sh and manifest.sh
# aws::_spec <mode> sets:
#   AWS_WHAT    what the list is, for its messages
#   AWS_CMD     the CLI's service and operation
#   AWS_QUERY   the fields: id, label, then the rest; label is what ctrl-y copies (None: the id)
#   AWS_IDS     a query for the ids alone, for the menu's count
#   AWS_COLS    the display: FIELD:WIDTH, comma-separated (the first is the name, a width of 0 is unpadded)
#   AWS_STATE   the field colored as a state (0: none)
#   AWS_HEADER  the header row's cells: NAME WIDTH RIGHT...
#   AWS_LABELS  the preview's labels for field 3 onwards
aws::_spec() {
  # shellcheck disable=SC2016  # the backticks are JMESPath literals
  local name='Tags[?Key==`Name`].Value | [0]' ids='join(`", "`, Subnets[].SubnetIdentifier)'
  AWS_STATE=0
  case "$1" in
    volumes)
      AWS_WHAT="EBS volumes" AWS_CMD=(ec2 describe-volumes) AWS_IDS='Volumes[].VolumeId'
      AWS_QUERY="Volumes[].[VolumeId, $name, State, Size, VolumeType, AvailabilityZone, Encrypted, Iops, CreateTime, Attachments[0].InstanceId, SnapshotId]"
      AWS_COLS=2:28,1:22,3:10,4:5,5:6,6:0 AWS_STATE=3
      AWS_HEADER=(NAME 28 0 ID 22 0 STATE 10 0 GIB 5 0 TYPE 6 0 ZONE 0 0)
      AWS_LABELS=(state size type zone encrypted iops created attached snapshot)
      ;;
    vpcs)
      AWS_WHAT="VPCs" AWS_CMD=(ec2 describe-vpcs) AWS_IDS='Vpcs[].VpcId'
      AWS_QUERY="Vpcs[].[VpcId, $name, State, CidrBlock, IsDefault, DhcpOptionsId, InstanceTenancy]"
      AWS_COLS=2:28,1:22,3:10,4:18,5:0 AWS_STATE=3
      AWS_HEADER=(NAME 28 0 ID 22 0 STATE 10 0 CIDR 18 0 DEFAULT 0 0)
      AWS_LABELS=(state cidr default dhcp tenancy)
      ;;
    subnets)
      AWS_WHAT="subnets" AWS_CMD=(ec2 describe-subnets) AWS_IDS='Subnets[].SubnetId'
      AWS_QUERY="Subnets[].[SubnetId, $name, State, VpcId, CidrBlock, AvailabilityZone, AvailableIpAddressCount, MapPublicIpOnLaunch, DefaultForAz]"
      AWS_COLS=2:28,1:25,3:10,5:18,6:12,7:0 AWS_STATE=3
      AWS_HEADER=(NAME 28 0 ID 25 0 STATE 10 0 CIDR 18 0 ZONE 12 0 FREE 0 0)
      AWS_LABELS=(state vpc cidr zone free-ips public default)
      ;;
    sgs)
      AWS_WHAT="security groups" AWS_CMD=(ec2 describe-security-groups) AWS_IDS='SecurityGroups[].GroupId'
      # shellcheck disable=SC2016  # the backticks are JMESPath literals
      AWS_QUERY='SecurityGroups[].[GroupId, GroupName, VpcId, Description, join(`", "`, IpPermissions[].join(`"/"`, [IpProtocol, to_string(FromPort), to_string(ToPort)])), join(`", "`, IpPermissionsEgress[].join(`"/"`, [IpProtocol, to_string(FromPort), to_string(ToPort)]))]'
      AWS_COLS=2:28,1:21,3:22,4:0
      AWS_HEADER=(NAME 28 0 ID 21 0 VPC 22 0 DESCRIPTION 0 0)
      AWS_LABELS=(vpc about inbound outbound)
      ;;
    db-subnets)
      AWS_WHAT="RDS subnet groups" AWS_CMD=(rds describe-db-subnet-groups) AWS_IDS='DBSubnetGroups[].DBSubnetGroupName'
      AWS_QUERY="DBSubnetGroups[].[DBSubnetGroupName, DBSubnetGroupName, SubnetGroupStatus, VpcId, DBSubnetGroupDescription, $ids]"
      AWS_COLS=2:32,3:10,4:22,5:0 AWS_STATE=3
      AWS_HEADER=(NAME 32 0 STATUS 10 0 VPC 22 0 DESCRIPTION 0 0)
      AWS_LABELS=(status vpc about subnets)
      ;;
    cache)
      AWS_WHAT="ElastiCache clusters" AWS_CMD=(elasticache describe-cache-clusters) AWS_IDS='CacheClusters[].CacheClusterId'
      AWS_QUERY='CacheClusters[].[CacheClusterId, CacheClusterId, CacheClusterStatus, Engine, EngineVersion, CacheNodeType, NumCacheNodes, PreferredAvailabilityZone, ReplicationGroupId, CacheClusterCreateTime, CacheSubnetGroupName]'
      AWS_COLS=2:32,3:12,4:8,5:9,6:16,7:0 AWS_STATE=3
      AWS_HEADER=(NAME 32 0 STATUS 12 0 ENGINE 8 0 VERSION 9 0 NODE 16 0 NODES 0 0)
      AWS_LABELS=(status engine version node nodes zone replicas created subnets)
      ;;
    cache-subnets)
      AWS_WHAT="ElastiCache subnet groups" AWS_CMD=(elasticache describe-cache-subnet-groups) AWS_IDS='CacheSubnetGroups[].CacheSubnetGroupName'
      AWS_QUERY="CacheSubnetGroups[].[CacheSubnetGroupName, CacheSubnetGroupName, VpcId, CacheSubnetGroupDescription, $ids]"
      AWS_COLS=2:32,3:22,4:0
      AWS_HEADER=(NAME 32 0 VPC 22 0 DESCRIPTION 0 0)
      AWS_LABELS=(vpc about subnets)
      ;;
    *) return 1 ;;
  esac
}

# aws::_source_table <mode>: a table row's list, by name
aws::_source_table() {
  local out
  aws::_spec "$1" || return 2
  fzx::require header
  fzx::header_print 1 NAME "${AWS_HEADER[@]}"
  aws::_read "$AWS_WHAT" out "${AWS_CMD[@]}" --output text --query "$AWS_QUERY" || return 1
  if [[ -z "$out" ]]; then
    aws::note "no $AWS_WHAT in $(aws::region)"
    return 0
  fi
  aws::_awk_setup
  # shellcheck disable=SC2016  # awk's fields
  printf '%s\n' "$out" |
    awk -F'\t' "${AWS_AWK[@]}" -v cols="$AWS_COLS" -v statef="$AWS_STATE" -v sort="${FZX_SORT:-name}" "$AWS_AWK_LIB"'
      function state_color(s) { s = tolower(s)
        if (s ~ /^(available|in-use|complete|active)$/) return run
        if (s ~ /error|fail|delet|incompatible/) return stop
        return pend }
      BEGIN { n = split(cols, col, ",") }
      { label = ($2 == "None" || $2 == "") ? "-" : $2
        line = ""
        for (i = 1; i <= n; i++) {
          split(col[i], p, ":"); f = p[1] + 0; w = p[2] + 0
          v = (f == 2) ? label : ($f == "None" || $f == "") ? "-" : $f
          if (w && length(v) > w) v = clip(v, w)
          c = (i == 1) ? name : (f == statef) ? state_color(v) : (i == n || i == 2) ? dim : ""
          line = line (i > 1 ? " " : "") cell(c, v, w, i == 1 && sort == "name")
        }
        details = ""
        for (f = 3; f <= NF; f++) details = details (f > 3 ? "\037" : "") $f
        printf "%s\t%s\t%s\t%s\t%s\n", tolower(label), $1, line, (label == "-" ? $1 : label), details }' |
    LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
}

# aws::_vault_profiles: aws-vault's profiles, one per line; nothing when it is off or not installed
aws::_vault_profiles() {
  [[ "${FZX_AWS_VAULT:-auto}" != off ]] && command -v aws-vault > /dev/null || return 0
  env -u AWS_VAULT aws-vault list --profiles 2> /dev/null
}

# aws::_config_region <profile>: its region in the CLI's config file, without starting the CLI
aws::_config_region() {
  local file="${AWS_CONFIG_FILE:-$HOME/.aws/config}" head="[profile $1]"
  [[ "$1" == default ]] && head="[default]"
  [[ -r "$file" ]] || return 0
  awk -v head="$head" '/^\[/ { on = ($0 == head) } on && $1 == "region" { sub(/^[^=]*=[ \t]*/, ""); print; exit }' "$file"
}

# aws::_source_profiles: the environment (what the CLI resolves unaided), then the CLI's and aws-vault's profiles,
# the one in use marked. Fields: profile (- for the environment), display, name, kind
aws::_source_profiles() {
  local err out vault name kind region mark rows=() dim rst=$'\e[0m' cname run
  dim="$(aws::color dim '38;5;244')" cname="$(aws::color aws_name '1;38;5;111')" run="$(aws::color aws_running '38;5;114')"
  fzx::require header
  fzx::header_print 1 NAME "" 1 0 NAME 28 0 KIND 8 0 REGION 0 0
  err="$(mktemp)" || return 2
  out="$(command aws configure list-profiles 2> "$err")" || {
    aws::failed "profiles" "$err"
    rm -f -- "$err"
    return 1
  }
  rm -f -- "$err"
  vault="$(aws::_vault_profiles)"
  aws::_selected
  mark=" "
  [[ -z "$AWS_SEL_KIND" ]] && mark="●"
  printf -- '-\t%s%s%s %s%-28s%s %-8s %s%s%s\tenvironment\tenvironment\n' "$run" "$mark" "$rst" "$cname" environment "$rst" "-" "$dim" "${AWS_REGION:-${AWS_DEFAULT_REGION:--}}" "$rst"
  mapfile -t rows < <(printf '%s\n%s\n' "$out" "$vault" | grep -v '^$' | LC_ALL=C sort -u)
  for name in "${rows[@]}"; do
    kind=profile
    grep -qxF -- "$name" <<< "$vault" && kind=vault
    region="$(aws::_config_region "$name")"
    mark=" "
    [[ "$AWS_SEL_NAME" == "$name" ]] && mark="●"
    printf '%s\t%s%s%s %s%-28s%s %-8s %s%s%s\t%s\t%s\n' "$name" "$run" "$mark" "$rst" "$cname" "$name" "$rst" "$kind" "$dim" "${region:--}" "$rst" "$name" "$kind"
  done
}
