#!/usr/bin/env bash
# displays preview: an output's state, monitor and modes; a mode's xrandr command; a displayd profile's
# definition (config.toml's table, or the saved layout in displayd's state)

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# displays::preview <id> [field 2] [module args...]
displays::preview() {
  local id="${1:-}" b=$'\e[1m' dim=$'\e['"${FZX_COLORS[displays_dim]:-38;5;244}m" on=$'\e['"${FZX_COLORS[displays_on]:-38;5;114}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && b="" dim="" on="" r=""
  [[ -n "$id" ]] || return 0
  case "${FZX_MODE:-outputs}" in
    outputs)
      local name state primary mode rate pos rot pref line fp="" label="" n
      line="$(displays::outputs | awk -F'\t' -v o="$id" '$1 == o' | tr '\t' '\037')"
      [[ -n "$line" ]] || { printf 'no output %s\n' "$id"; return 0; }
      IFS=$'\x1f' read -r name state primary mode rate pos rot pref <<< "$line"
      if command -v "${FZX_DISPLAYS_DISPLAYD:-displayd}" > /dev/null; then
        read -r _ fp _ _ label < <(command "${FZX_DISPLAYS_DISPLAYD:-displayd}" monitors 2> /dev/null | awk -v o="$id" '$1 == o')
      fi
      printf '%s%s%s  %s\n' "$b" "$name" "$r" "${label:-}"
      [[ -n "$fp" ]] && printf '%sfingerprint%s  %s\n' "$dim" "$r" "$fp"
      case "$state" in
        on) printf '%son%s           %s at %s Hz, at %s%s%s\n' "$on" "$r" "$mode" "$rate" "$pos" "${rot/#normal/}" "${primary:+, primary}" ;;
        off) printf 'off          connected, no mode on screen%s\n' "${primary:+ (primary)}" ;;
        *) printf '%sdisconnected%s\n' "$dim" "$r" ;;
      esac
      [[ -n "$pref" ]] && printf '%spreferred%s    %s\n' "$dim" "$r" "$pref"
      n="$(displays::modes "$id" | wc -l)"
      ((n)) || return 0
      printf '\n%smodes%s (%s; enter lists them all)\n' "$b" "$r" "$n"
      displays::modes "$id" | head -n "${FZX_DISPLAYS_PREVIEW_MODES:-12}" | while IFS=$'\t' read -r mode rate marks; do
        local c=""
        [[ "$marks" == *'*'* ]] && c="$on"
        printf '  %s%-11s %7s Hz%s %s\n' "$c" "$mode" "$rate" "$r" "$([[ "$marks" == *'*'* ]] && printf 'on screen ')$([[ "$marks" == *'+'* ]] && printf 'preferred')"
      done
      ;;
    modes)
      displays::args "${@:3}"
      printf '%s%s%s at %s Hz on %s\n\n%senter runs%s\n  xrandr --output %s --mode %s --rate %s\n' \
        "$b" "$id" "$r" "${2:-}" "${DISPLAYS_OUTPUT:-?}" "$dim" "$r" "${DISPLAYS_OUTPUT:-?}" "$id" "${2:-}"
      ;;
    profiles)
      local conf="${XDG_CONFIG_HOME:-$HOME/.config}/displayd/config.toml" state="${XDG_STATE_HOME:-$HOME/.local/state}/displayd/state.json"
      printf '%s%s%s  %s(%s)%s\n\n' "$b" "$id" "$r" "$dim" "${2:-}" "$r"
      if [[ "${2:-}" == config && -f "$conf" ]]; then
        # the profile's tables: [profiles.NAME] and its [profiles.NAME.outputs.*]
        awk -v n="$id" '
          /^\[/ { t = $0; gsub(/^\[+|\]+.*$/, "", t); on = (t == "profiles." n || index(t, "profiles." n ".") == 1) }
          on' "$conf"
      elif [[ -f "$state" ]] && command -v jq > /dev/null; then
        command jq --arg n "$id" '.layouts[$n] // "not in displayd'"'"'s state"' "$state"
      fi
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" displays
  displays::preview "$@"
}
