#!/usr/bin/env bash
# ssh: hosts from ~/.ssh/config, known_hosts and zsh-histdb's ssh, scp, rsync, mosh and sftp commands,
# last used first. `fzx -m ssh`. Enter connects in a new tmux window (alt-enter here), alt-s sends a path
# there, alt-F fetches one, alt-i installs your key, ctrl-e edits ~/.ssh/config at the host.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

ssh::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{2}')"
  )
}

fzx::module_main "$@"
