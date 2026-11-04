#!/usr/bin/env bats
# the aws module with a stubbed aws command (calls are logged; nothing touches AWS)

load test_helper

AWSM="$(readlink -f "$BATS_TEST_DIRNAME/../modules/aws")"

setup() {
  setup_fzx
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  CALLS="$BATS_TEST_TMPDIR/calls"
  OPENED="$BATS_TEST_TMPDIR/opened"
  cat > "$BATS_TEST_TMPDIR/bin/aws" << STUB
#!/usr/bin/env bash
printf 'pager=[%s] %s\n' "\${AWS_PAGER-unset}" "\$*" >> "$CALLS"
[[ -z "\${STUB_AWS_FAIL:-}" ]] || { printf '\n%s\n' "\$STUB_AWS_FAIL" >&2; exit 254; }
case "\$*" in
  'configure get region') echo us-east-2 ;;
  *'Instances[].State.Name'*)
    [[ -n "\${STUB_AWS_EMPTY:-}" ]] || printf 'running\tstopped\nrunning\tterminated\n' ;;
  *'ec2 describe-instances'*'--query'*)
    [[ -n "\${STUB_AWS_EMPTY:-}" ]] && exit 0
    printf 'i-old\tstopped\tzeta\tt3.micro\tNone\t10.0.0.9\tus-east-2a\t2026-01-01T00:00:00+00:00\tami-1\tvpc-1\tsubnet-1\tNone\tdefault\tName=zeta\n'
    printf 'i-web\trunning\talpha\tt3.small\t3.3.3.3\t10.0.0.1\tus-east-2b\t2026-02-02T00:00:00+00:00\tami-2\tvpc-1\tsubnet-2\tkey1\tweb, ssh\tName=alpha, env=prod\n'
    printf 'i-anon\tterminated\tNone\tt3.nano\tNone\tNone\tus-east-2c\t2026-03-03T00:00:00+00:00\tami-3\tNone\tNone\tNone\t\t\n' ;;
  *'ec2 describe-instances'*) echo '{"Reservations":[]}' ;;
  *'ec2 get-console-output'*) echo 'boot messages' ;;
  *'logGroups[].storedBytes'*) printf '1500\t2500000\t0\n' ;;
  *'logs describe-log-groups'*'logGroupName=='*) echo '{"logGroupName":"/app/api"}' ;;
  *'logs describe-log-groups'*)
    [[ -n "\${STUB_AWS_EMPTY:-}" ]] && exit 0
    printf '/app/web\t1500\t7\t1767225600000\tSTANDARD\n/app/api\t2500000\tNone\t1767225600000\tSTANDARD\n/app/idle\t0\t30\t1767225600000\tINFREQUENT_ACCESS\n' ;;
  *'logs describe-log-streams'*'/app/idle'*) echo None ;;
  *'logs describe-log-streams'*) echo stream-1 ;;
  *'logs get-log-events'*) printf '1767225600000\thello\tworld\ncontinued line\n' ;;
  *'logs tail'*) echo "tailed \$*" ;;
  *'ecs list-clusters'*)
    [[ -n "\${STUB_AWS_EMPTY:-}" ]] || printf 'arn:aws:ecs:r:1:cluster/web\tarn:aws:ecs:r:1:cluster/batch\n' ;;
  *'ecs describe-clusters'*'--query'*)
    printf 'web\tACTIVE\t2\t5\t1\t0\tarn:aws:ecs:r:1:cluster/web\nbatch\tINACTIVE\t0\t0\t0\t0\tarn:aws:ecs:r:1:cluster/batch\n' ;;
  *'ecs describe-clusters'*) echo '{"clusters":[]}' ;;
  *'ecs list-services'*'--cluster empty'*) ;;
  *'ecs list-services'*'--cluster many'*)
    for ((i = 1; i <= 12; i++)); do printf 'arn:s%s\t' "\$i"; done; echo ;;
  *'ecs list-services'*) echo 'arn:aws:ecs:r:1:service/web/api' ;;
  *'ecs describe-services'*) printf 'api\tACTIVE\t2\t3\n' ;;
  *'eks list-clusters'*)
    [[ -n "\${STUB_AWS_EMPTY:-}" ]] || printf 'prod\tdev\n' ;;
  *"eks describe-cluster --name \${STUB_EKS_FAIL:-none} "*) echo 'An error occurred (AccessDenied) when calling DescribeCluster' >&2; exit 254 ;;
  *'eks describe-cluster --name prod'*'--query'*) printf 'prod\tACTIVE\t1.33\teks.1\thttps://prod.eks\tt0\trole\tvpc-1\ta, b\n' ;;
  *'eks describe-cluster --name dev'*'--query'*) printf 'dev\tCREATING\tNone\tNone\tNone\tt1\trole\tNone\t\n' ;;
  *'eks describe-cluster'*) echo '{"cluster":{}}' ;;
  *'eks list-nodegroups'*'--cluster-name dev'*) ;;
  *'eks list-nodegroups'*) printf 'workers\tspot\n' ;;
  *'rds describe-db-instances'*'DBInstanceStatus --output'* | *'rds describe-db-instances --query DBInstances[].DBInstanceStatus'*) printf 'available\tstopped\n' ;;
  *'rds describe-db-instances'*'--query'*)
    [[ -n "\${STUB_AWS_EMPTY:-}" ]] && exit 0
    printf 'zeta\tstopped\tpostgres\t16.3\tdb.t3.micro\tus-east-2a\tzeta.rds\t5432\tFalse\t20\tgp3\tFalse\tTrue\tt0\tNone\tvpc-1\n'
    printf 'alpha\tavailable\tmysql\t8.0\tdb.t3.small\tus-east-2b\talpha.rds\t3306\tTrue\t50\tgp3\tFalse\tTrue\tt1\taurora-1\tvpc-1\n'
    printf 'new\tcreating\tpostgres\tNone\tdb.t3.micro\tNone\tNone\tNone\tFalse\tNone\tNone\tFalse\tTrue\tNone\tNone\tNone\n' ;;
  *'rds describe-db-instances'*) echo '{"DBInstances":[]}' ;;
  *'configure list-profiles'*) printf 'default\nwork\n' ;;
  *'sts get-caller-identity'*) echo 'arn:aws:iam::1:user/me' ;;
  *'ec2 describe-volumes'*'--query Volumes[].VolumeId'*) printf 'vol-1\tvol-2\n' ;;
  *'ec2 describe-volumes'*'--query'*)
    [[ -n "\${STUB_AWS_EMPTY:-}" ]] && exit 0
    printf 'vol-2\tNone\tavailable\t1\tgp3\tus-east-2a\tFalse\t3000\tt0\tNone\tNone\nvol-1\troot\tin-use\t8\tgp3\tus-east-2b\tTrue\t3000\tt1\ti-web\tsnap-1\n' ;;
  *'ec2 describe-security-groups'*'--query'*) printf 'sg-1\tweb\tvpc-1\tthe web tier\ttcp/443/443\t-1/null/null\n' ;;
  *'ec2 describe-vpcs'*'--query'*) printf 'vpc-1\tNone\tavailable\t172.31.0.0/16\tTrue\tdopt-1\tdefault\n' ;;
  *'ec2 describe-subnets'*'--query'*) printf 'subnet-1\tNone\tavailable\tvpc-1\t172.31.0.0/20\tus-east-2a\t4091\tTrue\tTrue\n' ;;
  *'rds describe-db-subnet-groups'*'--query'*) printf 'dbs\tdbs\tComplete\tvpc-1\tthe db subnets\ta, b\n' ;;
  *'elasticache describe-cache-clusters'*'--query'*) printf 'c1\tc1\tavailable\tredis\t7.1\tcache.t4g.micro\t1\tus-east-2a\tNone\tt0\tcs\n' ;;
  *'elasticache describe-cache-subnet-groups'*'--query'*) printf 'cs\tcs\tvpc-1\tthe cache subnets\ta, b\n' ;;
