#!/usr/bin/env bash
# kdeconnect actions on the selected ids of the current mode. A device that is away, or lacks the plugin an
# action needs, is named instead of failing silently. Nothing typed here (SMS, keys, text) goes into a history
# file, a logged command line or the log. Rows with an empty id (an empty or unreadable list) are skipped.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# kdeconnect::_not_here <action> <mode>: refuse an action the mode has no use for
kdeconnect::_not_here() {
  printf 'kdeconnect: %s does not apply to %s\n' "$1" "$2" >&2
  return 2
}

# kdeconnect::_ready <device> [plugin]: true when it is connected and has the plugin; else says why
kdeconnect::_ready() {
  local reach name
  { read -r _ reach; read -r _ name; } < <(kdeconnect::get "$1" isReachable name)
  name="${name//\"/}"
  if [[ "$reach" != true ]]; then
    printf 'kdeconnect: %s is not connected\n' "${name:-$1}" >&2
    return 1
  fi
  [[ -z "${2:-}" ]] || kdeconnect::plugins "$1" | grep -qx "$2" || {
    printf 'kdeconnect: %s does not support this (no %s plugin)\n' "$name" "$2" >&2
    return 1
  }
}

# kdeconnect::_each <plugin> <device...> -- <cli args...>: the request for each device that can take it
kdeconnect::_each() {
  local plugin="$1" devs=() d rc=0
  shift
  while (($#)) && [[ "$1" != -- ]]; do
    devs+=("$1")
    shift
  done
  shift
  for d in "${devs[@]}"; do
    if kdeconnect::_ready "$d" "$plugin"; then
      kdeconnect::cli -d "$d" "$@" || rc=$?
    else
      rc=1
    fi
  done
  return "$rc"
}

# kdeconnect::_report <rc>: show a failure until a key is pressed; execute would otherwise wipe it at once
kdeconnect::_report() {
  (($1 == 0)) && return 0
  if [[ -t 1 ]]; then
    printf '\n\e[31mfailed (exit %s)\e[0m, press a key ' "$1"
    IFS= read -rsn1 < /dev/tty || :
  fi
  return "$1"
}

# kdeconnect::_on_terminal: stderr to the terminal for the rest of this process: fzx sends an action's stderr to its
# log, where the reason a device refused what was just typed would not be seen
kdeconnect::_on_terminal() { if [[ -t 1 ]]; then exec 2>&1; fi; }

# kdeconnect::_share_target <text> <var>: a URL as it is, a local path made absolute; false when it does not exist
kdeconnect::_share_target() {
  local _t="$1"
  [[ "$_t" == \~/* ]] && _t="$HOME/${_t#\~/}"
  if [[ "$_t" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]]; then
    printf -v "$2" '%s' "$_t"
    return 0
  fi
  [[ -e "$_t" ]] || { printf 'kdeconnect: no such file: %s\n' "$_t" >&2; return 1; }
  printf -v "$2" '%s' "$(readlink -f -- "$_t")"
}

# kdeconnect::_sms <device>: asks for the number and the message, shows them, sends on y
kdeconnect::_sms() {
  local number message name
  kdeconnect::_on_terminal
  kdeconnect::_ready "$1" sms || return
  name="$(kdeconnect::get "$1" name | sed -E 's/^s "(.*)"$/\1/')"
  {
    fzx::tty_read -r -e -p $'\e[1mSMS to:\e[0m ' number || return 0
    [[ -n "$number" ]] || return 0
    fzx::tty_read -r -e -p $'\e[1mmessage:\e[0m ' message || return 0
    [[ -n "$message" ]] || return 0
  } < "${FZX_KDECONNECT_TTY:-/dev/tty}"
  number="${number//[ ()-]/}"
  if ! [[ "$number" =~ ^\+?[0-9]{3,}$ ]]; then
    printf 'kdeconnect: not a phone number: %s\n' "$number" >&2
    return 1
  fi
  fzx::require builtin
  fzx::confirm "send from $name to $number: \"$message\"" || return 0
  kdeconnect::cli -d "$1" --destination "$number" "--send-sms=$message"
}

# kdeconnect::reply <device> <thread>: send stdin as a message in the thread (replyToConversation, which takes
# groups too). The text goes to python on stdin, never on a command line, where any user here could read it
kdeconnect::reply() {
  timeout "${FZX_KDECONNECT_TIMEOUT:-15}" python3 -c '
import sys
import dbus
device = dbus.SessionBus().get_object("org.kde.kdeconnect", "/modules/kdeconnect/devices/" + sys.argv[1])
conversations = dbus.Interface(device, "org.kde.kdeconnect.device.conversations")
conversations.replyToConversation(dbus.Int64(int(sys.argv[2])), sys.stdin.read(), dbus.Array([], signature="v"))
' "$1" "$2"
}

# kdeconnect::transform <chat DEVICE/THREAD | send | chat-watch>
#   chat        enter in the sms list: the thread's chat screen, a child session (esc returns to the list)
#   send        enter in the chat: the first press asks in the header, a second one on the same text sends it
#   chat-watch  the chat's watcher (kdeconnect::chat_watch_start runs it in a process group of its own)
kdeconnect::transform() {
  case "${1:-}" in
    chat) kdeconnect::_transform_chat "${2:-}" ;;
    send) kdeconnect::_transform_send ;;
    chat-watch)
      fzx::session_args
      kdeconnect::chat_args "${FZX_ARGS[@]}" || return
      kdeconnect::chat_watch "$KDECONNECT_DEV" "$KDECONNECT_THREAD" "$FZX_SESSION_DIR/fzf.sock"
      ;;
    *)
      printf 'kdeconnect: unknown transform: %s\n' "${1:-}" >&2
      return 2
      ;;
  esac
}

kdeconnect::_transform_chat() {
  local dev thread
  # a row explaining an empty list has no thread
  kdeconnect::chat_id "$1" dev thread || { printf 'bell'; return 0; }
  fzx::require nav
  fzx::nav goto kdeconnect:chat --thread "$1"
}

# kdeconnect::_transform_send: the query, FZF_QUERY (never an argument). state/chat_pending holds a checksum of the
# text the header asked about, not the text
kdeconnect::_transform_send() {
  local text="${FZF_QUERY:-}" sum pending="" who err
  fzx::session_args
  kdeconnect::chat_args "${FZX_ARGS[@]}" || return
  [[ -n "${text//[[:space:]]/}" ]] || { printf 'bell'; return 0; }
  sum="$(printf '%s' "$text" | md5sum)"
  sum="${sum%% *}"
  fzx::state_get chat_pending pending || pending=""
  who="$(kdeconnect::thread_who "$KDECONNECT_DEV" "$KDECONNECT_THREAD")"
  who="${who:-thread $KDECONNECT_THREAD}"
  if [[ "$pending" != "$sum" ]]; then
    fzx::state_set chat_pending "$sum"
    printf 'change-header:%s' "$(printf 'send to %s: "%s"?  enter sends it, typing cancels' "$who" "$text" | fzx::glyphs_plain)"
    return 0
  fi
  fzx::state_set chat_pending ""
  # (printf, not a here-string, which would add a newline to the message)
  if err="$(kdeconnect::_ready "$KDECONNECT_DEV" sms 2>&1 &&
    printf '%s' "$text" | kdeconnect::reply "$KDECONNECT_DEV" "$KDECONNECT_THREAD" 2>&1)"; then
    printf 'clear-query+change-header:%s' "sent to $who; it shows here when the phone reports it"
  else
    err="${err//$'\n'/ }"
    printf 'bell+change-header:%s' "not sent: ${err:-the phone did not take it}"
  fi
}

# kdeconnect::action <action> <id...>
kdeconnect::action() {
  local action="${1:-}" mode="${FZX_MODE:-devices}" id ids=() rc=0 line
  shift
  for id in "$@"; do [[ -z "$id" ]] || ids+=("$id"); done
  # needs no row: looks for every device
  if [[ "$action" == refresh ]]; then
    kdeconnect::cli --refresh
    return
  fi
  ((${#ids[@]})) || return 0
  case "$action:$mode" in
    ping:devices) kdeconnect::_each ping "${ids[@]}" -- --ping || rc=$? ;;
    ring:devices) kdeconnect::_each findmyphone "${ids[@]}" -- --ring || rc=$? ;;
    clipboard:devices) kdeconnect::_each clipboard "${ids[@]}" -- --send-clipboard || rc=$? ;;
    lock:devices) kdeconnect::_each lockdevice "${ids[@]}" -- --lock || rc=$? ;;
    unlock:devices) kdeconnect::_each lockdevice "${ids[@]}" -- --unlock || rc=$? ;;
    pair:devices) for id in "${ids[@]}"; do kdeconnect::cli -d "$id" --pair || rc=$?; done ;;
    unpair:devices) for id in "${ids[@]}"; do kdeconnect::cli -d "$id" --unpair || rc=$?; done ;;
    share:devices)
      local target
      kdeconnect::_on_terminal
      fzx::tty_read -r -e -p $'\e[1mfile or URL:\e[0m ' line < "${FZX_KDECONNECT_TTY:-/dev/tty}" || return 0
      [[ -n "$line" ]] || return 0
      if kdeconnect::_share_target "$line" target; then
        kdeconnect::_each share "${ids[@]}" -- "--share=$target" || rc=$?
      else
        rc=1
      fi
      kdeconnect::_report "$rc" || :
      ;;
    text:devices | keys:devices)
      kdeconnect::_on_terminal
      fzx::tty_read -r -e -p $'\e[1mtext:\e[0m ' line < "${FZX_KDECONNECT_TTY:-/dev/tty}" || return 0
      [[ -n "$line" ]] || return 0
      if [[ "$action" == text ]]; then
        kdeconnect::_each share "${ids[@]}" -- "--share-text=$line" || rc=$?
      else
        kdeconnect::_each remotekeyboard "${ids[@]}" -- "--send-keys=$line" || rc=$?
      fi
      kdeconnect::_report "$rc" || :
      ;;
    sms:devices)
      kdeconnect::_sms "${ids[0]}" || rc=$?
      kdeconnect::_report "$rc" || :
      ;;
    dismiss:notifications)
      for id in "${ids[@]}"; do
        command busctl --user call "$KDECONNECT_BUS" "$(kdeconnect::path "${id%%/*}")/notifications/${id#*/}" \
          "$KDECONNECT_IFACE.notifications.notification" dismiss || rc=$?
      done
      ;;
    run:commands)
      for id in "${ids[@]}"; do
        kdeconnect::_ready "${id%%/*}" remotecommands && kdeconnect::cli -d "${id%%/*}" --execute-command "${id#*/}" || rc=$?
      done
      ;;
    ping:* | ring:* | clipboard:* | lock:* | unlock:* | pair:* | unpair:* | share:* | text:* | keys:* | sms:* | dismiss:* | run:*)
      kdeconnect::_not_here "$action" "$mode" || rc=$?
      ;;
    *)
      printf 'kdeconnect: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" kdeconnect
  kdeconnect::action "$@"
}
