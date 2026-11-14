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
  *' activeConversations '*) [[ -n "${STUB_QUIET:-}" ]] && { echo '{"type":"av","data":[[]]}'; exit; }; cat "$STUB_THREADS" ;;
  *' requestAllConversationThreads '*) exit 0 ;;
  *' requestConversation '*) exit 0 ;;
  *' monitor '*)
    [[ -n "${STUB_SILENT:-}" ]] && exit 0
    cat "$STUB_MONITOR"
    # as the real one: it runs until it is stopped
    echo "$$" > "$STUB_MONITOR.pid"
    exec sleep 317 ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" STUB_CALLS="$CALLS"
  export FZX_TTY="$BATS_TEST_TMPDIR/answers" FZX_KDECONNECT_TTY="$BATS_TEST_TMPDIR/typed"
  # threads: Sam (a contact, unread), a number nobody knows (sent by you), a group of four, one only an attachment
  export STUB_THREADS="$BATS_TEST_TMPDIR/threads" STUB_MONITOR="$BATS_TEST_TMPDIR/monitor" XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  cat > "$STUB_THREADS" << 'JSON'
{"type":"av","data":[[
{"type":"(isa(s)xiixixa(xsss))","data":[1,"see\nyou\tthere\u001b[2J",[["+1 (555) 123-0001"]],1767225600000,1,0,11,1,1,[]]},
{"type":"(isa(s)xiixixa(xsss))","data":[1,"on my way",[["5559998888"]],1767312000000,2,1,12,2,1,[]]},
{"type":"(isa(s)xiixixa(xsss))","data":[1,"hello all",[["5551230001"],["5550000002"],["5550000003"],["5550000004"]],1767139200000,1,1,13,3,1,[]]},
{"type":"(isa(s)xiixixa(xsss))","data":[1,"",[["5550000005"]],1767052800000,1,1,14,4,1,[[1,"image/png","x","y"]]]}
]]}
JSON
  cat > "$STUB_MONITOR" << 'JSON'
{"member":"conversationUpdated","payload":{"type":"v","data":[{"type":"(isa(s)xiixixa(xsss))","data":[1,"older\u001b[2J\nsecond line",[["5551230001"]],1767139200000,1,1,11,8,1,[]]}]}}
{"member":"conversationUpdated","payload":{"type":"v","data":[{"type":"(isa(s)xiixixa(xsss))","data":[1,"from me",[["5551230001"]],1767225600000,2,1,11,9,1,[[1,"image/png","x","y"]]]}]}}
{"member":"conversationUpdated","payload":{"type":"v","data":[{"type":"(isa(s)xiixixa(xsss))","data":[1,"another thread",[["5550000009"]],1767225600000,1,1,99,10,1,[]]}]}}
{"member":"conversationLoaded","payload":{"type":"xt","data":[99,1]}}
{"member":"conversationUpdated","payload":{"type":"v","data":[{"type":"(isa(s)xiixixa(xsss))","data":[1,"late one",[["5551230001"]],1767312000000,1,1,11,11,1,[]]}]}}
{"member":"conversationLoaded","payload":{"type":"xt","data":[11,3]}}
{"member":"conversationUpdated","payload":{"type":"v","data":[{"type":"(isa(s)xiixixa(xsss))","data":[1,"after it was loaded",[["5551230001"]],1767398400000,1,1,11,12,1,[]]}]}}
JSON
  mkdir -p "$XDG_DATA_HOME/kpeoplevcard/kdeconnect-phone1"
  printf 'BEGIN:VCARD\r\nFN:Sam Lee\r\nTEL;TYPE=CELL:+1 555 123 0001\r\nPHOTO:FN:not a name\r\n abc\r\nEND:VCARD\r\n' > "$XDG_DATA_HOME/kpeoplevcard/kdeconnect-phone1/a.vcf"
  printf 'BEGIN:VCARD\r\nFN:Pat\r\nTEL:5550000002\r\nEND:VCARD\r\n' > "$XDG_DATA_HOME/kpeoplevcard/kdeconnect-phone1/b.vcf"
  export TZ=UTC
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