esac
exit 0
STUB
  cat > "$BATS_TEST_TMPDIR/bin/xdg-open" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$OPENED"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/aws" "$BATS_TEST_TMPDIR/bin/xdg-open"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" PAGER=cat
  unset AWS_REGION AWS_DEFAULT_REGION
}

plain() { sed 's/\x1b\[[0-9;:]*m//g'; }
src() { FZX_MODE="$1" "$AWSM/source.sh" | plain; }
prev() { FZX_MODE="$1" "$AWSM/preview.sh" "${@:2}" | plain; }
act() { FZX_MODE="$1" "$AWSM/actions.sh" "${@:2}"; }

@test "ec2: running first, then stopped, then gone; id, name and details in their fields" {
  run src ec2
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == i-web$'\t'*alpha*i-web*t3.small*running*3.3.3.3$'\t'alpha$'\t'running* ]]
  [[ "${lines[1]}" == i-old$'\t'*zeta*stopped*10.0.0.9$'\t'zeta$'\t'* ]]
  [[ "${lines[2]}" == i-anon$'\t'*terminated* ]]
  [ "${#lines[@]}" -eq 3 ]
}

@test "ec2: an instance with no Name tag or address shows dashes and copies its id" {
  run bash -c "FZX_MODE=ec2 '$AWSM/source.sh' | cut -f1,3 | tail -1"
  [ "$output" = $'i-anon\ti-anon' ]
  run src ec2
  [[ "${lines[2]}" == *' - '* && "${lines[2]}" != *None*$'\t'i-anon* ]]
}

@test "ec2: the running toggle filters on the server; off it asks for everything" {
  run src ec2
  ! grep -q 'instance-state-name' "$CALLS"
  FZX_TOGGLES=running run src ec2
  grep -q 'Name=instance-state-name,Values=running' "$CALLS"
}

@test "ec2: sort by name" {
  FZX_SORT=name run src ec2
  [[ "${lines[0]}" == i-anon$'\t'* ]]
  [[ "${lines[1]}" == i-web$'\t'* ]]
  [[ "${lines[2]}" == i-old$'\t'* ]]
}

@test "logs: by name or by size, sizes readable, retention named" {
  run src logs
  [[ "${lines[0]}" == /app/api$'\t'*'2.5 MB'*'never expires'$'\t'/app/api$'\t'* ]]
  [[ "${lines[1]}" == /app/idle$'\t'*'0 B'*'30 days'* ]]
  [[ "${lines[2]}" == /app/web$'\t'*'1.5 KB'*'7 days'* ]]
  FZX_SORT=size run src logs
  [[ "${lines[0]}" == /app/api$'\t'* && "${lines[1]}" == /app/web$'\t'* && "${lines[2]}" == /app/idle$'\t'* ]]
}

