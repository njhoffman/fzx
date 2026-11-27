#!/usr/bin/env bash
# gpg source: "fingerprint<TAB>display" a key from `gpg --list-keys --with-colons`. Modes from $FZX_MODE:
# keys (every public key), secret (the ones whose secret key is here). Sort from $FZX_SORT: name (the primary
# user id) or created (newest first).

# gpg::keys: "fingerprint US validity US algo US created US expires US uid US secret" a primary key, fields split
# on \x1f (US: tabs, being whitespace to read, would merge an empty expires with its neighbours); validity
# is gpg's (u ultimate, f full, m marginal, e expired, r revoked, ...), algo like rsa4096 or ed25519, the
# dates as epochs (expires empty for never), secret 1 when the secret key is here
gpg::keys() {
  local sec
  sec="$(command gpg --list-secret-keys --with-colons 2> /dev/null | awk -F: '$1 == "sec" { want = 1; next } want && $1 == "fpr" { print $10; want = 0 }')"
  command gpg --list-keys --with-colons 2> /dev/null | awk -F: -v sec="$sec" '
    BEGIN { n = split(sec, s, "\n"); for (i = 1; i <= n; i++) secret[s[i]] = 1 }
    function algo(a, len, curve) {
      if (curve != "") return curve
      if (a == 1 || a == 2 || a == 3) return "rsa" len
      if (a == 17) return "dsa" len
      if (a == 16 || a == 20) return "elg" len
      return "algo" a "-" len
    }
    function flush() { if (fpr != "") printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\n", fpr, val, alg, created, expires, uid, (fpr in secret) }
    $1 == "pub" { flush(); val = $2; alg = algo($4, $3, $17); created = $6; expires = $7; fpr = ""; uid = ""; want = 1; next }
    $1 == "fpr" && want { fpr = $10; want = 0; next }
    $1 == "uid" && uid == "" { uid = $10 }
    END { flush() }'
}

# gpg::source
gpg::source() {
  local fpr val alg created expires uid secret mark c day exp
  local dim=$'\e['"${FZX_COLORS[gpg_dim]:-38;5;244}m" ok=$'\e['"${FZX_COLORS[gpg_trusted]:-38;5;114}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && dim="" ok="" r=""
  fzx::require header
  fzx::header_print 1 "$([[ "${FZX_SORT:-name}" == created ]] && echo CREATED || echo NAME)" "" 1 0 NAME 48 0 KEY 9 0 \
    CREATED 10 0 EXPIRES 10 0 "" 0 0
  # user ids are other people's text: fzx::glyphs_plain (whole lines: the fingerprints have none)
  # shellcheck disable=SC2119
  gpg::keys | fzx::glyphs_plain | awk -F'\037' -v mode="${FZX_MODE:-keys}" 'mode != "secret" || $7 == 1' |
    if [[ "${FZX_SORT:-name}" == created ]]; then LC_ALL=C sort -t$'\x1f' -k4,4nr; else sort -t$'\x1f' -k6,6f; fi |
    while IFS=$'\x1f' read -r fpr val alg created expires uid secret; do
      case "$val" in
        u) mark="★" c="$ok" ;;
        f) mark="●" c="$ok" ;;
        m) mark="◐" c="" ;;
        e | r | i | d) mark="✗" c="$dim" ;;
        *) mark="○" c="" ;;
      esac
      printf -v day '%(%F)T' "$created"
      exp="never"
      [[ -n "$expires" ]] && printf -v exp '%(%F)T' "$expires"
      [[ "$val" == e ]] && exp+=" (expired)"
      [[ "$val" == r ]] && exp="revoked"
      printf '%s\t%s%s%s %s%-48.48s%s %-9s %s %-10s %s%s\n' "$fpr" "$c" "$mark" "$r" "$c" "$uid" "$r" "$alg" "$day" "$exp" \
        "$( ((secret)) && printf '%ssecret%s' "$ok" "$r")" ""
    done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" gpg
  gpg::source "$@"
}
