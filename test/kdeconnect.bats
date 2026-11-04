#!/usr/bin/env bats
# the kdeconnect module with stubbed kdeconnect-cli and busctl (calls are logged; nothing reaches a device)

load test_helper

KC="$(readlink -f "$BATS_TEST_DIRNAME/../modules/kdeconnect")"

setup() {
  setup_fzx
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  CALLS="$BATS_TEST_TMPDIR/calls"
  cat > "$BATS_TEST_TMPDIR/bin/kdeconnect-cli" << STUB
#!/usr/bin/env bash
printf 'cli %s\n' "\$*" >> "$CALLS"
[[ -z "\${STUB_CLI_FAIL:-}" ]] || { echo "\$STUB_CLI_FAIL" >&2; exit 1; }
case "\$*" in
  '-l --id-name-only') [[ -n "\${STUB_NONE:-}" ]] && { echo '0 devices found' >&2; exit 0; }; printf 'phone1 Fold\naway1 Old Tablet\nnew1 Zed Laptop\n' ;;
  '-a --id-name-only') [[ -n "\${STUB_NONE:-}" ]] && exit 0; printf 'phone1 Fold\n' ;;
  *'--encryption-info'*) printf 'SHA256 fingerprint of your device certificate is: aa:aa\nSHA256 fingerprint of remote device certificate is: bb:bb\n' ;;
  *'--list-commands'*) printf 'k1: Lights: lights --on\nk2: Say: echo a: b\n' ;;
esac
exit 0
STUB
  cat > "$BATS_TEST_TMPDIR/bin/busctl" << 'STUB'
#!/usr/bin/env bash
printf 'bus %s\n' "$*" >> "$STUB_CALLS"
args=" $* "
case "$args" in
  *' status org.kde.kdeconnect '*) [[ -z "${STUB_DOWN:-}" ]]; exit ;;
  *'/phone1/battery '*) printf 'i %s\nb %s\n' "${STUB_CHARGE:-32}" "${STUB_CHARGING:-false}" ;;
  *'/phone1 org.kde.kdeconnect.device isReachable isPaired type '*) printf 'b true\nb true\ns "phone"\n' ;;
  *'/away1 org.kde.kdeconnect.device isReachable isPaired type '*) printf 'b false\nb true\ns "tablet"\n' ;;
  *'/new1 org.kde.kdeconnect.device isReachable isPaired type '*) printf 'b true\nb false\ns "desktop"\n' ;;
  *'/phone1 org.kde.kdeconnect.device isReachable name '*) printf 'b true\ns "Fold"\n' ;;
  *'/away1 org.kde.kdeconnect.device isReachable name '*) printf 'b false\ns "Old Tablet"\n' ;;
  *'/phone1 org.kde.kdeconnect.device name '*) printf 's "Fold"\n' ;;
  *' loadedPlugins '*) printf 'as 7 "kdeconnect_ping" "kdeconnect_findmyphone" "kdeconnect_clipboard" "kdeconnect_share" "kdeconnect_sms" "kdeconnect_remotekeyboard" %s\n' "${STUB_PLUGIN:-\"kdeconnect_x\"}" ;;
  *' activeNotifications '*) [[ -n "${STUB_QUIET:-}" ]] && { echo '{"type":"as","data":[[]]}'; exit; }; echo '{"type":"as","data":[["7","8"]]}' ;;
  *'/notifications/7 '*' GetAll '*) echo '{"type":"a{sv}","data":[{"appName":{"type":"s","data":"Signal"},"title":{"type":"s","data":"Sam"},"text":{"type":"s","data":"line one\nline\ttwo\u001b[2J"},"dismissable":{"type":"b","data":true}}]}' ;;
  *'/notifications/8 '*' GetAll '*) echo '{"type":"a{sv}","data":[{"appName":{"type":"s","data":"Battery"},"title":{"type":"s","data":"Low"},"text":{"type":"s","data":"back\\slash"},"dismissable":{"type":"b","data":false}}]}' ;;
  *'/notifications/9 '*' GetAll '*) echo 'Failed' >&2; exit 1 ;;
  *' dismiss '*) exit 0 ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" STUB_CALLS="$CALLS"
  export FZX_TTY="$BATS_TEST_TMPDIR/answers" FZX_KDECONNECT_TTY="$BATS_TEST_TMPDIR/typed"
}

plain() { sed 's/\x1b\[[0-9;:]*m//g'; }
src() { FZX_MODE="$1" "$KC/source.sh" | plain; }
prev() { FZX_MODE="$1" "$KC/preview.sh" "${@:2}" | plain; }
act() { FZX_MODE="$1" "$KC/actions.sh" "${@:2}"; }
typed() { printf '%s\n' "$@" > "$FZX_KDECONNECT_TTY"; }

