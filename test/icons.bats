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

@test "icons.sh sources cleanly (a comment glued to a glyph would break the table)" {
  run bash -c "source '$FZX_REPO/lib/icons.sh' 2>&1 >/dev/null"
  [ -z "$output" ]
}

@test "icon_label: icon in the preview icon color, then the label; plain under NO_COLOR or FZX_ICONS=none" {
  local out
  FZX_ICONS=unicode
  fzx::icon_label user user '38;5;244' out
  [ "$out" = $'\e[38;5;110m☺\e[0m \e[38;5;244muser\e[0m' ]
  NO_COLOR=1 fzx::icon_label user user '38;5;244' out
  [ "$out" = '☺ user' ]
  FZX_ICONS=none
  fzx::icon_label user user '' out
  [ "$out" = user ]
}
