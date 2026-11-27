#!/usr/bin/env bats
# the gpg module against a stub gpg (calls logged) that serves a fixture keyring in --with-colons form

load test_helper

GPGM="$(readlink -f "$BATS_TEST_DIRNAME/../modules/gpg")"

setup() {
  setup_fzx
  # the dates are printed in local time: UTC, so they read the same everywhere
  export NO_COLOR=1 CALLS="$BATS_TEST_TMPDIR/calls" TZ=UTC
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # four keys: mine (ultimate, ed25519, a secret key here), a full one that expires, an expired one, a revoked one
  cat > "$BATS_TEST_TMPDIR/pub" << 'EOF'
tru::1:1758223993:0:3:1:5
pub:u:255:22:AAAA000000000001:1758000000:::u:::scESC:::::ed25519:::0:
fpr:::::::::FPR1:
uid:u::::1758000000::H1::Me Myself <me@example.org>::::::::::0:
sub:u:255:18:AAAA000000000002:1758000000::::::e:::::cv25519::
fpr:::::::::FPR1SUB:
pub:f:4096:1:BBBB000000000001:1600000000:2000000000::-:::scESC::::::23::0:
fpr:::::::::FPR2:
uid:f::::1600000000::H2::Alice <alice@example.org>::::::::::0:
uid:f::::1600000000::H3::Alice Work <alice@work.example>::::::::::0:
pub:e:2048:1:CCCC000000000001:1300000000:1400000000::-:::sc::::::23::0:
fpr:::::::::FPR3:
uid:e::::1300000000::H4::Old Bob <bob@example.org>::::::::::0:
pub:r:3072:17:DDDD000000000001:1500000000:::-:::sc::::::23::0:
fpr:::::::::FPR4:
uid:r::::1500000000::H5::carol::::::::::0:
EOF
  printf 'sec:u:255:22:AAAA000000000001:1758000000::::::::::\nfpr:::::::::FPR1:\n' > "$BATS_TEST_TMPDIR/sec"
  cat > "$BATS_TEST_TMPDIR/bin/gpg" << 'STUB'
#!/usr/bin/env bash
printf 'gpg %s\n' "$*" >> "$CALLS"
case "$*" in
  "--list-keys --with-colons") cat "$BATS_TEST_TMPDIR/pub" ;;
  "--list-secret-keys --with-colons") cat "$BATS_TEST_TMPDIR/sec" ;;
  "--list-secret-keys --with-colons -- FPR1") cat "$BATS_TEST_TMPDIR/sec" ;;
  "--list-secret-keys --with-colons -- "*) exit 2 ;;
  "--armor --export -- "*) printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\n%s\n' "${*: -1}" ;;
  "--list-keys --keyid-format long "*) printf 'pub   rsa4096/%s\n' "${*: -1}" ;;
esac
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/gpg"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

src() { FZX_MODE="${1:-keys}" "$GPGM/source.sh"; }

@test "keys: every key by its primary user id, with trust, algorithm, created and expires; secret marked" {
  run src
  [ "${#lines[@]}" -eq 4 ]
  [ "$(printf '%s\n' "$output" | cut -f1 | paste -sd' ')" = "FPR2 FPR4 FPR1 FPR3" ]
  [[ "${lines[0]}" == $'FPR2\t● Alice <alice@example.org> '*"rsa4096   2020-09-13 2033-05-18"* ]]
  [[ "${lines[2]}" == $'FPR1\t★ Me Myself <me@example.org> '*"ed25519   2025-09-16 never      secret" ]]
  [[ "${lines[3]}" == $'FPR3\t✗ Old Bob'*"(expired)"* ]]
  [[ "${lines[1]}" == $'FPR4\t✗ carol '*"dsa3072"*"revoked"* ]]
}

@test "secret: only the keys whose secret key is here; sort created: newest first; a header row" {
  run src secret
  [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == FPR1$'\t'* ]]
  FZX_SORT=created run src
  [ "$(printf '%s\n' "$output" | cut -f1 | paste -sd' ')" = "FPR1 FPR2 FPR4 FPR3" ]
  FZX_SORT_HEADER=1 run src
  [[ "${lines[0]}" == $'\t'*"NAME"*"KEY"*"CREATED"*"EXPIRES"* ]]
}

@test "export copies the armored public keys; delete refuses a key whose secret key is here" {
  "$GPGM/actions.sh" export FPR2
  [[ "$(cat "$BATS_TEST_TMPDIR/clipboard")" == *"BEGIN PGP PUBLIC KEY BLOCK"*FPR2* ]]
  run "$GPGM/actions.sh" delete FPR1 FPR2
  [ "$status" -eq 1 ]
  [[ "$output" == *"FPR1 has its secret key here"* ]]
  grep -qx 'gpg --batch --yes --delete-keys -- FPR2' "$CALLS"
  run grep -c -- '--delete-keys -- FPR1' "$CALLS"
  [ "$output" = 0 ]
}

@test "trust, edit and refresh run gpg on the terminal" {
  "$GPGM/actions.sh" trust FPR2
  "$GPGM/actions.sh" edit FPR3
  "$GPGM/actions.sh" refresh FPR2 FPR3
  grep -qx 'gpg --edit-key FPR2 trust quit' "$CALLS"
  grep -qx 'gpg --edit-key FPR3' "$CALLS"
  grep -qx 'gpg --refresh-keys -- FPR2 FPR3' "$CALLS"
}

@test "preview: the key's listing, and whether its secret key is here" {
  run "$GPGM/preview.sh" FPR1
  [[ "$output" == *"pub   rsa4096/FPR1"* && "$output" == *"the secret key is here"* ]]
  run "$GPGM/preview.sh" FPR2
  [[ "$output" != *"secret key"* ]]
}

@test "under fzx: ctrl-y copies the fingerprints, alt-x asks before deleting" {
  stub_fzf
  run "$FZX" -m gpg
  [[ "$(fzf_bind ctrl-y)" == *"copy"* ]]
  [[ "$(fzf_bind alt-x)" == *"_cb action delete {+1}"* ]]
}

@test "menu: applicable with a keyring (secret with a secret key); the counts" {
  load_libs log
  source "$GPGM/manifest.sh" || :
  gpg::applicable gpg
  gpg::applicable gpg:secret
  [ "$(gpg::summary gpg)" = "4 keys" ]
  [ "$(gpg::summary gpg:secret)" = "1 key" ]
  : > "$BATS_TEST_TMPDIR/sec"
  run gpg::applicable gpg:secret
  [ "$status" -ne 0 ]
}

@test "components: every row has its five fields" {
  local bad
  bad="$(grep -v '^#' "$GPGM/components.tsv" | awk -F'  +|\t' 'NF != 5')"
  [ -z "$bad" ] || { printf 'rows without five fields:\n%s\n' "$bad"; return 1; }
}