@test "logs: one day of retention and one group read as singular" {
  sed -i "s|^case \"\\\$\*\" in|[[ \"\$*\" == *logGroupName,* ]] \&\& { printf '/one\\\\t5\\\\t1\\\\t1767225600000\\\\tSTANDARD\\\\n'; exit 0; }\n[[ \"\$*\" == *storedBytes* ]] \&\& { echo 5; exit 0; }\n&|" "$BATS_TEST_TMPDIR/bin/aws"
  run src logs
  [[ "$output" == *'1 day'$'\t'* ]]
  load_libs log config menu
  fzx::menu_entries aws "$AWSM"
  [ "$(aws::summary aws:logs)" = "1 log group" ]
}

@test "logs: a very long name keeps its end and the columns line up" {
  local long
  long="/aws/$(printf 'x%.0s' {1..80})/end"
  sed -i "s|^case \"\\\$\*\" in|[[ \"\$*\" == *describe-log-groups* ]] \&\& { printf '$long\\\\t5\\\\t1\\\\t1767225600000\\\\tSTANDARD\\\\n'; exit 0; }\n&|" "$BATS_TEST_TMPDIR/bin/aws"
  run src logs
  [[ "$output" == "$long"$'\t'*…*'/end '* ]]
  [[ "$output" == *$'\t'"$long"$'\t'* ]]
}

@test "an empty list is a row naming the Region, with an empty id" {
  export STUB_AWS_EMPTY=1
  run src ec2
  [ "$status" -eq 0 ]
  [ "$output" = $'\tno EC2 instances in us-east-2\tno EC2 instances in us-east-2\t' ]
  FZX_TOGGLES=running run src ec2
  [[ "$output" == $'\tno running EC2 instances in us-east-2\t'* ]]
  run src logs
  [[ "$output" == $'\tno log groups in us-east-2\t'* ]]
}

@test "the Region comes from the environment first, without asking the CLI" {
  export STUB_AWS_EMPTY=1 AWS_REGION=eu-north-1
  run src logs
  [[ "$output" == *'in eu-north-1'* ]]
  ! grep -q 'configure get region' "$CALLS"
}

@test "a failed read is a row with the message, a hint for credentials, and a failing status" {
  export STUB_AWS_FAIL='An error occurred (ExpiredToken) when calling the DescribeInstances operation: expired'
  run bash -c "FZX_MODE=ec2 '$AWSM/source.sh' 2> /dev/null | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" == $'\t'"cannot list EC2 instances: An error occurred (ExpiredToken)"*'(aws login signs in)'$'\t'* ]]
  FZX_MODE=ec2 run "$AWSM/source.sh"
  [ "$status" -eq 1 ]
  export STUB_AWS_FAIL='You must specify a region. You can also configure your region'
  run bash -c "FZX_MODE=logs '$AWSM/source.sh' 2> /dev/null"
  [[ "$output" == *'aws configure set region REGION'* ]]
  export STUB_AWS_FAIL='An error occurred (AccessDenied) when calling it'
  run bash -c "FZX_MODE=logs '$AWSM/source.sh' 2> /dev/null"
  [[ "$output" == *AccessDenied* && "$output" != *'aws login'* ]]
}

@test "without the CLI the source says so" {
  rm "$BATS_TEST_TMPDIR/bin/aws"
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" FZX_MODE=ec2 run "$AWSM/source.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *'not installed'* ]]
}

@test "every request goes without a pager and with bounded waits" {
  run src ec2
  grep -q '^pager=\[\] --cli-connect-timeout 10 --cli-read-timeout 10 ec2 describe-instances' "$CALLS"
  FZX_AWS_TIMEOUT=3 run bash -c "FZX_AWS_TIMEOUT=3 FZX_MODE=logs '$AWSM/source.sh'"
  grep -q -- '--cli-connect-timeout 3 --cli-read-timeout 3 logs' "$CALLS"
}

@test "header row: the columns named over the rows, the sorted one marked, before a read that can fail" {
  FZX_SORT_HEADER=1 run bash -c "FZX_MODE=ec2 FZX_SORT_HEADER=1 '$AWSM/source.sh' | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" == $'\t'*NAME*ID*TYPE*STATE*IP* ]]
  [[ "${lines[1]}" == i-web$'\t'* ]]
  run bash -c "FZX_MODE=logs FZX_SORT_HEADER=1 '$AWSM/source.sh' | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" == $'\t'*NAME*SIZE*RETENTION* ]]
  export STUB_AWS_FAIL='An error occurred (Throttling)'
  run bash -c "FZX_MODE=logs FZX_SORT_HEADER=1 '$AWSM/source.sh' 2> /dev/null | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" == $'\t'*NAME* && "${lines[1]}" == *Throttling* ]]
}

@test "ec2 preview: from the row, no request; values AWS did not send are left out" {
  local details
  details="$(FZX_MODE=ec2 "$AWSM/source.sh" | awk -F'\t' '$1 == "i-web" { print $4 }')"
  : > "$CALLS"
  run prev ec2 i-web alpha "$details"
  [ "$status" -eq 0 ]
  [[ "$output" == *alpha*running* && "$output" == *'3.3.3.3'* && "$output" == *'web, ssh'* && "$output" == *'env=prod'* ]]
  [ ! -s "$CALLS" ]
  details="$(FZX_MODE=ec2 "$AWSM/source.sh" | awk -F'\t' '$1 == "i-anon" { print $4 }')"
  run prev ec2 i-anon i-anon "$details"
  [[ "$output" == *terminated* && "$output" == *us-east-2c* && "$output" != *None* && "$output" != *public* ]]
}