@test "devices: connected first, then away, then not paired; state and battery; id, name and details in fields" {
  run src devices
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == phone1$'\t'*Fold*phone*connected*'32%'$'\t'Fold$'\t'true* ]]
  [[ "${lines[1]}" == away1$'\t'*'Old Tablet'*tablet*away*-$'\t''Old Tablet'$'\t'false* ]]
  [[ "${lines[2]}" == new1$'\t'*'Zed Laptop'*desktop*'not paired'* ]]
  [ "$(printf '%s\n' "${lines[0]}" | awk -F'\t' '{ print NF }')" -eq 4 ]
}

@test "devices: by name; the battery of an away device is not asked for" {
  FZX_SORT=name run src devices
  [[ "${lines[0]}" == phone1$'\t'* && "${lines[1]}" == away1$'\t'* && "${lines[2]}" == new1$'\t'* ]]
  ! grep -q '/away1/battery' "$CALLS"
}

@test "devices: charging is named, a low battery marked, unless it is charging" {
  STUB_CHARGING=true run src devices
  [[ "${lines[0]}" == *'32% charging'$'\t'* ]]
  STUB_CHARGE=10 run bash -c "FZX_MODE=devices '$KC/source.sh'"
  [[ "${lines[0]}" == *$'\e[38;5;203m10%'* ]]
  STUB_CHARGE=10 STUB_CHARGING=true run bash -c "FZX_MODE=devices '$KC/source.sh'"
  [[ "${lines[0]}" != *$'\e[38;5;203m10%'* ]]
}

@test "devices: none known, and the daemon failing, are rows with an empty id" {
  STUB_NONE=1 run src devices
  [ "$status" -eq 0 ]
  [[ "$output" == $'\tno devices known'* ]]
  STUB_CLI_FAIL='cannot reach the daemon' FZX_MODE=devices run "$KC/source.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'cannot list devices: cannot reach the daemon'* ]]
}

@test "devices: a header row names the columns" {
  run bash -c "FZX_MODE=devices FZX_SORT_HEADER=1 '$KC/source.sh' | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" == $'\t'*NAME*TYPE*STATE*BATTERY* ]]
  [[ "${lines[1]}" == phone1$'\t'* ]]
}

@test "without its tools the source says which is missing" {
  run bash -c "source '$FZX_REPO/lib/core.sh'; source '$KC/source.sh'; command() { [[ \"\$2\" == kdeconnect-cli ]] && return 1; builtin command \"\$@\"; }; FZX_MODE=devices kdeconnect::source"
  [ "$status" -eq 2 ]
  [[ "$output" == *'kdeconnect-cli command is not installed'* ]]
}

@test "notifications: one row each, control characters gone, ids naming device and notification" {
  run src notifications
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == phone1/7$'\t'*Signal*Sam*'line one line two'*$'\t'Sam ]]
  [[ "${lines[1]}" == phone1/8$'\t'*Battery*Low*'back\slash'*$'\t'Low ]]
  [[ "$output" != *$'\e[2J'* ]]
  run bash -c "FZX_MODE=notifications '$KC/source.sh'"
  [[ "$output" != *$'\e[2J'* ]]
  [ "$(printf '%s\n' "${lines[0]}" | awk -F'\t' '{ print NF }')" -eq 3 ]
}

@test "notifications: only connected devices are asked; empty and nobody connected say so" {
  run src notifications
  ! grep -q '/away1/notifications' "$CALLS"
  STUB_QUIET=1 run src notifications
  [[ "$output" == $'\tno notifications\t'* ]]
  STUB_NONE=1 run src notifications
  [[ "$output" == $'\tno device connected\t'* ]]
}

@test "notifications stay off disk: the module keeps nothing" {
  run grep -E '^FZX_PERSIST=none' "$KC/config.sh"
  [ "$status" -eq 0 ]
}

@test "notification preview: the whole text from the bus, clean; what cannot be dismissed; one gone since" {
  run prev notifications phone1/7 Sam
  [[ "${lines[0]}" == *Sam*Signal* ]]
  [[ "$output" == *'line one'$'\n''line'$'\t''two'* ]]
  [[ "$output" != *$'\e[2J'* && "$output" != *'cannot be dismissed'* ]]
  run prev notifications phone1/8 Low
  [[ "$output" == *'cannot be dismissed'* ]]
  run prev notifications phone1/9 Gone
  [ "$status" -eq 0 ]
  [[ "$output" == *'no longer on the device'* ]]
}

@test "commands: only devices with the plugin are asked; a colon in the command line stays; none says so" {
  run src commands
  [[ "$output" == $'\tno connected device offers commands\t'* ]]
  ! grep -q -- '--list-commands' "$CALLS"
  export STUB_PLUGIN='"kdeconnect_remotecommands"'
  run src commands
  [[ "${lines[0]}" == phone1/k1$'\t'*Lights*'lights --on'$'\t'Lights$'\t''lights --on' ]]
  [[ "${lines[1]}" == phone1/k2$'\t'*Say*'echo a: b'$'\t'Say$'\t''echo a: b' ]]
}

