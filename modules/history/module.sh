#!/usr/bin/env bash
# history: zsh-histdb's commands, one row per command, newest first. `fzx -m history[:global|:host|
# :directory|:session]` (global, every host, by default). Enter prints the command; alt-enter prints it and exits 10 (the zsh widget then runs it).
# The zsh widget (shell/fzx.zsh, ctrl-r) passes the shell's histdb session as FZX_HISTDB_SESSION.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

history::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2..
    --nth=2
    --tabstop=1
    --scheme=history
    --preview "$(fzx::cb preview '{1}')"
    "--preview-window=down,40%,nohidden"
  )
  # a command over several lines is an item over several lines (lib: --read0, items counted by NUL)
  # shellcheck disable=SC2034  # read by lib/opts.sh
  [[ "${FZX_HISTORY_MULTILINE:-1}" == 1 ]] && FZX_READ0=1
  # module args are the starting query (the zsh widget passes what is typed on the command line)
  ((${#FZX_ARGS[@]})) && FZX_OPTS+=("--query=${FZX_ARGS[*]}")
  return 0
}

fzx::module_main "$@"
