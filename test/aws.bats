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
  run bash -c "cat '$AWSM'/*.sh | grep -oE '(ec2|logs) [a-z]+(-[a-z-]+)?' | grep -E ' (run|start|stop|terminate|reboot|create|delete|put|modify|update|tag|untag)\b'"
  [ "$status" -eq 1 ]
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
  STUB_AWS_EMPTY=1 run aws::summary aws
  [ "$output" = "0 running, 0 stopped" ]
  STUB_AWS_FAIL=denied run aws::summary aws
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm "$BATS_TEST_TMPDIR/bin/aws"
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run aws::applicable aws
  [ "$status" -ne 0 ]
}