@test "device preview: state, battery, the device's own fingerprint, plugins; away ones are not asked" {
  run prev devices phone1 Fold $'true\x1ftrue\x1fphone\x1f32\x1ffalse'
  [[ "$output" == *Fold*connected* && "$output" == *'32%'* && "$output" == *'bb:bb'* && "$output" != *'aa:aa'* && "$output" == *ping*share* ]]
  : > "$CALLS"
  run prev devices away1 'Old Tablet' $'false\x1ftrue\x1ftablet\x1f-\x1ffalse'
  [[ "$output" == *'Old Tablet'*away* && "$output" != *battery* && "$output" != *sha256* ]]
  [ ! -s "$CALLS" ]
  run prev devices new1 Zed $'true\x1ffalse\x1fdesktop\x1f-\x1ffalse'
  [[ "$output" == *'not paired'* ]]
}

@test "preview of a row without an id, and of a command" {
  run prev devices "" "no devices known" ""
  [ "$output" = "no devices known" ]
  run prev commands phone1/k1 Lights 'lights --on'
  [[ "$output" == *Lights* && "$output" == *'lights --on'* && "$output" == *k1* ]]
}

@test "ping, ring, clipboard: each selected device" {
  act devices ping phone1
  grep -qx 'cli -d phone1 --ping' "$CALLS"
  act devices ring phone1
  grep -qx 'cli -d phone1 --ring' "$CALLS"
  act devices clipboard phone1
  grep -qx 'cli -d phone1 --send-clipboard' "$CALLS"
}

@test "a device that is away is named, and one failing does not stop the others" {
  run act devices ping away1 phone1
  [ "$status" -eq 1 ]
  [[ "$output" == *'Old Tablet is not connected'* ]]
  grep -qx 'cli -d phone1 --ping' "$CALLS"
  ! grep -q 'cli -d away1' "$CALLS"
}

@test "lock and unlock need the plugin: a phone without it is told so" {
  run act devices lock phone1
  [ "$status" -eq 1 ]
  [[ "$output" == *'Fold does not support this (no lockdevice plugin)'* ]]
  ! grep -q -- '--lock' "$CALLS"
  export STUB_PLUGIN='"kdeconnect_lockdevice"'
  act devices lock phone1
  grep -qx 'cli -d phone1 --lock' "$CALLS"
  act devices unlock phone1
  grep -qx 'cli -d phone1 --unlock' "$CALLS"
}

