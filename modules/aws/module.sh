#!/usr/bin/env bash
# aws: EC2 instances, CloudWatch log groups, ECS and EKS clusters and RDS instances, read-only, with whatever credentials and Region the AWS CLI
# resolves. `fzx -m aws[:logs|:ecs|:eks|:rds]`. Enter prints the ids (instance id, log group or cluster name).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

aws::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{3}' '{4}')"
    "--preview-window=down,55%,nohidden"
  )
  # ctrl-y: what the row is called, not the id the commands take
  # shellcheck disable=SC2034  # read by lib/actions.sh
  FZX_ACTION_ARGS_FOR['copy']='{+3}'
}

fzx::module_main "$@"
