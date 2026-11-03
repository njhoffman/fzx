#!/usr/bin/env bash
# colors menu entries

colors::manifest() {
  fzx::entry colors "The 256-color palette"
  fzx::entry colors:16 "The terminal's 16 colors"
  fzx::entry colors:names "X11 color names"
  fzx::entry colors:fzx "fzx's own colors"
}

colors::applicable() {
  [[ "$1" != colors:names ]] || [[ -r "${FZX_COLORS_RGB_TXT:-/usr/share/X11/rgb.txt}" ]]
}

# colors::summary <target>: how many the mode lists, fzx's by the config layers
colors::summary() {
  case "$1" in
    colors) printf '256 colors\n' ;;
    colors:16) printf '16 colors, 8 and bright\n' ;;
    colors:names | colors:fzx)
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :
      printf '%s %s\n' "$(FZX_MODE="${1#colors:}" colors::source 2> /dev/null | wc -l)" \
        "$([[ "$1" == colors:names ]] && echo names || echo colors)"
      ;;
  esac
}