@test "logs preview: size and retention, then the newest stream's events, stamped" {
  export TZ=UTC
  run prev logs /app/api /app/api $'2500000\x1fNone\x1f1767225600000\x1fSTANDARD'
  [[ "$output" == */app/api* && "$output" == *'2500000 bytes'* && "$output" == *'never expires'* ]]
  [[ "$output" == *'latest events'*stream-1* ]]
  [[ "$output" == *'2026-01-01 00:00:00 hello'$'\t'world* ]]
  [[ "$output" == *$'\n''continued line'* ]]
  grep -q -- '--order-by LastEventTime --descending --limit 1 --no-paginate' "$CALLS"
  grep -q -- '--log-stream-name=stream-1 --no-start-from-head --limit 40' "$CALLS"
}

@test "text from elsewhere: colors stay, what moves the cursor or clears the screen goes" {
  run bash -c "source '$AWSM/source.sh'; printf 'a\\e[2J\\e[01;01H\\e[=3hb\\e[31mred\\e[0m\\ttab\\r\\e]0;title\\a\\ec\\ndone\\n' | aws::clean"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'ab\e[31mred\e[0m\ttab' ]
  [ "${lines[1]}" = done ]
}

@test "console output and log events reach the screen clean" {
  sed -i "s|^case \"\\\$\*\" in|[[ \"\$*\" == *get-console-output* ]] \&\& { printf 'boot\\\\033[2Jok\\\\n'; exit 0; }\n[[ \"\$*\" == *get-log-events* ]] \&\& { printf '1767225600000\\\\tev\\\\033[2Jent\\\\n'; exit 0; }\n&|" "$BATS_TEST_TMPDIR/bin/aws"
  run act ec2 logs i-web
  [[ "$output" == *bootok* && "$output" != *$'\e[2J'* ]]
  FZX_MODE=logs run "$AWSM/preview.sh" /app/api /app/api $'1\x1f1\x1f1767225600000\x1fSTANDARD'
  [[ "$output" == *event* && "$output" != *$'\e[2J'* ]]
}

@test "logs preview: a group with no streams says so" {
  run prev logs /app/idle /app/idle $'0\x1f30\x1f1767225600000\x1fSTANDARD'
  [[ "$output" == *'no events'* && "$output" == *'30 days'* ]]
  run prev logs /app/idle /app/idle $'0\x1f1\x1f1767225600000\x1fSTANDARD'
  [[ "$output" == *'1 day'* && "$output" != *'1 days'* ]]
  ! grep -q get-log-events "$CALLS"
}

@test "preview of a row without an id shows its message" {
  run prev ec2 "" "no EC2 instances in us-east-2" ""
  [ "$output" = "no EC2 instances in us-east-2" ]
  [ ! -s "$CALLS" ]
}

@test "console: each row's page in the Region, a log group's name encoded for the console" {
  act ec2 console i-web i-old
  grep -qxF 'https://us-east-2.console.aws.amazon.com/ec2/home?region=us-east-2#InstanceDetails:instanceId=i-web' "$OPENED"
  [ "$(wc -l < "$OPENED")" -eq 2 ]
  : > "$OPENED"
  act logs console '/aws/lambda/a#b'
  grep -qxF 'https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#logsV2:log-groups/log-group/$252Faws$252Flambda$252Fa$2523b' "$OPENED"
}

@test "logs action: an instance's console output; a group followed, several merged with their names" {
  run act ec2 logs i-web
  [[ "$output" == *'=== i-web'*'boot messages'* ]]
  grep -q 'ec2 get-console-output --instance-id i-web --latest' "$CALLS"
  run act logs logs /app/api
  [[ "$output" == *'tailed'*'logs tail /app/api --follow --format short --since 1h'* ]]
  run act logs logs /app/api /app/web
  [[ "$output" == *'following 2 log groups'* && "$output" == *'[/app/api]'*tailed* && "$output" == *'[/app/web]'*tailed* ]]
}

@test "inspect: the instance's JSON; a log group by its exact name, not as a prefix" {
  run act ec2 inspect i-web
  grep -q 'ec2 describe-instances --instance-ids i-web --output json' "$CALLS"
  run act logs inspect /app/api
  [[ "$output" == *'/app/api'* ]]
  grep -qF "logGroups[?logGroupName=='/app/api'] | [0]" "$CALLS"
}

@test "actions skip rows without an id and refuse unknown names" {
  run act ec2 console ""
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  [ ! -e "$OPENED" ]
  run act ec2 terminate i-web
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown action'* ]]
  [ ! -s "$CALLS" ]
}

@test "every row of the table parses, in every mode" {
  local m
  for m in ec2 logs ecs eks rds cache profiles volumes vpcs subnets sgs db-subnets cache-subnets; do
    run bash -c "'$FZX' -m aws:$m --dry-run 2>&1 > /dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "only EC2's start, stop and reboot change anything, each confirmed; nothing terminates or deletes" {
  run bash -c "grep -E '^action' '$AWSM/components.tsv' | grep -E 'confirm' | awk '{ print \$2 }' | sort | paste -sd ' '"
  [ "$output" = "reboot start stop" ]
  # no other CLI call in the module writes
  run bash -c "cat '$AWSM'/*.sh | grep -oE '(ec2|logs|ecs|eks|rds|elasticache|iam|sts) [a-z]+(-[a-z-]+)?' | grep -E ' (run|start|stop|terminate|reboot|create|delete|put|modify|update|tag|untag|remove|attach|detach)\b'"
  [ "$status" -eq 1 ]
  run grep -c 'terminate-instances\|delete-' "$AWSM/actions.sh"
  [ "$output" = 0 ]
}

