#!/usr/bin/env bash
# systemd: services of the user and system managers. `fzx -m systemd[:system|:failed]`.
# Enter prints unit names.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

systemd::modes() {
  FZX_MODES=(user system failed)
}

systemd::opts() {
  local action hints
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=2
    --preview "$(fzx::cb preview {1})"
    --preview-window=down,50%,nowrap,nohidden
  )
  for action in start stop restart enable disable; do
    fzx::bind "${FZX_KEYS[systemd.$action]}" "execute($(fzx::cb action "$action" {+1}))+reload($(fzx::cb source))" "$action"
  done
  fzx::bind "${FZX_KEYS[systemd.journal]}" "execute($(fzx::cb action journal {1}))" journal
  fzx::bind "${FZX_KEYS[systemd.edit]}" "execute($(fzx::cb action edit {1}))+reload($(fzx::cb source))" edit
  # the header lists the module's keys from what was just bound, so it cannot drift from the bindings
  fzx::key_hints hints
  FZX_OPTS+=("--header=$hints")
}

fzx::module_main "$@"