@test "sms: threads, newest first, contacts named, unread marked, you marked, text safe, ids naming device and thread" {
  run src sms
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [[ "${lines[0]}" == phone1/12$'\t'*5559998888*'2026-01-02 00:00'*'you: on my way'$'\t'5559998888 ]]
  [[ "${lines[1]}" == phone1/11$'\t'*'Sam Lee'*'2026-01-01 00:00'*'see you there'$'\t''Sam Lee' ]]
  [[ "${lines[2]}" == phone1/13$'\t'*'Sam Lee, Pat +2'*'hello all'* ]]
  [[ "${lines[3]}" == phone1/14$'\t'*'(attachment)'* ]]
  [ "$(printf '%s\n' "${lines[0]}" | awk -F'\t' '{ print NF }')" -eq 3 ]
  run bash -c "FZX_MODE=sms '$KC/source.sh'"
  [[ "$output" != *$'\e[2J'* && "$output" != *'[2J'* ]]
  # the unread mark only on the unread thread
  [[ "$(printf '%s\n' "${lines[1]}" | cut -f2)" == *●* && "$(printf '%s\n' "${lines[0]}" | cut -f2)" != *●* ]]
}

@test "sms and its preview: emoji the terminal widens differently lose their selectors and skin tones" {
  sed -i 's/"on my way"/"on my way \\u2764\\ufe0f \\ud83d\\udc4d\\ud83c\\udffb"/' "$STUB_THREADS"
  sed -i 's/"late one"/"late one \\u2764\\ufe0f"/' "$STUB_MONITOR"
  local heart skin
  heart="$(printf '\u2764')" skin="$(printf '\U1F3FB')"
  run src sms
  [[ "${lines[0]}" == phone1/12$'\t'*"you: on my way $heart $(printf '\U1F44D')"$'\t'5559998888 ]]
  [[ "$output" != *$'\ufe0f'* && "$output" != *"$skin"* ]]
  run prev sms phone1/11 'Sam Lee'
  [[ "$output" == *"late one $heart"* && "$output" != *$'\ufe0f'* ]]
  FZX_GLYPHS_PLAIN=0 run src sms
  [[ "${lines[0]}" == *"$skin"* ]]
}

@test "sms: by name; a header row names the columns" {
  FZX_SORT=name run src sms
  [[ "${lines[0]}" == phone1/14$'\t'* && "${lines[1]}" == phone1/12$'\t'* && "${lines[2]}" == phone1/11$'\t'* && "${lines[3]}" == phone1/13$'\t'* ]]
  run bash -c "FZX_MODE=sms FZX_SORT_HEADER=1 '$KC/source.sh' | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" == $'\t'*NAME*DATE*LAST* ]]
  [[ "${lines[1]}" == phone1/12$'\t'* ]]
}

@test "sms: only a connected device with the plugin; asked once; nothing yet and nobody connected say so" {
  run src sms
  grep -q requestAllConversationThreads "$CALLS"
  ! grep -q '/away1' <(grep -E 'activeConversations|requestAll' "$CALLS")
  FZX_KDECONNECT_SMS_WAIT=0 STUB_QUIET=1 run src sms
  [[ "$output" == $'\tno conversations yet'* ]]
  STUB_NONE=1 run src sms
  [[ "$output" == $'\tno device connected\t'* ]]
}

@test "sms: no contacts synced: the numbers show" {
  rm -rf "$XDG_DATA_HOME/kpeoplevcard"
  run src sms
  [[ "${lines[1]}" == *'+1 (555) 123-0001'* ]]
}