@test "start, stop, reboot: the instances, ec2 only, and bound behind the confirmation" {
  act ec2 start i-web i-old
  grep -q 'ec2 start-instances --instance-ids i-web i-old' "$CALLS"
  act ec2 stop i-web
  grep -q 'ec2 stop-instances --instance-ids i-web' "$CALLS"
  act ec2 reboot i-web
  grep -q 'ec2 reboot-instances --instance-ids i-web' "$CALLS"
  : > "$CALLS"
  run act rds stop alpha
  [ "$status" -eq 2 ]
  [[ "$output" == *'stop does not apply to rds'* ]]
  [ ! -s "$CALLS" ]
  STUB_AWS_FAIL='An error occurred (UnauthorizedOperation)' FZX_MODE=ec2 run "$AWSM/actions.sh" stop i-web
  [ "$status" -ne 0 ]
  stub_fzf
  run "$FZX" -m aws
  [[ "$(fzf_bind ctrl-x)" == *'stop'* ]]
  [[ "$(fzf_bind alt-s)" == *'start'* ]]
  [[ "$(fzf_bind alt-R)" == *'reboot'* ]]
}

@test "table modes: rows in their fields, sorted by name, no None shown; a hidden one opens from the menu" {
  local m
  run src volumes
  [[ "${lines[0]}" == vol-2$'\t'*'- '*vol-2*available*gp3*us-east-2a$'\t'vol-2$'\t'available* ]]
  [[ "${lines[1]}" == vol-1$'\t'*root*vol-1*in-use*$'\t'root$'\t'* ]]
  for m in volumes vpcs subnets sgs db-subnets cache cache-subnets; do
    FZX_MODE=$m run "$AWSM/source.sh"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "${lines[0]}" | awk -F'\t' '{ print NF }')" -eq 4 ]
    [[ "$(printf '%s\n' "${lines[0]}" | cut -f2)" != *None* ]]
  done
  run bash -c "grep -E '^mode +(volumes|vpcs|subnets|sgs|db-subnets|cache-subnets) ' '$AWSM/components.tsv' | grep -vc hidden"
  [ "$output" = 0 ]
  stub_fzf
  run "$FZX" -m aws:vpcs
  [ "$status" -eq 0 ]
}

@test "table modes: an empty list and a failure read as the others do; a header row names the columns" {
  STUB_AWS_EMPTY=1 run src volumes
  [[ "$output" == $'\tno EBS volumes in us-east-2\t'* ]]
  STUB_AWS_FAIL='An error occurred (ExpiredToken)' FZX_MODE=sgs run "$AWSM/source.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'cannot list security groups'*'aws login'* ]]
  run bash -c "FZX_MODE=cache FZX_SORT_HEADER=1 '$AWSM/source.sh' | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" == $'\t'*NAME*STATUS*ENGINE*VERSION*NODE*NODES* ]]
}

@test "table previews: labels over the fields, the rule for all traffic named, no request" {
  local d
  d="$(FZX_MODE=sgs "$AWSM/source.sh" | cut -f4)"
  : > "$CALLS"
  run prev sgs sg-1 web "$d"
  [[ "$output" == *web* && "$output" == *sg-1* && "$output" == *'the web tier'* && "$output" == *tcp/443/443* && "$output" == *'all traffic'* ]]
  [ ! -s "$CALLS" ]
  d="$(FZX_MODE=volumes "$AWSM/source.sh" | awk -F'\t' '$1 == "vol-2" { print $4 }')"
  run prev volumes vol-2 vol-2 "$d"
  [[ "$output" == *available* && "$output" == *us-east-2a* && "$output" != *None* && "$output" != *attached* ]]
}

@test "table modes: console pages and the JSON; profiles have neither" {
  act volumes console vol-1
  act vpcs console vpc-1
  act subnets console subnet-1
  act sgs console sg-1
  grep -qF '#VolumeDetails:volumeId=vol-1' "$OPENED"
  grep -qF '/vpcconsole/home?region=us-east-2#VpcDetails:VpcId=vpc-1' "$OPENED"
  grep -qF '#SubnetDetails:subnetId=subnet-1' "$OPENED"
  grep -qF '#SecurityGroup:groupId=sg-1' "$OPENED"
  run act volumes inspect vol-1
  grep -q 'ec2 describe-volumes --volume-ids vol-1 --output json' "$CALLS"
  run act db-subnets inspect dbs
  grep -q 'rds describe-db-subnet-groups --db-subnet-group-name dbs --output json' "$CALLS"
  run act cache inspect c1
  grep -q 'elasticache describe-cache-clusters --cache-cluster-id c1 --show-cache-node-info' "$CALLS"
  run act profiles console work
  [ "$status" -eq 2 ]
}

