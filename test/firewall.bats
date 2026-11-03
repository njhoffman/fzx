#!/usr/bin/env bats
# the firewall module against a stub ufw and sudo (sudo -n succeeds unless $BATS_TEST_TMPDIR/nosudo
# exists), fixture profiles and ufw.conf

load test_helper

FW="$(readlink -f "$BATS_TEST_DIRNAME/../modules/firewall")"

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS" "$BATS_TEST_TMPDIR/apps"
  cat > "$STUBS/sudo" << 'STUB'
#!/usr/bin/env bash
if [[ "$1" == -n ]]; then
  [[ -f "$BATS_TEST_TMPDIR/nosudo" ]] && { echo "sudo: a password is required" >&2; exit 1; }
  shift
fi
echo "sudo $*" >> "$BATS_TEST_TMPDIR/calls"
"$@"
STUB
  cat > "$STUBS/ufw" << 'STUB'
#!/usr/bin/env bash
# ufw off ($BATS_TEST_TMPDIR/inactive): status lists nothing, show added the rules
if [[ -f "$BATS_TEST_TMPDIR/inactive" ]]; then
  case "$*" in
    status*) echo "Status: inactive"; exit 0 ;;
    "show added") printf "Added user rules (see 'ufw status' for running firewall):\nufw allow 22/tcp\nufw limit 2222/tcp comment 'ssh'\nufw allow OpenSSH\nufw deny 'Postfix SMTPS'\n"; exit 0 ;;
  esac
fi
case "$*" in
  "status verbose") printf 'Status: active\nLogging: on (low)\nDefault: deny (incoming), allow (outgoing), disabled (routed)\nNew profiles: skip\n\nTo                         Action      From\n--                         ------      ----\n22/tcp                     ALLOW IN    Anywhere\n' ;;
  "status numbered") cat "$BATS_TEST_TMPDIR/numbered" ;;
  "status") sed -E 's/^\[ *[0-9]+\] //' "$BATS_TEST_TMPDIR/numbered" ;;
  --dry-run*bogus*) echo "ERROR: Bad port" >&2; echo "ufw $*" >> "$BATS_TEST_TMPDIR/calls"; exit 1 ;;
  *) echo "ufw $*" >> "$BATS_TEST_TMPDIR/calls" ;;
esac
STUB
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
  cat > "$BATS_TEST_TMPDIR/numbered" << 'OUT'
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     LIMIT IN    Anywhere                   # ssh
[ 2] OpenSSH                    ALLOW IN    192.168.1.0/24
[ 3] 8080                       DENY OUT    Anywhere on eth0
[ 4] 22/tcp (v6)                LIMIT IN    Anywhere (v6)              # ssh
[10] CUPS                       REJECT IN   Anywhere
OUT
  printf '[OpenSSH]\ntitle=Secure shell server\ndescription=OpenSSH is a free implementation.\nports=22/tcp\n' > "$BATS_TEST_TMPDIR/apps/openssh-server"
  printf '[CUPS]\ntitle=Printing\ndescription=CUPS.\nports=631\n\n[Avahi]\ntitle=mDNS\ndescription=Zeroconf.\nports=5353/udp\n' > "$BATS_TEST_TMPDIR/apps/cups"
  printf 'ENABLED=yes\nLOGLEVEL=low\n' > "$BATS_TEST_TMPDIR/ufw.conf"
  export FZX_FIREWALL_APPS_DIR="$BATS_TEST_TMPDIR/apps" FZX_FIREWALL_CONF="$BATS_TEST_TMPDIR/ufw.conf"
}

src() { FZX_MODE="$1" "$FW/source.sh"; }

@test "rules: a header with the state, policies and logging; numbered rules with to, action, from, comment" {
  run src rules
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 6 ]
  [ "${lines[0]}" = $'-\t-\tufw  active  deny (incoming), allow (outgoing), disabled (routed)  logging on (low)' ]
  [[ "${lines[1]}" == $'1\t22/tcp LIMIT IN Anywhere\t  1  22/tcp '*"  LIMIT IN    Anywhere "*"  # ssh" ]]
  [[ "${lines[2]}" == $'2\tOpenSSH ALLOW IN 192.168.1.0/24\t  2  OpenSSH '* ]]
  # spaces inside the from column; v6 rules; two-digit numbers
  [[ "${lines[3]}" == $'3\t8080 DENY OUT Anywhere on eth0\t'* ]]
  [[ "${lines[4]}" == $'4\t22/tcp (v6) LIMIT IN Anywhere (v6)\t'* ]]
  [[ "${lines[5]}" == $'10\tCUPS REJECT IN Anywhere\t 10  CUPS '* ]]
}