@test "sms preview: this thread only, newest first up to when it loaded, who sent it, attachments, text safe" {
  run prev sms phone1/11 'Sam Lee'
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == 'Sam Lee' ]]
  [[ "$output" == *'late one'*'from me'*'attachment'*'older'*'second line'* ]]
  [[ "$output" != *'another thread'* && "$output" != *'after it was loaded'* && "$output" != *'[2J'* ]]
  [[ "$output" == *'2026-01-01 00:00  you'* ]]
  grep -q 'requestConversation xii 11 0 30' "$CALLS"
}

@test "sms preview: a group names who wrote; the monitor is gone afterwards; nothing back says so" {
  cat > "$STUB_MONITOR" << 'JSON'
{"member":"conversationUpdated","payload":{"type":"v","data":[{"type":"(isa(s)xiixixa(xsss))","data":[1,"hi",[["5551230001"],["5550000002"]],1767225600000,1,1,13,5,1,[]]}]}}
{"member":"conversationLoaded","payload":{"type":"xt","data":[13,1]}}
JSON
  run prev sms phone1/13 'Sam Lee, Pat'
  [[ "$output" == *'2026-01-01 00:00  Sam Lee'* && "$output" == *hi* ]]
  sleep 0.2
  ! kill -0 "$(cat "$STUB_MONITOR.pid")" 2> /dev/null
  STUB_SILENT=1 run prev sms phone1/13 'Sam Lee, Pat'
  [ "$status" -eq 0 ]
  [[ "$output" == *'no messages came back'* ]]
}

# python3 for kdeconnect::reply: records its arguments and what it read (STUB_PY_FAIL: fails saying so)
stub_reply() {
  cat > "$BATS_TEST_TMPDIR/bin/python3" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "${@:3}" > "$BATS_TEST_TMPDIR/py.args"
cat > "$BATS_TEST_TMPDIR/py.in"
[[ -z "${STUB_PY_FAIL:-}" ]] || { echo "$STUB_PY_FAIL" >&2; exit 1; }
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/python3"
}

# a kept chat session for phone1/11, its id in $sid
chat_session() {
  stub_fzf
  run "$FZX" -m kdeconnect:chat --keep -- --thread phone1/11
  [ "$status" -eq 0 ]
  sid="$(basename "$(session_dirs)")"
}

@test "sms: enter opens the thread's chat, a child screen; a row without a thread rings the bell" {
  stub_fzf
  run "$FZX" -m kdeconnect:sms --keep
  [ "$(fzf_bind enter)" = "enter:transform:$FZX _cb transform chat {1}" ]
  local sid child
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" run "$FZX" _cb transform chat phone1/11
  [[ "$output" == "become:$FZX --resume "*" -m :chat" ]]
  child="${output#*--resume }" child="${child%% *}"
  [ "$(tr '\0' ' ' < "$FZX_RUNTIME_DIR/sessions/$child/meta/args")" = "--thread phone1/11 " ]
  [ "$(cat "$FZX_RUNTIME_DIR/sessions/$child/meta/parent")" = "$sid" ]
  FZX_SESSION="$sid" run "$FZX" _cb transform chat ''
  [ "$output" = bell ]
  FZX_SESSION="$sid" run "$FZX" _cb transform chat 'phone1/11; rm -rf /'
  [ "$output" = bell ]
}

@test "chat: the header row names the thread; messages newest first, yours marked, attachments counted" {
  FZX_KDECONNECT_CHAT_LIVE=0 FZX_MODE=chat run bash -c "'$KC/source.sh' --thread phone1/11 | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [[ "${lines[0]}" == $'\tSam Lee  type a reply: enter asks, enter again sends' ]]
  [[ "${lines[1]}" == 11$'\t'*'2026-01-02 00:00  late one' ]]
  [[ "${lines[2]}" == 9$'\t'*'2026-01-01 00:00  you: from me (1 attachment)' ]]
  [[ "${lines[3]}" == 8$'\t'*'older second line' ]]
  # nothing from another thread, nor what came after the phone said it was done
  [[ "$output" != *'another thread'* && "$output" != *'after it was loaded'* && "$output" != *'[2J'* ]]
  grep -q 'requestConversation xii 11 0 50' "$CALLS"
  # a thread id it cannot read, and a phone that sends nothing back
  FZX_MODE=chat run "$KC/source.sh" --thread nope
  [ "$status" -eq 2 ]
  STUB_SILENT=1 FZX_KDECONNECT_CHAT_LIVE=0 FZX_MODE=chat run bash -c "'$KC/source.sh' --thread phone1/11 | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "$output" == *'no messages came back from the phone'* ]]
}