@test "profiles: the environment first and marked; regions from the config file; choosing one marks it" {
  export AWS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
  printf '[default]\nregion = us-east-2\n[profile work]\nregion = eu-north-1\n' > "$AWS_CONFIG_FILE"
  run src profiles
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == -$'\t'*●*environment*$'\t'environment$'\t'* ]]
  [[ "${lines[1]}" == default$'\t'*default*profile*us-east-2$'\t'default$'\t'profile ]]
  [[ "${lines[2]}" == work$'\t'*work*eu-north-1$'\t'work$'\t'profile ]]
  [[ "${lines[2]}" != *●* ]]
  act profiles use work
  [ "$(cat "$FZX_STATE_DIR/aws/profile")" = "profile work" ]
  run src profiles
  [[ "${lines[2]}" == *●*work* && "${lines[0]}" != *●* ]]
  act profiles use -
  [ ! -e "$FZX_STATE_DIR/aws/profile" ]
}

@test "a chosen profile: every request names it, over the environment's keys; the Region is its own" {
  export AWS_CONFIG_FILE="$BATS_TEST_TMPDIR/config" STUB_AWS_EMPTY=1
  printf '[profile work]\nregion = eu-north-1\n' > "$AWS_CONFIG_FILE"
  mkdir -p "$FZX_STATE_DIR/aws"
  echo 'profile work' > "$FZX_STATE_DIR/aws/profile"
  run src logs
  [[ "$output" == *'no log groups in eu-north-1'* ]]
  grep -q -- '--profile work logs describe-log-groups' "$CALLS"
  ! grep -q 'configure get region' "$CALLS"
  AWS_REGION=us-east-2 run src logs
  [[ "$output" == *'in us-east-2'* ]]
}

@test "choosing a profile drops what the session read as the other one" {
  export FZX_SESSION_DIR="$BATS_TEST_TMPDIR/session"
  mkdir -p "$FZX_SESSION_DIR/data" "$FZX_SESSION_DIR/aws_preview"
  : > "$FZX_SESSION_DIR/data/ec2"
  : > "$FZX_SESSION_DIR/aws_preview/x"
  act profiles use work
  [ ! -e "$FZX_SESSION_DIR/data/ec2" ]
  [ ! -e "$FZX_SESSION_DIR/aws_preview" ]
}

@test "profile preview: asks as that profile without choosing it; the environment as itself" {
  export AWS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
  printf '[profile work]\nregion = eu-north-1\n' > "$AWS_CONFIG_FILE"
  run prev profiles work work profile
  [[ "$output" == *work* && "$output" == *eu-north-1* && "$output" == *'arn:aws:iam::1:user/me'* ]]
  grep -q -- '--profile work sts get-caller-identity' "$CALLS"
  [ ! -e "$FZX_STATE_DIR/aws/profile" ]
  : > "$CALLS"
  run prev profiles - environment environment
  [[ "$output" == *'what the CLI resolves'* && "$output" == *'arn:aws:iam'* ]]
  ! grep -q -- '--profile' "$CALLS"
}

@test "aws-vault: its profiles are listed, a chosen one runs through exec, login opens it; off hides them" {
  cat > "$BATS_TEST_TMPDIR/bin/aws-vault" << STUB
#!/usr/bin/env bash
printf 'vault %s vault_env=[%s]\n' "\$*" "\${AWS_VAULT-unset}" >> "$CALLS"
case "\$1" in
  list) echo vaulted ;;
  exec) shift 3; exec aws "\$@" ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/aws-vault"
  run src profiles
  [[ "$output" == *$'\t'vaulted$'\t'vault* ]]
  FZX_AWS_VAULT=off run bash -c "FZX_AWS_VAULT=off FZX_MODE=profiles '$AWSM/source.sh'"
  [[ "$output" != *vaulted* ]]
  act profiles use vaulted
  [ "$(cat "$FZX_STATE_DIR/aws/profile")" = "vault vaulted" ]
  : > "$CALLS"
  # started from inside another exec: aws-vault refuses to nest
  AWS_VAULT=outer run src vpcs
  [ "$status" -eq 0 ]
  grep -q 'vault exec vaulted -- aws .*vault_env=\[unset\]' "$CALLS"
  grep -q 'ec2 describe-vpcs' "$CALLS"
  ! grep -q -- '--profile' "$CALLS"
  act profiles login vaulted
  grep -q 'vault login vaulted' "$CALLS"
  run act profiles login -
  [ "$status" -eq 2 ]
}

@test "login without aws-vault says so" {
  run act profiles login work
  [ "$status" -eq 2 ]
  [[ "$output" == *'aws-vault is not installed'* ]]
}

@test "ecs: clusters by name with their counts; a whole row in four fields" {
  run src ecs
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == batch$'\t'*INACTIVE*$'\t'batch$'\t'INACTIVE* ]]
  [[ "${lines[1]}" == web$'\t'*web*ACTIVE*2*5*1*0$'\t'web$'\t'ACTIVE* ]]
  [ "$(printf '%s\n' "${lines[1]}" | awk -F'\t' '{ print NF }')" -eq 4 ]
  grep -q 'ecs describe-clusters --clusters arn:aws:ecs:r:1:cluster/web arn:aws:ecs:r:1:cluster/batch' "$CALLS"
}

@test "ecs: clusters are described 100 at a time" {
  sed -i "s|^case \"\\\$\*\" in|[[ \"\$*\" == *'ecs list-clusters'* ]] \&\& { for ((i = 1; i <= 101; i++)); do printf 'c%s\\\\t' \"\\\$i\"; done; echo; exit 0; }\n&|" "$BATS_TEST_TMPDIR/bin/aws"
  run src ecs
  [ "$(grep -c 'ecs describe-clusters' "$CALLS")" -eq 2 ]
}

