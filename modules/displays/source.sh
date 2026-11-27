#!/usr/bin/env bash
# displays source. Modes from $FZX_MODE:
#   outputs  "name<TAB>state<TAB>display": xrandr's outputs, on first, then off, then (toggle all) the
#            disconnected ones; state is on, off or disconnected
#   modes    "WxH<TAB>rate<TAB>display": one output's modes (--output NAME), each rate its own row
#   profiles "name<TAB>kind<TAB>display": displayd's profiles (`displayd list`), kind config or saved

# displays::args [module args...]: DISPLAYS_OUTPUT from --output NAME
displays::args() {
  DISPLAYS_OUTPUT=""
  while (($#)); do
    case "$1" in
      --output)
        DISPLAYS_OUTPUT="${2:-}"
        shift
        (($#)) && shift
        ;;
      *) shift ;;
    esac
  done
}

# displays::outputs: xrandr's outputs as "name<TAB>state<TAB>primary<TAB>mode<TAB>rate<TAB>pos<TAB>rotation<TAB>preferred",
# state on (a mode on screen), off (connected, no mode) or disconnected; mode, rate and pos (+X+Y) of the
# mode on screen, the preferred mode (+) for any connected one
displays::outputs() {
  command xrandr --query 2> /dev/null | awk '
    function flush() { if (name != "") printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", name, state, primary, mode, rate, pos, rot, pref }
    /^[^ ]+ (connected|disconnected)/ {
      flush()
      name = $1; state = $2 == "connected" ? "off" : "disconnected"; primary = ""; mode = ""; rate = ""; pos = ""; rot = "normal"; pref = ""
      for (i = 3; i <= NF && $i !~ /^\(/; i++) {
        if ($i == "primary") primary = "primary"
        else if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) { state = "on"; split($i, g, "+"); mode = g[1]; pos = "+" g[2] "+" g[3] }
        else if ($i ~ /^(left|right|inverted)$/) rot = $i
      }
      next
    }
    /^   [0-9]+x[0-9]+/ && name != "" {
      m = $1
      for (i = 2; i <= NF; i++) {
        t = $i
        if (t ~ /^[0-9.]+/) { r = t; gsub(/[^0-9.]/, "", r) }
        if (t ~ /\*/) rate = r
        if (t ~ /\+/ && pref == "") pref = m
      }
    }
    END { flush() }'
}

# displays::modes <output>: the output's modes as "WxH<TAB>rate<TAB>marks", marks "*" (on screen) and "+"
# (preferred), in xrandr's order, each mode and rate once
displays::modes() {
  command xrandr --query 2> /dev/null | awk -v out="$1" '
    /^[^ ]+ (connected|disconnected)/ { on = $1 == out; next }
    on && /^   [0-9]+x[0-9]+/ {
      m = $1; n = 0
      for (i = 2; i <= NF; i++) {
        t = $i
        if (t ~ /^[0-9.]+/) { r[++n] = t; gsub(/[^0-9.]/, "", r[n]); k[n] = t; sub(/^[0-9.]+/, "", k[n]) }
        else if (n) k[n] = k[n] t
      }
      # one row a mode and rate: xrandr lists a rate again for another modeline, which --rate cannot pick
      for (i = 1; i <= n; i++) {
        key = m "\t" r[i]
        if (!(key in mark)) order[++rows] = key
        mark[key] = mark[key] (k[i] ~ /\*/ ? "*" : "") (k[i] ~ /\+/ ? "+" : "")
      }
    }
    on && /^[^ ]/ { on = 0 }
    END { for (i = 1; i <= rows; i++) { f = mark[order[i]]; printf "%s\t%s%s\n", order[i], (f ~ /\*/ ? "*" : ""), (f ~ /\+/ ? "+" : "") } }'
}

# displays::labels <var>: the assoc var filled with displayd's names for the outputs (`displayd monitors`:
# "OUTPUT  FINGERPRINT  KIND  MODE  NAME"), empty without displayd
displays::labels() {
  local -n _dl_out="$1"
  local _dl_o _dl_fp _dl_kind _dl_mode _dl_name
  command -v "${FZX_DISPLAYS_DISPLAYD:-displayd}" > /dev/null || return 0
  while read -r _dl_o _dl_fp _dl_kind _dl_mode _dl_name; do
    [[ -n "$_dl_o" && -n "$_dl_name" ]] && _dl_out["$_dl_o"]="$_dl_name"
  done < <(command "${FZX_DISPLAYS_DISPLAYD:-displayd}" monitors 2> /dev/null)
}

# displays::profiles: `displayd list` as "name<TAB>kind<TAB>marks", marks * (the default for what is
# connected) and + (fits it)
displays::profiles() {
  command -v "${FZX_DISPLAYS_DISPLAYD:-displayd}" > /dev/null || return 0
  command "${FZX_DISPLAYS_DISPLAYD:-displayd}" list 2> /dev/null | awk '{
    marks = substr($0, 1, 2); gsub(/ /, "", marks)
    line = substr($0, 4)
    kind = line; sub(/.*\[/, "", kind); sub(/\].*/, "", kind)
    name = line; sub(/  \[[a-z]+\] *$/, "", name)
    if (name != "") printf "%s\t%s\t%s\n", name, kind, marks
  }'
}

# displays::source [module args...]
displays::source() {
  displays::args "$@"
  local on=$'\e['"${FZX_COLORS[displays_on]:-38;5;114}m" dim=$'\e['"${FZX_COLORS[displays_dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && on="" dim="" r=""
  case "${FZX_MODE:-outputs}" in
    outputs)
      local -A labels=()
      local all=0 name state primary mode rate pos rot pref
      displays::labels labels
      [[ " ${FZX_TOGGLES:-} " == *" all "* ]] && all=1
      # fields split on \x1f: tabs, being whitespace to read, would merge the empty ones
      displays::outputs | awk -F'\t' -v OFS=$'\x1f' '{ $1 = $1; print ($2 == "on" ? 0 : $2 == "off" ? 1 : 2), $0 }' |
        sort -t$'\x1f' -k1,1n -s | cut -d$'\x1f' -f2- |
        while IFS=$'\x1f' read -r name state primary mode rate pos rot pref; do
          [[ "$state" == disconnected ]] && ((!all)) && continue
          local c="" what mark=○
          case "$state" in
            on)
              c="$on" mark=● what="$mode@$rate $pos"
              [[ "$rot" != normal ]] && what+=" $rot"
              ;;
            off) what="off${pref:+ (preferred $pref)}" ;;
            *) c="$dim" what="disconnected" ;;
          esac
          printf '%s\t%s\t%s%s %-8s%s %-22s %s%s%s%s\n' "$name" "$state" "$c" "$mark" "$name" "$r" "${labels[$name]:-}" \
            "$c" "$what" "${primary:+  primary}" "$r"
        done
      ;;
    modes)
      [[ -n "$DISPLAYS_OUTPUT" ]] || { printf 'displays: modes needs --output NAME\n' >&2; return 2; }
      displays::modes "$DISPLAYS_OUTPUT" | while IFS=$'\t' read -r mode rate marks; do
        local c=""
        [[ "$marks" == *'*'* ]] && c="$on"
        printf '%s\t%s\t%s%-11s %7s Hz%s  %s\n' "$mode" "$rate" "$c" "$mode" "$rate" "$r" \
          "$([[ "$marks" == *'*'* ]] && printf 'on screen  ')$([[ "$marks" == *'+'* ]] && printf 'preferred')"
      done
      ;;
    profiles)
      displays::profiles | while IFS=$'\t' read -r name kind marks; do
        local c="" note=""
        [[ "$marks" == *'+'* ]] || c="$dim"
        [[ "$marks" == *'*'* ]] && note="default here"
        [[ "$marks" == *'+'* && -z "$note" ]] && note="fits"
        printf '%s\t%s\t%s%-60s%s %s%-7s%s %s\n' "$name" "$kind" "$c" "$name" "$r" "$dim" "$kind" "$r" "$note"
      done
      ;;
    *)
      printf 'displays: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" displays
  displays::source "$@"
}
