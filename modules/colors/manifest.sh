#!/usr/bin/env bash
# colors menu entries

colors::manifest() {
  fzx::entry colors "The 256-color palette"
  fzx::entry colors:names "X11 color names"
  fzx::entry colors:fzx "fzx's own colors"
}

colors::applicable() {
  [[ "$1" != colors:names ]] || [[ -r "${FZX_COLORS_RGB_TXT:-/usr/share/X11/rgb.txt}" ]]
}