@test "chat: the query is the reply: enter asks, enter again on the same text sends it on stdin, then clears" {
  chat_session
  [ "$(fzf_bind enter)" = "enter:transform:$FZX _cb transform send" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *' --disabled '* && " ${FZF_ARGS[*]} " == *' --header-lines=1 '* ]]
  [ "$(fzf_bind change)" = "change:change-header:" ]
  # no preview: none by the terminal's width either
  [[ " ${FZF_ARGS[*]} " != *'_cb layout start'* ]]
  stub_reply
  FZF_QUERY='see you at 6' FZX_SESSION="$sid" run "$FZX" _cb transform send
  [ "$output" = 'change-header:send to Sam Lee: "see you at 6"?  enter sends it, typing cancels' ]
  [ ! -e "$BATS_TEST_TMPDIR/py.in" ]
  # other text: asked about again
  FZF_QUERY='see you at 7' FZX_SESSION="$sid" run "$FZX" _cb transform send
  [[ "$output" == 'change-header:send to Sam Lee: "see you at 7"?'* ]]
  FZF_QUERY='see you at 7' FZX_SESSION="$sid" run "$FZX" _cb transform send
  [ "$output" = 'clear-query+change-header:sent to Sam Lee; it shows here when the phone reports it' ]
  [ "$(cat "$BATS_TEST_TMPDIR/py.args")" = $'phone1\n11' ]
  # the text exactly, no newline added
  [ "$(od -An -c "$BATS_TEST_TMPDIR/py.in" | tr -s ' ')" = ' s e e y o u a t 7' ]
  # sent once: the next enter asks again
  FZF_QUERY='see you at 7' FZX_SESSION="$sid" run "$FZX" _cb transform send
  [[ "$output" == 'change-header:send to'* ]]
  # nothing typed: the bell
  FZF_QUERY='   ' FZX_SESSION="$sid" run "$FZX" _cb transform send
  [ "$output" = bell ]
  # what was typed is in no file and not in the log
  run grep -rl 'see you' "$FZX_STATE_DIR" "$FZX_CACHE_DIR" "$FZX_RUNTIME_DIR"
  [ "$status" -ne 0 ]
}

@test "chat: a reply the phone does not take says why and keeps the text" {
  chat_session
  stub_reply
  FZF_QUERY='hi' FZX_SESSION="$sid" "$FZX" _cb transform send > /dev/null
  STUB_PY_FAIL='org.freedesktop.DBus.Error.NoReply' FZF_QUERY='hi' FZX_SESSION="$sid" run "$FZX" _cb transform send
  [ "$output" = 'bell+change-header:not sent: org.freedesktop.DBus.Error.NoReply' ]
  # a device that went away is named, nothing sent
  rm -f "$BATS_TEST_TMPDIR/py.in"
  sed -i "s|'/phone1 org.kde.kdeconnect.device isReachable name '\*) printf 'b true|'/phone1 org.kde.kdeconnect.device isReachable name '*) printf 'b false|" "$BATS_TEST_TMPDIR/bin/busctl"
  FZF_QUERY='hi' FZX_SESSION="$sid" "$FZX" _cb transform send > /dev/null
  FZF_QUERY='hi' FZX_SESSION="$sid" run "$FZX" _cb transform send
  [ "$output" = 'bell+change-header:not sent: kdeconnect: Fold is not connected' ]
  [ ! -e "$BATS_TEST_TMPDIR/py.in" ]
}