@test "rules without a cached sudo: the header row alone, ufw.conf's state and the hint" {
  touch "$BATS_TEST_TMPDIR/nosudo"
  run src rules
  [ "$status" -eq 0 ]
  [ "$output" = $'-\t-\tufw  active (ufw.conf)  rules need root: run sudo -v, then ctrl-r' ]
  printf 'ENABLED=no\n' > "$BATS_TEST_TMPDIR/ufw.conf"
  run src rules
  [[ "$output" == *"ufw  inactive (ufw.conf)"* ]]
  FZX_MODE=bogus run "$FW/source.sh"
  [ "$status" -eq 2 ]
}

@test "apps: every profile section by name, ports, title, and the rule naming it; without root too" {
  run src apps
  [ "${#lines[@]}" -eq 4 ]
  [ "$(printf '%s\n' "${lines[@]:1}" | cut -f1 | tr '\n' ' ')" = "Avahi CUPS OpenSSH " ]
  [[ "${lines[1]}" == $'Avahi\tAvahi\tAvahi '*"5353/udp "*"  mDNS" ]]
  [[ "${lines[2]}" == $'CUPS\tCUPS\tCUPS '*"  REJECT IN   631 "* ]]
  [[ "${lines[3]}" == $'OpenSSH\tOpenSSH\tOpenSSH '*"  ALLOW IN    22/tcp "*"  Secure shell server" ]]
  touch "$BATS_TEST_TMPDIR/nosudo"
  run src apps
  [ "${#lines[@]}" -eq 4 ]
  [[ "${lines[0]}" == *"rules need root"* && "${lines[3]}" != *ALLOW* ]]
}

@test "preview: the status; a rule's fields and its profile; a profile with its rules; without root" {
  run "$FW/preview.sh" -
  [ "${lines[0]}" = "Status: active" ]
  FZX_MODE=rules run "$FW/preview.sh" 2
  [ "${lines[0]}" = "rule 2" ]
  [[ "$output" == *"to       OpenSSH"* && "$output" == *"action   ALLOW IN"* && "$output" == *"from     192.168.1.0/24"* ]]
  [[ "$output" == *"profile  22/tcp" ]]
  FZX_MODE=rules run "$FW/preview.sh" 4
  [[ "$output" == *"comment  ssh"* && "$output" == *"family   IPv6"* ]]
  FZX_MODE=rules run "$FW/preview.sh" 99
  [ "$output" = "no rule 99 (any more)" ]
  FZX_MODE=apps run "$FW/preview.sh" CUPS
  [ "${lines[0]}" = CUPS ]
  [[ "$output" == *"ports  631"* && "$output" == *"file   $BATS_TEST_TMPDIR/apps/cups"* ]]
  [[ "$output" == *$'rules\n[10] CUPS '* ]]
  FZX_MODE=apps run "$FW/preview.sh" Avahi
  [[ "$output" == *"no rule names it"* ]]
  touch "$BATS_TEST_TMPDIR/nosudo"
  run "$FW/preview.sh" -
  [[ "$output" == *"ufw answers only root"*"ENABLED=yes"* ]]
  FZX_MODE=rules run "$FW/preview.sh" 2
  [ "$output" = "needs root: run sudo -v" ]
}