@test "eks: one request per cluster, a creating one without its missing values; one that fails is a row" {
  run src eks
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == dev$'\t'*CREATING*' - '*'-'$'\t'dev$'\t'* ]]
  [[ "$(printf '%s\n' "${lines[0]}" | cut -f2)" != *None* ]]
  [[ "${lines[1]}" == prod$'\t'*ACTIVE*1.33*https://prod.eks$'\t'prod$'\t'* ]]
  [ "$(grep -c 'eks describe-cluster' "$CALLS")" -eq 2 ]
  STUB_EKS_FAIL=dev FZX_MODE=eks run "$AWSM/source.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *prod* && "$output" == *'cannot list EKS cluster'*AccessDenied* ]]
}

@test "rds: available first, or by name; endpoint shown, a dash for one still being created" {
  run src rds
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == alpha$'\t'*'mysql 8.0'*db.t3.small*available*alpha.rds$'\t'alpha$'\t'* ]]
  [[ "${lines[1]}" == new$'\t'*creating*' -'$'\t'new$'\t'* ]]
  [[ "${lines[2]}" == zeta$'\t'*stopped* ]]
  FZX_SORT=name run src rds
  [[ "${lines[0]}" == alpha$'\t'* && "${lines[1]}" == new$'\t'* && "${lines[2]}" == zeta$'\t'* ]]
}

@test "ecs, eks, rds: an empty list names the Region; a header row comes first" {
  export STUB_AWS_EMPTY=1
  run src ecs
  [[ "$output" == $'\tno ECS clusters in us-east-2\t'* ]]
  run src eks
  [[ "$output" == $'\tno EKS clusters in us-east-2\t'* ]]
  run src rds
  [[ "$output" == $'\tno RDS instances in us-east-2\t'* ]]
  run bash -c "FZX_MODE=rds FZX_SORT_HEADER=1 '$AWSM/source.sh' | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" == $'\t'*NAME*ENGINE*CLASS*STATE*ENDPOINT* ]]
  run bash -c "FZX_MODE=ecs FZX_SORT_HEADER=1 '$AWSM/source.sh' | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" == $'\t'*NAME*STATUS*SERVICES*RUNNING*PENDING*INSTANCES* ]]
}

@test "ecs preview: the counts, then services; the first 10 and how many more; none" {
  run prev ecs web web $'ACTIVE\x1f2\x1f5\x1f1\x1f0\x1farn:c'
  [[ "$output" == *web*ACTIVE* && "$output" == *'5 tasks'* && "$output" == *services* && "$output" == *api*ACTIVE*'2/3 tasks'* ]]
  run prev ecs many many $'ACTIVE\x1f12\x1f0\x1f0\x1f0\x1farn:c'
  [[ "$output" == *'and 2 more'* ]]
  grep -q 'ecs describe-services --cluster many --services arn:s1 .* arn:s10 --output' "$CALLS"
  ! grep -q 'arn:s11' <(grep 'describe-services' "$CALLS")
  run prev ecs empty empty $'ACTIVE\x1f0\x1f0\x1f0\x1f0\x1farn:c'
  [[ "$output" == *'no services'* ]]
}

