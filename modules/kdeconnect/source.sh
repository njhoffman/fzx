#!/usr/bin/env bash
# kdeconnect source: "id<TAB>display<TAB>name<TAB>details" per mode, the name being what ctrl-y copies.
#   devices        id: the device's. Details: reachable paired type charge charging (0x1f-separated)
#   notifications  id: DEVICE/NOTIFICATION. Read from the bus, none of it kept
#   commands       id: DEVICE/COMMAND. Details: the command line
#   sms            id: DEVICE/THREAD, name: who it is with (sort recent or name). Read from the bus, none of it kept
# A message is the D-Bus struct (event, body, addresses, date, type, read, thread, uid, sub, attachments): type 1 came
# in, 2 went out; read 0 is unread; addresses are one-field structs.
# A list with nothing to show, or that cannot be read, is a row with an empty id and the message as its name.
# What a device sends is text from elsewhere: control characters never reach the screen.

KDECONNECT_BUS=org.kde.kdeconnect
KDECONNECT_IFACE=org.kde.kdeconnect.device

# kdeconnect::cli <args...>: kdeconnect-cli, not waiting forever for a device
kdeconnect::cli() { timeout "${FZX_KDECONNECT_TIMEOUT:-15}" kdeconnect-cli "$@"; }

# kdeconnect::path <device>: its object on the bus
kdeconnect::path() { printf '/modules/kdeconnect/devices/%s' "$1"; }

# kdeconnect::get <device> <property...>: its values, one per line, as busctl prints them
kdeconnect::get() {
  local dev="$1"
  shift
  command busctl --user get-property "$KDECONNECT_BUS" "$(kdeconnect::path "$dev")" "$KDECONNECT_IFACE" "$@" 2> /dev/null
}

# kdeconnect::battery <device>: "PERCENT CHARGING" (true or false); nothing when it does not say
kdeconnect::battery() {
  command busctl --user get-property "$KDECONNECT_BUS" "$(kdeconnect::path "$1")/battery" "$KDECONNECT_IFACE.battery" charge isCharging 2> /dev/null |
    awk '{ print $2 }' | paste -sd ' '
}

# kdeconnect::plugins <device>: the plugins it has loaded, one per line, without their prefix
kdeconnect::plugins() {
  command busctl --user call "$KDECONNECT_BUS" "$(kdeconnect::path "$1")" "$KDECONNECT_IFACE" loadedPlugins 2> /dev/null |
    tr ' ' '\n' | tr -d '"' | sed -n 's/^kdeconnect_//p'
}

# kdeconnect::connected: "id name" of the paired, reachable devices
kdeconnect::connected() { kdeconnect::cli -a --id-name-only 2> /dev/null | grep -E '^[^ ]+ '; }

# kdeconnect::notification_ids <device>: the ids of its notifications, one per line
kdeconnect::notification_ids() {
  command busctl --user --json=short call "$KDECONNECT_BUS" "$(kdeconnect::path "$1")/notifications" \
    "$KDECONNECT_IFACE.notifications" activeNotifications 2> /dev/null | command jq -r '.data[0][]?'
}

# kdeconnect::notification <device> <id>: its properties as JSON, each value at .NAME
kdeconnect::notification() {
  command busctl --user --json=short call "$KDECONNECT_BUS" "$(kdeconnect::path "$1")/notifications/$2" \
    org.freedesktop.DBus.Properties GetAll s "$KDECONNECT_IFACE.notifications.notification" 2> /dev/null |
    command jq -c '.data[0] | map_values(.data)'
}

# kdeconnect::conversations <device>: the newest message of each thread the daemon knows, as busctl's JSON
kdeconnect::conversations() {
  command busctl --user --json=short call "$KDECONNECT_BUS" "$(kdeconnect::path "$1")" "$KDECONNECT_IFACE.conversations" activeConversations 2> /dev/null
}

# kdeconnect::_ask_threads <device>: ask the phone for its threads; the answer arrives in the daemon by itself
kdeconnect::_ask_threads() {
  command busctl --user call "$KDECONNECT_BUS" "$(kdeconnect::path "$1")" "$KDECONNECT_IFACE.conversations" requestAllConversationThreads > /dev/null 2>&1
}

