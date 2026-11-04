#!/usr/bin/env bash
# aws: EC2 instances, log groups, ECS, EKS and ElastiCache clusters, RDS instances and the network around them,
# as the AWS CLI resolves them or as the profile chosen here. Only EC2's start, stop and reboot change anything.
# `fzx -m aws[:MODE]`. Enter prints the ids.

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
