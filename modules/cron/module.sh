#!/usr/bin/env bash
# cron: crontab entries with their next run, anacron's jobs and the run-parts scripts.
# `fzx -m cron[:user|:system|:scripts]`. ctrl-e edits, alt-d disables or enables an entry of your crontab,
# alt-enter runs one now. Enter prints the commands (scripts: their paths).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
cron::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,50%,wrap,nohidden"
  )
  FZX_ACTION_ARGS_FOR['copy']='{+2}'
}

fzx::module_main "$@"
