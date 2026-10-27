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
  [toggle_on]="" # footer: a toggle that is on
  [toggle_off]="" # footer: a toggle that is off
  [sort]=""      # footer: the sort order
  [user]=""      # preview: a user
  [clock]=""     # preview: a time
  [duration]=""  # preview: how long
  [cpu]=""       # preview: cpu
  [memory]=""    # preview: memory
  [parent]=""    # preview: parent and children
  [threads]=""   # preview: threads, counts
  [state]=""     # preview: a state
  [command]=""   # preview: a command line
  [folder]=""    # preview: a directory
  [host]=""      # preview: a host
  [remote]=""    # preview: a remote
  [star]=""      # github: stars
  [fork]=""      # github: forks
  [issue]=""     # github: open issues
  [archived]=""  # github: an archived repository
  [repo]=""      # github: a repository
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
  [toggle_on]="●"
  [toggle_off]="○"
  [sort]="↓"
  [user]="☺"
  [clock]="◷"
  [duration]="⧗"
  [cpu]="◫"
  [memory]="▥"
  [parent]="↰"
  [threads]="≡"
  [state]="◉"
  [command]="$"
  [folder]="⌂"
  [host]="▭"
  [remote]="⇄"
  [star]="★"
  [fork]="⑂"
  [issue]="!"
  [archived]="▣"
  [repo]="▤"
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

# fzx::icon_label <name> <label> <label SGR> <var>: "<icon> <label>" for a preview, the icon in
# FZX_COLORS[preview_icon] and the label in the given SGR (no escapes when it is empty or NO_COLOR is set);
# the label alone with FZX_ICONS=none
fzx::icon_label() {
  local __fzx_glyph __fzx_out="" __fzx_ic="${FZX_COLORS[preview_icon]:-38;5;110}"
  fzx::icon "$1" __fzx_glyph
  if [[ -n "${NO_COLOR+x}" || -z "$3" ]]; then
    __fzx_out="${__fzx_glyph:+$__fzx_glyph }$2"
  else
    [[ -n "$__fzx_glyph" ]] && __fzx_out=$'\e['"${__fzx_ic}m$__fzx_glyph"$'\e[0m '
    __fzx_out+=$'\e['"${3}m$2"$'\e[0m'
  fi
  printf -v "$4" '%s' "$__fzx_out"
}