@test "chat watcher: a reload for each change in its thread, none for others; started once, stopped on leaving" {
  # curl records what it would post to fzf
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${@: -1}" >> "%s/posts"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/curl"
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  local sock="$BATS_TEST_TMPDIR/s.sock"
  /usr/bin/python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$sock"
  # the monitor's lines (2026-01-01 to 01-04) as news: thread 11 four times, each newer, thread 99 once
  run timeout 3 bash -c 'source "$1/lib/core.sh"; fzx::require log; source "$2/source.sh"; kdeconnect::chat_watch phone1 11 "$3" 0' _ \
    "$FZX_REPO" "$KC" "$sock"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/posts")" -eq 4 ]
  # the reload ctrl-r does (with the loading prompt, when there is one)
  [[ "$(sort -u "$BATS_TEST_TMPDIR/posts")" == *"reload($FZX _cb source)" ]]
  [ "$(sort -u "$BATS_TEST_TMPDIR/posts" | wc -l)" -eq 1 ]
  # what a load's own request brings back is older than the watcher's start: no reload, so no reload loop;
  # one message newer than the rest, announced twice (sent, then delivered), reloads once
  rm -f "$BATS_TEST_TMPDIR/posts"
  run timeout 3 bash -c 'source "$1/lib/core.sh"; fzx::require log; source "$2/source.sh"; kdeconnect::chat_watch phone1 11 "$3"' _ \
    "$FZX_REPO" "$KC" "$sock"
  [ ! -e "$BATS_TEST_TMPDIR/posts" ]
  local now=$(( ${EPOCHREALTIME/./} / 1000 + 5000 )) news="$BATS_TEST_TMPDIR/news"
  { cat "$STUB_MONITOR"
    printf '{"member":"conversationUpdated","payload":{"type":"v","data":[{"type":"(isa(s)xiixixa(xsss))","data":[1,"new",[["5551230001"]],%s,1,0,11,20,1,[]]}]}}\n' "$now" "$now"
  } > "$news"
  STUB_MONITOR="$news" run timeout 3 bash -c 'source "$1/lib/core.sh"; fzx::require log; source "$2/source.sh"; kdeconnect::chat_watch phone1 11 "$3"' _ \
    "$FZX_REPO" "$KC" "$sock"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/posts")" -eq 1 ]
  # in a session: the source starts it in a group of its own, once
  chat_session
  local dir="$FZX_RUNTIME_DIR/sessions/$sid" pgid
  /usr/bin/python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$dir/fzf.sock"
  FZX_SESSION="$sid" "$FZX" _cb source > /dev/null
  pgid="$(cat "$dir/state/bg_pgid")"
  kill -0 -- "-$pgid"
  FZX_SESSION="$sid" "$FZX" _cb source > /dev/null
  [ "$(cat "$dir/state/bg_pgid")" = "$pgid" ]
  # leaving the screen ends it
  FZX_SESSION="$sid" run "$FZX" _cb nav escape
  local i
  for i in $(seq 30); do kill -0 -- "-$pgid" 2> /dev/null || break; sleep 0.1; done
  ! kill -0 -- "-$pgid" 2> /dev/null
  # FZX_KDECONNECT_CHAT_LIVE=0: none
  rm -f "$dir/state/bg_pgid"
  FZX_KDECONNECT_CHAT_LIVE=0 FZX_SESSION="$sid" "$FZX" _cb source > /dev/null
  [ ! -e "$dir/state/bg_pgid" ]
}

