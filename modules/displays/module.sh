#!/usr/bin/env bash
# displays: xrandr's outputs and their modes, and displayd's profiles (~/git/displayd) when it is installed.
# `fzx -m displays[:profiles]`. outputs: enter lists the output's modes (enter there sets one), alt-s turns it
# on or off, alt-p makes it primary, alt-m places it, alt-R rotates it, alt-a shows the disconnected ones;
# profiles: enter applies one, alt-D makes it the default here; alt-S saves the layout on screen.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# displays::header: displayd's applied profile and whether its daemon runs, empty without displayd
displays::header() {
  command -v "${FZX_DISPLAYS_DISPLAYD:-displayd}" > /dev/null || return 0
  command "${FZX_DISPLAYS_DISPLAYD:-displayd}" status 2> /dev/null | awk '
    $1 == "applied" { $1 = ""; sub(/^ +/, ""); applied = $0 }
    $1 == "daemon" { daemon = $2 }
    END { if (applied != "" || daemon != "") printf "displayd: %s%s", (applied != "" ? applied : "nothing applied"), (daemon != "" ? "  (daemon " daemon ")" : "") }'
}

# shellcheck disable=SC2034  # FZX_ACTION_ARGS*: read by lib/actions.sh
displays::opts() {
  local header out=""
  displays::args "${FZX_ARGS[@]}"
  header="$(displays::header)"
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=3
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{2}' "${FZX_ARGS[@]}")"
    ${header:+"--header=$header"}
  )
  case "$FZX_MODE" in
    modes)
      printf -v out '%q' "$DISPLAYS_OUTPUT"
      FZX_ACTION_ARGS_FOR['set']="$out {1} {2}"
      ;;
    profiles) FZX_ACTION_ARGS_FOR['apply']='{1}' FZX_ACTION_ARGS_FOR['default']='{1}' ;;
  esac
  FZX_ACTION_ARGS_FOR['save']='' FZX_ACTION_ARGS_FOR['rescue']='' FZX_ACTION_ARGS_FOR['daemon']=''
  fzx::in_session || return 0
  # enter: an output's modes, a mode set, a profile applied (one row each; standalone it prints)
  local act flags
  fzx::require actions
  case "$FZX_MODE" in
    outputs)
      fzx::bind enter "transform:$(fzx::cb nav goto displays:modes --output '{1}')" "the output's modes"
      fzx::bind ctrl-o "transform:$(fzx::cb nav goto displays:modes --output '{1}')" "the output's modes"
      ;;
    modes)
      fzx::comp_field action set flags flags 2> /dev/null || flags=notify,reload
      fzx::_action_bind_string set "$flags" act
      fzx::bind enter "$act" "use this mode and rate on $DISPLAYS_OUTPUT"
      ;;
    profiles)
      fzx::comp_field action apply flags flags 2> /dev/null || flags=notify,reload
      fzx::_action_bind_string apply "$flags" act
      fzx::bind enter "$act" "apply the profile (displayd apply)"
      ;;
  esac
}

fzx::module_main "$@"