@test "actions: delete highest first, allow and deny profiles, enable and disable; through sudo" {
  FZX_MODE=rules "$FW/actions.sh" delete - 2 10 4
  FZX_MODE=apps "$FW/actions.sh" allow OpenSSH "Postfix SMTPS"
  FZX_MODE=apps "$FW/actions.sh" deny CUPS
  "$FW/actions.sh" enable
  "$FW/actions.sh" disable
  [ "$(grep '^ufw' "$BATS_TEST_TMPDIR/calls")" = "ufw --force delete 10
ufw --force delete 4
ufw --force delete 2
ufw allow OpenSSH
ufw allow Postfix SMTPS
ufw deny CUPS
ufw --force enable
ufw disable" ]
  [ "$(grep -c '^sudo ufw' "$BATS_TEST_TMPDIR/calls")" -eq 8 ]
  FZX_MODE=apps run "$FW/actions.sh" delete OpenSSH
  [ "$status" -eq 2 ]
  FZX_MODE=rules run "$FW/actions.sh" allow 1
  [ "$status" -eq 2 ]
}

@test "ufw off: the added rules, not in effect, ids by rule; profiles marked from them; delete by rule" {
  touch "$BATS_TEST_TMPDIR/inactive"
  run src rules
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  [ "${lines[0]}" = $'-\t-\tufw  inactive  rules added, not in effect' ]
  [ "${lines[1]}" = $'added:allow 22/tcp\tallow 22/tcp\t  -  ALLOW       22/tcp  (not in effect)' ]
  [[ "${lines[2]}" == $'added:limit 2222/tcp comment \'ssh\'\t'*"  LIMIT       2222/tcp comment 'ssh'  (not in effect)" ]]
  run src apps
  [[ "${lines[3]}" == $'OpenSSH\tOpenSSH\tOpenSSH '*"  ALLOW off  "* ]]
  [[ "${lines[2]}" == $'CUPS\tCUPS\tCUPS '*"            631"* ]]
  FZX_MODE=rules run "$FW/preview.sh" "added:allow OpenSSH"
  [ "${lines[0]}" = "ufw allow OpenSSH" ]
  [[ "$output" == *"not in effect: ufw is off"* && "$output" == *"profile  22/tcp" ]]
  FZX_MODE=rules "$FW/actions.sh" delete "added:limit 2222/tcp comment 'ssh'" "added:deny 'Postfix SMTPS'" 3
  [ "$(grep '^ufw' "$BATS_TEST_TMPDIR/calls")" = "ufw delete limit 2222/tcp
ufw delete deny Postfix SMTPS
ufw --force delete 3" ]
  source "$FW/source.sh" || :
  source "$FW/actions.sh" || :
  firewall::_words "allow from 10.0.0.1 to any app 'Postfix SMTPS' comment 'x y'"
  [ "${#FIREWALL_WORDS[@]}" -eq 7 ] && [ "${FIREWALL_WORDS[6]}" = "Postfix SMTPS" ]
}

@test "add and insert: checked with --dry-run, then added (at a position); verbs only; insert needs a number" {
  source "$FW/actions.sh" || :
  firewall::_add "" "ufw allow from 10.0.0.0/8 to any port 22 proto tcp comment 'lan ssh'"
  firewall::_add 3 "deny out 25"
  [ "$(grep '^ufw' "$BATS_TEST_TMPDIR/calls")" = "ufw --dry-run allow from 10.0.0.0/8 to any port 22 proto tcp comment lan ssh
ufw allow from 10.0.0.0/8 to any port 22 proto tcp comment lan ssh
ufw --dry-run insert 3 deny out 25
ufw insert 3 deny out 25" ]
  : > "$BATS_TEST_TMPDIR/calls"
  run firewall::_add "" "allow bogus"
  [ "$status" -eq 1 ] && [ "$output" = "ERROR: Bad port" ]
  [ "$(grep -c '^ufw' "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
  run firewall::_add "" "reset"
  [ "$status" -eq 2 ] && [[ "$output" == *"starts with allow, deny, reject or limit"* ]]
  # insert without a numbered rule (the header row, rules added while ufw is off)
  FZX_MODE=rules run "$FW/actions.sh" insert - "added:allow 22/tcp"
  [ "$status" -eq 2 ] && [[ "$output" == *"above a numbered rule"* ]]
  FZX_MODE=apps run "$FW/actions.sh" insert OpenSSH
  [ "$status" -eq 2 ]
}

@test "under fzx: the header row, rules or names accepted, the action keys" {
  stub_fzf
  run "$FZX" -m firewall
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header-lines=1 "* && " ${FZF_ARGS[*]} " == *" --accept-nth=2 "* ]]
  [[ "$(fzf_bind alt-x)" == "alt-x:execute($FZX _cb action delete {+1})+"*"reload("* ]]
  [[ "$(fzf_bind alt-a)" == "alt-a:execute($FZX _cb action allow {+1})+"*"reload("* ]]
  [[ "$(fzf_bind ctrl-y)" == *"copy {+2}"* ]]
  [[ "$(fzf_bind alt-n)" == "alt-n:execute($FZX _cb action add {+1})+"*"reload("* ]]
  [[ "$(fzf_bind alt-I)" == "alt-I:execute($FZX _cb action insert {+1})+"*"reload("* ]]
}

@test "menu: where ufw is installed; on or off from ufw.conf; the profile count" {
  source "$FW/manifest.sh"
  firewall::applicable firewall
  [ "$(firewall::summary firewall)" = on ]
  [ "$(firewall::summary firewall:apps)" = "3 profiles" ]
}