@test "eks preview: the details, then node groups; values AWS did not send left out" {
  run prev eks prod prod $'ACTIVE\x1f1.33\x1feks.1\x1fhttps://prod.eks\x1ft0\x1frole\x1fvpc-1\x1fa, b'
  [[ "$output" == *prod*ACTIVE* && "$output" == *https://prod.eks* && "$output" == *'a, b'* && "$output" == *'node groups'*workers*spot* ]]
  run prev eks dev dev $'CREATING\x1fNone\x1fNone\x1fNone\x1ft1\x1frole\x1fNone\x1f'
  [[ "$output" == *'no node groups'* && "$output" != *None* ]]
}

@test "rds preview: from the row, no request; one being created shows only what AWS sent" {
  : > "$CALLS"
  run prev rds alpha alpha $'available\x1fmysql\x1f8.0\x1fdb.t3.small\x1fus-east-2b\x1falpha.rds\x1f3306\x1fTrue\x1f50\x1fgp3\x1fFalse\x1fTrue\x1ft1\x1faurora-1\x1fvpc-1'
  [[ "$output" == *'mysql 8.0'* && "$output" == *'alpha.rds:3306'* && "$output" == *'50 GiB gp3'* && "$output" == *aurora-1* ]]
  [ ! -s "$CALLS" ]
  run prev rds new new $'creating\x1fpostgres\x1fNone\x1fdb.t3.micro\x1fNone\x1fNone\x1fNone\x1fFalse\x1fNone\x1fNone\x1fFalse\x1fTrue\x1fNone\x1fNone\x1fNone'
  [[ "$output" == *creating* && "$output" == *postgres* && "$output" != *None* && "$output" != *GiB* && "$output" != *endpoint* ]]
}

@test "preview cache: a second look asks nothing, it expires, and standalone there is none" {
  local details=$'1500\x1f7\x1f1767225600000\x1fSTANDARD' first
  export FZX_SESSION_DIR="$BATS_TEST_TMPDIR/session"
  mkdir -p "$FZX_SESSION_DIR"
  first="$(prev logs /app/web /app/web "$details")"
  [[ "$first" == *'latest events'* ]]
  : > "$CALLS"
  [ "$(prev logs /app/web /app/web "$details")" = "$first" ]
  [ ! -s "$CALLS" ]
  # another group has its own
  run prev logs /app/api /app/api "$details"
  grep -q 'log-group-name=/app/api' "$CALLS"
  : > "$CALLS"
  # older than FZX_AWS_PREVIEW_TTL
  find "$FZX_SESSION_DIR/aws_preview" -type f -exec touch -d '2 minutes ago' {} +
  run prev logs /app/web /app/web "$details"
  grep -q 'describe-log-streams' "$CALLS"
  : > "$CALLS"
  FZX_AWS_PREVIEW_TTL=0 run prev logs /app/web /app/web "$details"
  grep -q 'describe-log-streams' "$CALLS"
  unset FZX_SESSION_DIR
  : > "$CALLS"
  run prev logs /app/web /app/web "$details"
  grep -q 'describe-log-streams' "$CALLS"
}

@test "preview cache: a failure is shown and not kept; reading the list again empties it" {
  local details=$'1500\x1f7\x1f1767225600000\x1fSTANDARD'
  export FZX_SESSION_DIR="$BATS_TEST_TMPDIR/session"
  mkdir -p "$FZX_SESSION_DIR"
  STUB_AWS_FAIL='An error occurred (Throttling)' run prev logs /app/web /app/web "$details"
  [[ "$output" == *Throttling* ]]
  [ -z "$(find "$FZX_SESSION_DIR/aws_preview" -type f)" ]
  run prev logs /app/web /app/web "$details"
  [[ "$output" == *'latest events'* ]]
  [ -n "$(find "$FZX_SESSION_DIR/aws_preview" -type f)" ]
  run src logs
  [ ! -e "$FZX_SESSION_DIR/aws_preview" ]
}

@test "ecs, eks, rds: console pages, the JSON; logs does not apply" {
  act ecs console web
  act eks console prod
  act rds console alpha
  grep -qxF 'https://us-east-2.console.aws.amazon.com/ecs/v2/clusters/web?region=us-east-2' "$OPENED"
  grep -qxF 'https://us-east-2.console.aws.amazon.com/eks/home?region=us-east-2#/clusters/prod' "$OPENED"
  grep -qxF 'https://us-east-2.console.aws.amazon.com/rds/home?region=us-east-2#database:id=alpha;is-cluster=false' "$OPENED"
  run act ecs inspect web
  grep -q 'ecs describe-clusters --clusters web --output json' "$CALLS"
  run act eks inspect prod
  grep -q 'eks describe-cluster --name prod --output json' "$CALLS"
  run act rds inspect alpha
  grep -q 'rds describe-db-instances --db-instance-identifier alpha --output json' "$CALLS"
  : > "$CALLS"
  run act rds logs alpha
  [ "$status" -eq 2 ]
  [[ "$output" == *'logs does not apply to rds'* ]]
  [ ! -s "$CALLS" ]
}

@test "under fzx: mode, toggle and action keys are bound; ctrl-y copies the name; the id is printed" {
  stub_fzf
  run "$FZX" -m aws
  [ "$status" -eq 0 ]
  [[ "$(fzf_bind alt-a)" == *'_cb toggle running'* ]]
  [[ "$(fzf_bind alt-O)" == *'_cb action console'* ]]
  [[ "$(fzf_bind ctrl-l)" == *'_cb action logs'* ]]
  [[ "$(fzf_bind alt-i)" == *'_cb action inspect'* ]]
  [[ "$(fzf_bind ctrl-y)" == *"_cb notify copy {+3}"* ]]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=1 "* ]]
}

@test "menu: listed where the CLI is, with no request; summaries count; a failed count says nothing" {
  load_libs log config menu
  fzx::menu_entries aws "$AWSM"
  [[ " ${FZX_ENTRY_TARGETS[*]} " == *" aws "* && " ${FZX_ENTRY_TARGETS[*]} " == *" aws:logs "* ]]
  aws::applicable aws
  [ ! -s "$CALLS" ]
  [ "$(aws::summary aws)" = "2 running, 1 stopped" ]
  [ "$(aws::summary aws:logs)" = "3 log groups" ]
  [[ " ${FZX_ENTRY_TARGETS[*]} " == *" aws:ecs "* && " ${FZX_ENTRY_TARGETS[*]} " == *" aws:eks "* && " ${FZX_ENTRY_TARGETS[*]} " == *" aws:rds "* ]]
  [ "$(aws::summary aws:ecs)" = "2 clusters" ]
  [ "$(aws::summary aws:eks)" = "2 clusters" ]
  [ "$(aws::summary aws:rds)" = "1 available of 2" ]
  [ "$(aws::summary aws:volumes)" = "2 EBS volumes" ]
  sed -i "s|printf 'vol-1\\\\tvol-2\\\\n'|echo vol-1|" "$BATS_TEST_TMPDIR/bin/aws"
  [ "$(aws::summary aws:volumes)" = "1 EBS volume" ]
  [ "$(aws::summary aws:profiles)" = "using the environment" ]
  [ -z "$(aws::summary_key)" ]
  mkdir -p "$FZX_STATE_DIR/aws"
  echo 'profile work' > "$FZX_STATE_DIR/aws/profile"
  [ "$(aws::summary_key)" = "profile work" ]
  rm "$FZX_STATE_DIR/aws/profile"
  STUB_AWS_EMPTY=1 run aws::summary aws
  [ "$output" = "0 running, 0 stopped" ]
  STUB_AWS_FAIL=denied run aws::summary aws
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm "$BATS_TEST_TMPDIR/bin/aws"
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run aws::applicable aws
  [ "$status" -ne 0 ]
}
