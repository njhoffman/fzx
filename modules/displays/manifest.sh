#!/usr/bin/env bash
# displays menu entries, under X with xrandr answering; profiles with displayd

displays::manifest() {
  fzx::entry displays "Displays: outputs and modes (xrandr)"
  fzx::entry displays:profiles "Display profiles (displayd)"
}

displays::applicable() {
  [[ -n "${DISPLAY:-}" ]] && command -v xrandr > /dev/null || return 1
  case "$1" in
    displays:profiles) command -v "${FZX_DISPLAYS_DISPLAYD:-displayd}" > /dev/null ;;
    *) command xrandr --query > /dev/null 2>&1 ;;
  esac
}

# displays::summary <target>: the outputs on screen with their modes; the profiles and the default here
displays::summary() {
  # shellcheck source=./source.sh
  source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
  case "$1" in
    displays:profiles)
      displays::profiles | awk -F'\t' "$FZX_AWK_PLURAL"'
        { n++ } $3 ~ /\*/ { d = $1 }
        END { printf "%s%s\n", plural(n, "profile"), (d != "" ? ", default: " d : "") }'
      ;;
    *)
      displays::outputs | awk -F'\t' "$FZX_AWK_PLURAL"'
        $2 != "disconnected" { c++ }
        $2 == "on" { on = on (on != "" ? ", " : "") $1 " " $4 }
        END { printf "%s connected%s\n", c + 0, (on != "" ? "; on: " on : "") }'
      ;;
  esac
}

# the summaries are cached once for every directory: they describe the machine, not the directory
displays::summary_global() { :; }
