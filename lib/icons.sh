#!/usr/bin/env bash
# icons: named icons in the style FZX_ICONS picks: nerd (Nerd Font glyphs, the default), unicode (plain
# Unicode symbols, for terminals without a Nerd Font) or none. The glyphs are literal characters, not \u
# escapes, so they do not depend on the locale bash parses this file in.

# shellcheck disable=SC2034  # read through fzx::icon
declare -gA FZX_ICONS_NERD=(
  [branch]=""    # git branch
  [ahead]=""     # commits ahead of the upstream
  [behind]=""    # commits behind
  [changed]=""   # uncommitted changes
  [todo]=""      # open TODO items
  [added]=""     # git: added / staged new
  [modified]=""  # git: modified
  [deleted]=""   # git: deleted
  [renamed]=""   # git: renamed or copied
  [untracked]="" # git: untracked
  [conflict]=""  # git: unmerged
  [running]=""   # a running container or process
  [stopped]=""   # stopped / exited
  [paused]=""    # paused
  [created]=""   # created, never started
  [file]=""      # a file
  [unit]=""      # a systemd unit
  [docker]=""    # a docker container
  [ok]=""        # succeeded
  [failed]=""    # failed
)

declare -gA FZX_ICONS_UNICODE=(
  [branch]="⎇"
  [ahead]="↑"
  [behind]="↓"
  [changed]="●"
  [todo]="☐"
  [added]="+"
  [modified]="~"
  [deleted]="-"
  [renamed]=">"
  [untracked]="?"
  [conflict]="!"
  [running]="▶"
  [stopped]="■"
  [paused]="‖"
  [created]="○"
  [file]="▤"
  [unit]="⚙"
  [docker]="◆"
  [ok]="✓"
  [failed]="✗"
)

# fzx::icon <name> [var]: the icon, empty for an unknown name or FZX_ICONS=none; into var when given
fzx::icon() {
  local __fzx_icon_value=""
  case "${FZX_ICONS:-nerd}" in
    nerd) __fzx_icon_value="${FZX_ICONS_NERD[$1]:-}" ;;
    unicode) __fzx_icon_value="${FZX_ICONS_UNICODE[$1]:-}" ;;
  esac
  if [[ -n "${2:-}" ]]; then printf -v "$2" '%s' "$__fzx_icon_value"; else printf '%s' "$__fzx_icon_value"; fi
}

# fzx::icon_vars <name...>: awk -v options "icon_<name>=<icon>" for each name, into FZX_ICON_VARS
fzx::icon_vars() {
  local _name _glyph
  FZX_ICON_VARS=()
  for _name in "$@"; do
    fzx::icon "$_name" _glyph
    FZX_ICON_VARS+=(-v "icon_${_name}=$_glyph")
  done
}