# kdeconnect::_threads <device>: its threads: at once when the daemon has them, else after the first sync settles
# (the same count twice) or FZX_KDECONNECT_SMS_WAIT seconds
kdeconnect::_threads() {
  local out n=0 last=-1 i
  kdeconnect::_ask_threads "$1"
  out="$(kdeconnect::conversations "$1")"
  n="$(command jq '.data[0] | length' <<< "$out" 2> /dev/null)"
  if ((${n:-0} == 0)); then
    for ((i = 0; i < ${FZX_KDECONNECT_SMS_WAIT:-8}; i++)); do
      sleep 1
      out="$(kdeconnect::conversations "$1")"
      n="$(command jq '.data[0] | length' <<< "$out" 2> /dev/null)"
      ((${n:-0} > 0 && ${n:-0} == last)) && break
      last="${n:-0}"
    done
  fi
  printf '%s\n' "$out"
}

# kdeconnect::contacts <device>: "DIGITS<TAB>NAME" from the vCards the contacts plugin syncs, the last 10 digits of
# each number so +1 555 and 555 match
kdeconnect::contacts() {
  local dir="${XDG_DATA_HOME:-$HOME/.local/share}/kpeoplevcard/kdeconnect-$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -name '*.vcf' -exec awk '
    function flush(  i) { for (i = 1; i <= n; i++) if (fn != "") print tel[i] "\t" fn; n = 0; fn = "" }
    FNR == 1 { flush() }
    { sub(/\r$/, "") }
    /^FN[:;]/ { fn = $0; sub(/^[^:]*:/, "", fn); gsub(/\\/, "", fn); gsub(/\t/, " ", fn) }
    /^TEL[:;]/ { t = $0; sub(/^[^:]*:/, "", t); gsub(/[^0-9]/, "", t); if (t != "") tel[++n] = substr(t, length(t) > 10 ? length(t) - 9 : 1) }
    END { flush() }' {} +
}

# KDECONNECT_JQ: what the sms list and preview share: who an address is, and text made safe to draw. $contacts arrives
# through a file descriptor, never on a command line, where any user on this machine could read it
# shellcheck disable=SC2016  # jq's variables
KDECONNECT_JQ='
  def who: tostring as $a | ($a | gsub("[^0-9]"; "") | .[-10:]) as $k | ($contacts[0][$k] // $a);
  def safe: (. // "") | tostring | gsub("\u001b\\[[0-9;:?=]*[A-Za-z]"; "") | gsub("[\u0001-\u0008\u000b-\u001f\u007f]+"; " ");
  def flat: safe | gsub("[\t\n]+"; " ");
  def names: map(.[0] | who | flat);
  def people: names | if length > 3 then (.[0:2] | join(", ")) + " +\(length - 2)" else join(", ") end;
  def when: (.[3] / 1000 | strflocaltime("%Y-%m-%d %H:%M"));
'

# kdeconnect::_contacts_json <device>: the contacts as one JSON object
kdeconnect::_contacts_json() {
  kdeconnect::contacts "$1" | command jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

# kdeconnect::color <name> <default SGR>: an escape sequence from FZX_COLORS
kdeconnect::color() { printf '\e[%sm' "${FZX_COLORS[$1]:-$2}"; }

# kdeconnect::note <text>: a row for a list with nothing to show
kdeconnect::note() { printf '\t%s%s\e[0m\t%s\t\n' "$(kdeconnect::color dim '38;5;244')" "$1" "$1"; }

# kdeconnect::clean: stdin without control characters: names and text come from the device
kdeconnect::clean() { LC_ALL=C sed -E $'s/\x1b\\[[0-9;:?=]*[A-Za-z]//g' | LC_ALL=C tr -d '\000-\010\013-\037\177'; }

kdeconnect::source() {
  local m
  for m in kdeconnect-cli busctl jq; do
    command -v "$m" > /dev/null || { printf 'kdeconnect: the %s command is not installed\n' "$m" >&2; return 2; }
  done
  case "${FZX_MODE:-devices}" in
    devices) kdeconnect::_source_devices ;;
    notifications) kdeconnect::_source_notifications ;;
    commands) kdeconnect::_source_commands ;;
    sms) kdeconnect::_source_sms ;;
    *)
      printf 'kdeconnect: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

