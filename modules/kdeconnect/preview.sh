#!/usr/bin/env bash
# kdeconnect preview: a device's state, battery, certificate and plugins; a notification's whole text, read from
# the bus so a dismissed one says so; a command's line; a conversation's latest messages, newest first, held in memory
# only. An empty id is a row explaining an empty or unreadable list.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# kdeconnect::_row <label> <value>: one line, left out when there is no value
kdeconnect::_row() {
  [[ -n "$2" ]] || return 0
  printf '%s%-10s%s %s\n' "$_D" "$1" "$_R" "$2"
}

# kdeconnect::preview_device <id> <name> <details>
kdeconnect::preview_device() {
  local reach paired type charge charging state fp plugins
  IFS=$'\x1f' read -r reach paired type charge charging <<< "$3"
  state="not paired"
  [[ "$paired" == true ]] && state=away
  [[ "$reach" == true && "$paired" == true ]] && state=connected
  [[ "$reach" == true || "$paired" == true ]] || state=gone
  printf '%s%s%s  %s\n\n' "$_B" "$2" "$_R" "$state"
  kdeconnect::_row type "$type"
  kdeconnect::_row id "$1"
  if [[ -n "$charge" && "$charge" != - ]]; then
    kdeconnect::_row battery "$charge%$([[ "$charging" == true ]] && echo ' charging')"
  fi
  [[ "$reach" == true ]] || return 0
  # the device's own certificate, to compare with what it shows
  fp="$(kdeconnect::cli --encryption-info -d "$1" 2> /dev/null | sed -n 's/^SHA256 fingerprint of remote device certificate is: //p')"
  kdeconnect::_row sha256 "$fp"
  plugins="$(kdeconnect::plugins "$1" | paste -sd ' ')"
  [[ -z "$plugins" ]] || printf '\n%splugins%s\n%s\n' "$_B" "$_R" "$plugins"
}

# kdeconnect::preview_notification <device/notification>
kdeconnect::preview_notification() {
  local json
  json="$(kdeconnect::notification "${1%%/*}" "${1#*/}")"
  if [[ -z "$json" ]]; then
    printf '%sno longer on the device%s\n' "$_D" "$_R"
    return 0
  fi
  command jq -r --arg b "$_B" --arg d "$_D" --arg r "$_R" '
    def clean: (. // "") | tostring | gsub("\u001b\\[[0-9;:?=]*[A-Za-z]"; "") | gsub("[\u0001-\u0008\u000b-\u001f\u007f]+"; " ");
    "\($b)\(.title | clean)\($r)  \($d)\(.appName | clean)\($r)",
    (if .dismissable then empty else "\($d)cannot be dismissed\($r)" end),
    "", (.text | clean)' <<< "$json"
}

# kdeconnect::preview_command <device/command> <name> <command line>
kdeconnect::preview_command() {
  printf '%s%s%s\n\n' "$_B" "$2" "$_R"
  kdeconnect::_row runs "$3"
  kdeconnect::_row key "${1#*/}"
}

# kdeconnect::thread_messages <device> <thread> <limit>: busctl's JSON lines for the messages of a thread. They come as
# signals after asking, so the monitor starts first; it says nothing when it is ready, hence the pause, and a second
# request if nothing answers. In variables only, never a file. Fails when nothing came
kdeconnect::thread_messages() {
  local dev="$1" thread="$2" limit="$3" path iface="$KDECONNECT_IFACE.conversations" fd pid line got=() asked=1 rc
  path="$(kdeconnect::path "$dev")"
  exec {fd}< <(exec timeout "${FZX_KDECONNECT_SMS_WAIT:-8}" busctl --user monitor --json=short --match="type='signal',interface='$iface',path='$path'" 2> /dev/null)
  pid=$!
  # fzf ends a preview when the cursor moves: the monitor goes with it
  trap 'kill "$pid" 2> /dev/null' EXIT TERM
  sleep 0.25
  command busctl --user call "$KDECONNECT_BUS" "$path" "$iface" requestConversation xii "$thread" 0 "$limit" > /dev/null 2>&1
  while :; do
    IFS= read -r -t 3 -u "$fd" line
    rc=$?
    if ((rc > 128)); then
      ((asked < 2)) || break
      asked=2
      command busctl --user call "$KDECONNECT_BUS" "$path" "$iface" requestConversation xii "$thread" 0 "$limit" > /dev/null 2>&1
      continue
    fi
    ((rc == 0)) || break
    case "$line" in
      *'"member":"conversationLoaded"'*)
        [[ "$(command jq -r '.payload.data[0]' <<< "$line")" == "$thread" ]] && break
        ;;
      *'"member":"conversationUpdated"'*) got+=("$line") ;;
    esac
  done
  kill "$pid" 2> /dev/null
  trap - EXIT TERM
  exec {fd}<&-
  ((${#got[@]})) || return 1
  printf '%s\n' "${got[@]}"
}

# kdeconnect::preview_sms <device/thread> <who>
kdeconnect::preview_sms() {
  local dev="${1%%/*}" thread="${1#*/}" lines
  if ! lines="$(kdeconnect::thread_messages "$dev" "$thread" "${FZX_KDECONNECT_SMS_MESSAGES:-30}")"; then
    printf '%s%s%s\n\n%sno messages came back from the phone%s\n' "$_B" "$2" "$_R" "$_D" "$_R"
    return 0
  fi
  printf '%s%s%s\n\n' "$_B" "$2" "$_R"
  command jq -rs --slurpfile contacts <(kdeconnect::_contacts_json "$dev") --argjson thread "$thread" \
    --arg b "$_B" --arg d "$_D" --arg r "$_R" "$KDECONNECT_JQ"'
    [.[].payload.data[0].data | select(.[6] == $thread)] | unique_by(.[3], .[7]) | sort_by(-.[3]) | .[] |
    "\($d)\(when)\($r)  \(if .[4] == 2 then "you" elif (.[2] | length) > 1 then (.[2][0][0] | who | flat) else "" end)",
    ((.[1] | safe) as $t | if $t != "" then $t else empty end),
    (if (.[9] | length) > 0 then "\($d)(\(.[9] | length) attachment\(if (.[9] | length) == 1 then "" else "s" end))\($r)" else empty end),
    ""' <<< "$lines"
}

# kdeconnect::preview <id> <name> <details>
kdeconnect::preview() {
  local _B=$'\e[1m' _D=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" _R=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && _B="" _D="" _R=""
  if [[ -z "${1:-}" ]]; then
    printf '%s\n' "${2:-}"
    return 0
  fi
  case "${FZX_MODE:-devices}" in
    devices) kdeconnect::preview_device "$1" "${2:-}" "${3:-}" ;;
    notifications) kdeconnect::preview_notification "$1" ;;
    commands) kdeconnect::preview_command "$1" "${2:-}" "${3:-}" ;;
    sms) kdeconnect::preview_sms "$1" "${2:-}" ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" kdeconnect
  kdeconnect::preview "$@"
}
