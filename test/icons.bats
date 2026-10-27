#!/usr/bin/env bats
# lib/icons.sh: named icons in the FZX_ICONS style

load test_helper

setup() {
  setup_fzx
  load_libs icons
}

@test "icon: nerd glyphs by default, plain Unicode, or nothing" {
  [ "$(fzx::icon branch)" = $'' ]
  FZX_ICONS=unicode
  [ "$(fzx::icon branch)" = '⎇' ]
  [ "$(fzx::icon failed)" = '✗' ]
  FZX_ICONS=none
  [ -z "$(fzx::icon branch)" ]
  FZX_ICONS=unicode
  [ -z "$(fzx::icon no-such-icon)" ]
}

@test "icon into a variable, whatever the caller names it" {
  local _glyph _i
  FZX_ICONS=unicode
  fzx::icon todo _glyph
  fzx::icon todo _i
  [ "$_glyph" = '☐' ] && [ "$_i" = '☐' ]
}

@test "icon_vars: awk -v options per name" {
  FZX_ICONS=unicode
  fzx::icon_vars ahead behind
  [ "${FZX_ICON_VARS[*]}" = "-v icon_ahead=↑ -v icon_behind=↓" ]
  [ "$(awk "${FZX_ICON_VARS[@]}" 'BEGIN { print icon_ahead icon_behind }')" = '↑↓' ]
}

@test "every icon has both a nerd and a Unicode form" {
  local name
  for name in "${!FZX_ICONS_NERD[@]}"; do
    [ -n "${FZX_ICONS_UNICODE[$name]:-}" ]
  done
  [ "${#FZX_ICONS_NERD[@]}" -eq "${#FZX_ICONS_UNICODE[@]}" ]
}