@test "sms preview: a phone that never says it is done still answers once its messages stop or are all there" {
  # the monitor's lines without conversationLoaded: done after a quiet second, asked once (waiting for the signal,
  # it used to ask again after 3s, then wait 3s more)
  sed -i '/conversationLoaded/d' "$STUB_MONITOR"
  run prev sms phone1/11 'Sam Lee'
  [[ "$output" == *'late one'* ]]
  [ "$(grep -c 'requestConversation' "$CALLS")" -eq 1 ]
  # nor waits once it has as many as it asked for, however long the quiet would be: the two first only
  : > "$CALLS"
  FZX_KDECONNECT_SMS_IDLE=60 FZX_KDECONNECT_SMS_MESSAGES=2 run timeout 30 bash -c "FZX_MODE=sms '$KC/preview.sh' phone1/11 'Sam Lee'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'from me'*'older'* && "$output" != *'late one'* ]]
  [ "$(grep -c 'requestConversation' "$CALLS")" -eq 1 ]
}

@test "sms: what contacts and messages hold is never on a command line, in a file or in the log" {
  grep -vq -- '--argjson contacts' "$KC/source.sh"
  run grep -c -- '--argjson contacts\|--arg contacts' "$KC/source.sh" "$KC/preview.sh"
  [[ "$output" != *:[1-9]* ]]
  stub_fzf
  run "$FZX" -m kdeconnect:sms --keep
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_LOG_LEVEL=debug FZX_SESSION="$sid" run "$FZX" _cb source
  [[ "$output" == *'Sam Lee'* ]]
  FZX_LOG_LEVEL=debug FZX_SESSION="$sid" run "$FZX" _cb preview phone1/11 'Sam Lee' ''
  [[ "$output" == *'late one'* ]]
  FZX_LOG_LEVEL=debug FZX_SESSION="$sid" run "$FZX" _cb notify copy 'Sam Lee'
  FZX_LOG_LEVEL=debug FZX_SESSION="$sid" run "$FZX" _cb action ping 'Sam Lee'
  # a failing callback logs at error, where arguments used to show
  FZX_LOG_LEVEL=debug FZX_SESSION="$sid" run "$FZX" _cb action dismiss 'Sam Lee'
  run grep -rlE 'Sam Lee|late one|on my way|hello all' "$FZX_STATE_DIR" "$FZX_CACHE_DIR" "$(session_dirs)"
  [ "$status" -ne 0 ]
  # copying a whole row and opening the actions menu hand over the row itself: not to the log either
  FZX_SESSION="$sid" run "$FZX" _cb notify copy-line 'Sam Lee 2026 hello all'
  FZX_SESSION="$sid" run "$FZX" _cb nav goto actions copy-line 'Sam Lee 2026 hello all' --fzx--
  run grep -rlE 'Sam Lee|hello all' "$FZX_STATE_DIR" "$FZX_CACHE_DIR"
  [ "$status" -ne 0 ]
  # and the log still says what ran
  grep -q 'cb preview rc=0' "$FZX_STATE_DIR/fzx.log"
}

@test "sms: copies as everywhere, ctrl-y the name and alt-y the row; the menu entry and a count" {
  stub_fzf
  run "$FZX" -m kdeconnect:sms
  [[ "$(fzf_bind alt-y)" == *'_cb notify copy-line {+}'* ]]
  [[ "$(fzf_bind ctrl-y)" == *"_cb notify copy {+3}"* ]]
  load_libs log config menu
  fzx::menu_entries kdeconnect "$KC"
  [[ " ${FZX_ENTRY_TARGETS[*]} " == *" kdeconnect:sms "* ]]
  [ "$(kdeconnect::summary kdeconnect:sms)" = "4 conversations, 1 unread" ]
  STUB_QUIET=1 run kdeconnect::summary kdeconnect:sms
  [ -z "$output" ]
  ! grep -q requestAll "$CALLS"
}

@test "FZX_LOG_ARGS: other modules still name their arguments" {
  stub_fzf
  run "$FZX" -m ps --keep
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" run "$FZX" _cb action nosuchaction naming-this-argument
  grep -q 'cb action nosuchaction naming-this-argument' "$FZX_STATE_DIR/fzx.log"
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
  for m in devices notifications commands sms; do
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
