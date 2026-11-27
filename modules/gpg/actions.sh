#!/usr/bin/env bash
# gpg actions on the selected fingerprints: export (the armored public keys to the clipboard), trust and edit
# (gpg --edit-key on the terminal), delete (public keys only), refresh (from the keyserver)

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# gpg::_has_secret <fingerprint>: the secret key is here
gpg::_has_secret() { command gpg --list-secret-keys --with-colons -- "$1" > /dev/null 2>&1; }

# gpg::action <name> <fingerprints...>
gpg::action() {
  local action="${1:-}" fpr rc=0
  shift
  (($#)) || return 0
  case "$action" in
    export)
      # public keys only: a secret key never goes to the clipboard from here
      fzx::require builtin
      command gpg --armor --export -- "$@" | fzx::clip
      ;;
    trust) command gpg --edit-key "$1" trust quit ;;
    edit) command gpg --edit-key "$1" ;;
    delete)
      for fpr; do
        if gpg::_has_secret "$fpr"; then
          printf 'gpg: %s has its secret key here; delete it by hand (gpg --delete-secret-and-public-key)\n' "$fpr" >&2
          rc=1
          continue
        fi
        command gpg --batch --yes --delete-keys -- "$fpr" || rc=1
      done
      ;;
    refresh) command gpg --refresh-keys -- "$@" || rc=$? ;;
    *)
      printf 'gpg: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" gpg
  gpg::action "$@"
}
