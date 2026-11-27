#!/usr/bin/env bash
# gpg: the keys in your keyring (`fzx -m gpg[:secret]`), with their trust, user id, algorithm and dates.
# ctrl-y copies fingerprints, alt-e the armored public keys, alt-t sets the trust, ctrl-e runs gpg --edit-key,
# alt-x deletes public keys (asks first; a key whose secret key is here is refused).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

gpg::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}')"
  )
}

fzx::module_main "$@"
