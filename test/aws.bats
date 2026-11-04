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
  sed -i "s|^case \"\\\$\*\" in|[[ \"\$*\" == *logGroupName,* ]] \&\& { printf '/one\\\\t5\\\\t1\\\\t1767225600000\\\\tSTANDARD\\\\n'; exit 0; }\n[[ \"\$*\" == *storedBytes* ]] \&\& { echo 5; exit 0; }\n\&|" "$BATS_TEST_TMPDIR/bin/aws"
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

@test "read-only: no action row or CLI call in the module changes a resource" {
  run grep -E '^action' "$AWSM/components.tsv"
  [ "${#lines[@]}" -eq 3 ]
  # every aws subcommand the module runs reads
  run bash -c "cat '$AWSM'/*.sh | grep -oE '(ec2|logs|ecs|eks|rds) [a-z]+(-[a-z-]+)?' | grep -E ' (run|start|stop|terminate|reboot|create|delete|put|modify|update|tag|untag)\b'"
  [ "$status" -eq 1 ]
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
  sed -i "s|^case \"\\\$\*\" in|[[ \"\$*\" == *'ecs list-clusters'* ]] \&\& { for ((i = 1; i <= 101; i++)); do printf 'c%s\\\\t' \"\\\$i\"; done; echo; exit 0; }\n\&|" "$BATS_TEST_TMPDIR/bin/aws"
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
  STUB_AWS_EMPTY=1 run aws::summary aws
  [ "$output" = "0 running, 0 stopped" ]
  STUB_AWS_FAIL=denied run aws::summary aws
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm "$BATS_TEST_TMPDIR/bin/aws"
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run aws::applicable aws
  [ "$status" -ne 0 ]
}