@test "share: a URL as it is, a file made absolute, ~ expanded; a missing file is refused; nothing typed cancels" {
  typed 'https://example.com/a'
  act devices share phone1
  grep -qxF 'cli -d phone1 --share=https://example.com/a' "$CALLS"
  : > "$BATS_TEST_TMPDIR/a file"
  typed "$BATS_TEST_TMPDIR/a file"
  act devices share phone1
  grep -qxF "cli -d phone1 --share=$(readlink -f "$BATS_TEST_TMPDIR/a file")" "$CALLS"
  : > "$HOME/kc-file"
  typed '~/kc-file'
  act devices share phone1
  grep -qxF "cli -d phone1 --share=$(readlink -f "$HOME/kc-file")" "$CALLS"
  : > "$CALLS"
  typed '/no/such/file'
  run act devices share phone1
  [ "$status" -eq 1 ]
  [[ "$output" == *'no such file: /no/such/file'* ]]
  [ ! -s "$CALLS" ]
  typed ''
  run act devices share phone1
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "text and keys: the typed line whole, even with a dash first; nothing typed cancels" {
  typed '--not an option'
  act devices text phone1
  grep -qxF 'cli -d phone1 --share-text=--not an option' "$CALLS"
  typed 'hello there'
  act devices keys phone1
  grep -qxF 'cli -d phone1 --send-keys=hello there' "$CALLS"
  : > "$CALLS"
  typed ''
  run act devices keys phone1
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "sms: sent only on y, the number tidied, shown first; a bad number or no answer sends nothing" {
  typed '+1 (555) 123-4567' 'see you soon'
  printf 'n' > "$FZX_TTY"
  run act devices sms phone1
  [ "$status" -eq 0 ]
  grep -qF 'send from Fold to +15551234567: "see you soon"' "$FZX_TTY"
  ! grep -q -- '--send-sms' "$CALLS"
  printf 'y' > "$FZX_TTY"
  act devices sms phone1
  grep -qxF 'cli -d phone1 --destination +15551234567 --send-sms=see you soon' "$CALLS"
  : > "$CALLS"
  typed 'not a number' 'hello'
  printf 'y' > "$FZX_TTY"
  run act devices sms phone1
  [ "$status" -eq 1 ]
  [[ "$output" == *'not a phone number'* ]]
  ! grep -q -- '--send-sms' "$CALLS"
  typed '5551234' ''
  run act devices sms phone1
  [ "$status" -eq 0 ]
  ! grep -q -- '--send-sms' "$CALLS"
}

@test "on a terminal, a foreground action's errors reach it and not fzx's log, where stderr goes" {
  command -v script > /dev/null || skip "no script command"
  local log="$BATS_TEST_TMPDIR/action.log"
  typed '/no/such/file'
  run timeout 5 script -qec "env FZX_MODE=devices FZX_KDECONNECT_TTY='$FZX_KDECONNECT_TTY' '$KC/actions.sh' share phone1 2>> '$log'" /dev/null < /dev/null
  [[ "$output" == *'no such file: /no/such/file'* ]]
  [ ! -s "$log" ]
}

@test "what is typed goes in no history file" {
  typed '5551234' 'a private message'
  printf 'y' > "$FZX_TTY"
  act devices sms phone1
  typed 'more private text'
  act devices text phone1
  run grep -rl 'private' "$FZX_STATE_DIR" "$FZX_CACHE_DIR"
  [ "$status" -ne 0 ]
}

@test "pair, unpair and refresh" {
  act devices pair new1
  grep -qx 'cli -d new1 --pair' "$CALLS"
  act devices unpair away1
  grep -qx 'cli -d away1 --unpair' "$CALLS"
  act devices refresh
  grep -qx 'cli --refresh' "$CALLS"
  act notifications refresh ""
  [ "$(grep -c 'cli --refresh' "$CALLS")" -eq 2 ]
}

@test "dismiss: the notification on its device; run: a command on its device" {
  act notifications dismiss phone1/7
  grep -q '/devices/phone1/notifications/7 org.kde.kdeconnect.device.notifications.notification dismiss' "$CALLS"
  export STUB_PLUGIN='"kdeconnect_remotecommands"'
  act commands run phone1/k1
  grep -qx 'cli -d phone1 --execute-command k1' "$CALLS"
}

@test "actions refuse the wrong mode, skip rows without an id and refuse unknown names" {
  run act notifications ping phone1/7
  [ "$status" -eq 2 ]
  [[ "$output" == *'ping does not apply to notifications'* ]]
  run act devices dismiss phone1
  [ "$status" -eq 2 ]
  : > "$CALLS"
  run act devices ping ""
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  run act devices explode phone1
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown action'* ]]
}

@test "lock, unlock, unpair and run are confirmed by fzx; sms asks itself" {
  run bash -c "grep -E '^action' '$KC/components.tsv' | grep -E '\bconfirm\b' | awk '{ print \$2 }' | sort | paste -sd ' '"
  [ "$output" = "lock run unlock unpair" ]
  grep -qE '^action +sms .*asks$' "$KC/components.tsv"
}

@test "every row of the table parses, in every mode" {
  local m
  for m in devices notifications commands; do
    run bash -c "'$FZX' -m kdeconnect:$m --dry-run 2>&1 > /dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "under fzx: keys are bound; ctrl-y copies the name; the id is printed" {
  stub_fzf
  run "$FZX" -m kdeconnect
  [ "$status" -eq 0 ]
  [[ "$(fzf_bind alt-p)" == *'_cb notify ping'* ]]
  [[ "$(fzf_bind alt-m)" == *'_cb action sms'* ]]
  [[ "$(fzf_bind alt-l)" == *'lock'* ]]
  [[ "$(fzf_bind alt-v)" == *'_cb notify clipboard'* ]]
  [[ "$(fzf_bind ctrl-y)" == *"_cb notify copy {+3}"* ]]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=1 "* ]]
}

@test "menu: listed where the daemon runs, asked once and without starting it; summaries" {
  load_libs log config menu
  fzx::menu_entries kdeconnect "$KC"
  [[ " ${FZX_ENTRY_TARGETS[*]} " == *" kdeconnect:notifications "* ]]
  local t
  : > "$CALLS"
  for t in "${FZX_ENTRY_TARGETS[@]}"; do kdeconnect::applicable "$t"; done
  [ "$(grep -c 'status org.kde.kdeconnect' "$CALLS")" -eq 1 ]
  ! grep -q '^cli' "$CALLS"
  _KDECONNECT_UP=""
  STUB_DOWN=1 run kdeconnect::applicable kdeconnect
  [ "$status" -ne 0 ]
  [ "$(kdeconnect::summary kdeconnect)" = "Fold 32%" ]
  [ "$(kdeconnect::summary kdeconnect:notifications)" = "2 notifications" ]
  [ "$(STUB_NONE=1 kdeconnect::summary kdeconnect)" = "nothing connected" ]
}