kdeconnect::_source_devices() {
  local out err id name reach paired type battery charge charging sort="${FZX_SORT:-state}" hl="${FZX_COLORS[sorted]:-4}" rows=""
  fzx::require icons header
  fzx::icon_vars running stopped
  fzx::header_print 1 "$([[ "$sort" == name ]] && echo NAME || echo STATE)" "" 1 0 NAME 28 0 TYPE 8 0 STATE 11 0 BATTERY 0 0
  err="$(mktemp)" || return 2
  if ! out="$(kdeconnect::cli -l --id-name-only 2> "$err")"; then
    printf 'kdeconnect: cannot list devices: %s\n' "$(head -1 "$err")" >&2
    kdeconnect::note "cannot list devices: $(head -1 "$err")"
    rm -f -- "$err"
    return 1
  fi
  rm -f -- "$err"
  out="$(grep -E '^[^ ]+ ' <<< "$out" | kdeconnect::clean)"
  if [[ -z "$out" ]]; then
    kdeconnect::note "no devices known: is KDE Connect open on the other device? (alt-c looks again)"
    return 0
  fi
  while read -r id name; do
    { read -r _ reach; read -r _ paired; read -r _ type; } < <(kdeconnect::get "$id" isReachable isPaired type)
    type="${type//\"/}"
    charge="-" charging=false
    if [[ "$reach" == true ]]; then
      battery="$(kdeconnect::battery "$id")"
      [[ -z "$battery" ]] || { charge="${battery% *}" charging="${battery#* }"; }
    fi
    rows+="$id"$'\t'"$name"$'\t'"${reach:-false}"$'\t'"${paired:-false}"$'\t'"${type:--}"$'\t'"$charge"$'\t'"$charging"$'\n'
  done <<< "$out"
  printf '%s' "$rows" |
    awk -F'\t' "${FZX_ICON_VARS[@]}" -v sort="$sort" -v hl=$'\e['"${hl}m" -v rst=$'\e[0m' -v low="${FZX_KDECONNECT_BATTERY_LOW:-20}" \
      -v name="$(kdeconnect::color kdeconnect_name '1;38;5;111')" -v on="$(kdeconnect::color kdeconnect_connected '38;5;114')" \
      -v away="$(kdeconnect::color kdeconnect_away '38;5;250')" -v lowc="$(kdeconnect::color kdeconnect_low '38;5;203')" \
      -v dim="$(kdeconnect::color dim '38;5;244')" '
      function cell(color, text, w, sorted) { return sorted ? color hl text rst sprintf("%" (w - length(text) > 0 ? w - length(text) : 0) "s", "") : color sprintf("%-" w "s", text) rst }
      { shown = length($2) > 28 ? substr($2, 1, 27) "…" : $2
        if ($3 == "true" && $4 == "true") { state = "connected"; c = on; i = icon_running; rank = 0 }
        else if ($4 == "true") { state = "away"; c = away; i = icon_stopped; rank = 1 }
        else if ($3 == "true") { state = "not paired"; c = away; i = icon_stopped; rank = 2 }
        else { state = "gone"; c = dim; i = icon_stopped; rank = 3 }
        if (i == "") i = "●"
        bat = "-"
        if ($6 != "-") bat = ($6 + 0 <= low + 0 && $7 != "true" ? lowc : "") $6 "%" rst ($7 == "true" ? " charging" : "")
        key = sort == "name" ? tolower($2) : rank
        printf "%s\t%s\t%s%s%s %s %-8s %s %s\t%s\t%s\037%s\037%s\037%s\037%s\n", key, $1, c, i, rst, cell(name, shown, 28, sort == "name"), $5,
          cell(c, state, 11, sort == "state"), bat, $2, $3, $4, $5, $6, $7 }' |
    LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
}

