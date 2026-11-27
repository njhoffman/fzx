#!/usr/bin/env bash
# gpg preview: the key as gpg lists it (user ids, subkeys, fingerprint; no network), and whether its secret
# key is here

# gpg::preview <fingerprint>
gpg::preview() {
  local fpr="${1:-}"
  [[ -n "$fpr" ]] || return 0
  # shellcheck disable=SC2119  # no fields: the whole text
  command gpg --list-keys --keyid-format long --with-fingerprint --with-subkey-fingerprint -- "$fpr" 2> /dev/null |
    fzx::glyphs_plain
  if command gpg --list-secret-keys --with-colons -- "$fpr" > /dev/null 2>&1; then
    printf 'the secret key is here\n'
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" gpg
  gpg::preview "$@"
}
