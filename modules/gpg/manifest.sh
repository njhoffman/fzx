#!/usr/bin/env bash
# gpg menu entries, where gpg has a keyring

gpg::manifest() {
  fzx::entry gpg "GPG keys"
  fzx::entry gpg:secret "GPG keys you hold the secret of"
}

gpg::applicable() {
  command -v gpg > /dev/null || return 1
  case "$1" in
    gpg:secret) [[ -n "$(command gpg --list-secret-keys --with-colons 2> /dev/null | head -n 1)" ]] ;;
    *) [[ -n "$(command gpg --list-keys --with-colons 2> /dev/null | head -n 1)" ]] ;;
  esac
}

# gpg::summary <target>: how many keys (secret ones for gpg:secret)
gpg::summary() {
  local kind=pub list=--list-keys
  [[ "$1" == gpg:secret ]] && kind=sec list=--list-secret-keys
  command gpg "$list" --with-colons 2> /dev/null | awk -F: -v k="$kind" "$FZX_AWK_PLURAL"'
    $1 == k { n++ } END { print plural(n, "key") }'
}

# the summaries are cached once for every directory: they describe the keyring, not the directory
gpg::summary_global() { :; }