kdeconnect::_source_notifications() {
  local id name nid any=0 app title
  app="$(kdeconnect::color kdeconnect_name '1;38;5;111')" title="$(kdeconnect::color dim '38;5;244')"
  while read -r id name; do
    [[ -n "$id" ]] || continue
    any=1
    while read -r nid; do
      [[ -n "$nid" ]] || continue
      kdeconnect::notification "$id" "$nid" |
        command jq -r --arg id "$id/$nid" --arg app "$app" --arg dim "$title" --arg r $'\e[0m' '
          def flat: (. // "") | tostring | gsub("\u001b\\[[0-9;:?=]*[A-Za-z]"; "") | gsub("[\u0001-\u001f\u007f]+"; " ");
          def pad($w): if length > $w then .[0:$w-1] + "…" else . + (" " * ($w - length)) end;
          [$id, "\($app)\(.appName | flat | pad(16))\($r) \(.title | flat | pad(28)) \($dim)\(.text | flat)\($r)", (.title | flat)] | @tsv' |
        sed 's/\\\\/\\/g'
      any=2
    done < <(kdeconnect::notification_ids "$id")
  done < <(kdeconnect::connected)
  case "$any" in
    0) kdeconnect::note "no device connected" ;;
    1) kdeconnect::note "no notifications" ;;
  esac
}

kdeconnect::_source_commands() {
  local id name key label cmd any=0 color
  color="$(kdeconnect::color kdeconnect_name '1;38;5;111')"
  while read -r id name; do
    [[ -n "$id" ]] || continue
    # phones do not offer commands; asking one only prints nothing
    kdeconnect::plugins "$id" | grep -qx remotecommands || continue
    while IFS= read -r line; do
      key="${line%%: *}" line="${line#*: }" label="${line%%: *}" cmd="${line#*: }"
      [[ -n "$key" ]] || continue
      any=1
      printf '%s/%s\t%s%-28s\e[0m %s\t%s\t%s\n' "$id" "$key" "$color" "$label" "$cmd" "$label" "$cmd"
    done < <(kdeconnect::cli --list-commands -d "$id" 2> /dev/null | kdeconnect::clean)
  done < <(kdeconnect::connected)
  ((any)) || kdeconnect::note "no connected device offers commands"
}

kdeconnect::_source_sms() {
  local id name sort="${FZX_SORT:-recent}" hl="${FZX_COLORS[sorted]:-4}"
  fzx::require header
  fzx::header_print 1 "$([[ "$sort" == name ]] && echo NAME || echo DATE)" "" 1 0 NAME 26 0 DATE 16 0 LAST 0 0
  while read -r id name; do
    [[ -n "$id" ]] || continue
    kdeconnect::plugins "$id" | grep -qx sms || continue
    kdeconnect::_threads "$id" |
      command jq -r --slurpfile contacts <(kdeconnect::_contacts_json "$id") --arg dev "$id" --arg sort "$sort" --arg hl $'\e['"${hl}m" --arg r $'\e[0m' \
        --arg name "$(kdeconnect::color kdeconnect_name '1;38;5;111')" --arg dim "$(kdeconnect::color dim '38;5;244')" \
        --arg new "$(kdeconnect::color kdeconnect_connected '38;5;114')" "$KDECONNECT_JQ"'
        def pad($w): if length > $w then .[0:$w-1] + "…" else . + (" " * ($w - length)) end;
        .data[0][]?.data |
        (.[2] | people) as $who | (.[4] == 1 and .[5] == 0) as $unread | (when) as $date |
        ((if .[4] == 2 then "you: " else "" end) + ((.[1] | flat) as $b | if $b != "" then $b elif (.[9] | length) > 0 then "(attachment)" else "" end)) as $last |
        [(if $sort == "name" then ($who | ascii_downcase) else (9999999999999 - .[3] | tostring | ("0" * (16 - length)) + .) end),
         "\($dev)/\(.[6])",
         "\(if $unread then "\($new)●\($r)" else " " end) \($name)\(if $sort == "name" then $hl else "" end)\($who | pad(26))\($r) \($dim)\(if $sort == "recent" then $hl else "" end)\($date)\($r) \($last)",
         $who] | @tsv' | sed 's/\\\\/\\/g'
  done < <(kdeconnect::connected) | LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2- | kdeconnect::_or_note
}

# kdeconnect::_or_note: stdin, or a row saying why the sms list is empty
kdeconnect::_or_note() {
  local line got=0
  while IFS= read -r line; do
    got=1
    printf '%s\n' "$line"
  done
  ((got)) && return 0
  if [[ -n "$(kdeconnect::connected)" ]]; then
    kdeconnect::note "no conversations yet: the phone may still be syncing (ctrl-r reads again)"
  else
    kdeconnect::note "no device connected"
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" kdeconnect
  kdeconnect::source "$@"
}
