#!/usr/bin/env bash
# colors: the 256-color palette, the terminal's 16 colors, X11 color names and fzx's own FZX_COLORS, with swatches and samples;
# the theme selector over every color setting, fzf's and fzx's.
# `fzx -m colors[:16|:names|:fzx|:theme]`. Enter prints numbers, names or keys; alt-h/alt-s/alt-e copy codes.
# In theme enter opens a value picker (colors:pick) for the setting; edits wait until alt-k saves them into
# ~/.config/fzx/theme.sh; alt-p shows them in a sample fzf in a tmux split; alt-t lists base16 presets
# (colors:presets), enter there sets fzf's keys to one.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
colors::opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{3}' '{4}')"
    "--preview-window=right,50%,nohidden"
  )
  FZX_ACTION_ARGS_FOR['hex']='{+3}'
  FZX_ACTION_ARGS_FOR['sgr']='{+4}'
  FZX_ACTION_ARGS_FOR['escape']='{+4}'
  FZX_ACTION_ARGS_FOR['reset']='{+1}'
  fzx::in_session || return 0
  case "${FZX_MODE:-}" in
    # the third field is the setting's value as it is now
    theme)
      fzx::bind enter "transform:$(fzx::cb transform edit '{1}' '{3}')" "change the setting: choose its new value"
      fzx::bind alt-t "transform:$(fzx::cb transform presets)" "presets: a base16 color scheme for fzf's keys"
      ;;
    presets)
      fzx::bind enter "transform:$(fzx::cb transform preset '{1}')" \
        "set fzf's keys to this scheme (pending until alt-k saves); the theme's other fzf keys are reset"
      ;;
    pick)
      fzx::bind enter "transform:$(fzx::cb transform pick '{1}')" \
        "set it to this color with the attributes on; with nothing matching, to what you typed"
      colors::_pick_header
      ;;
  esac
}

# colors::_pick_header: the picker's header: the setting and its value, how to give your own
colors::_pick_header() {
  local i id="" value=""
  for ((i = 0; i < ${#FZX_ARGS[@]}; i++)); do
    case "${FZX_ARGS[i]}" in
      --key) id="${FZX_ARGS[i + 1]:-}" ;;
      --value) value="${FZX_ARGS[i + 1]:-}" ;;
    esac
  done
  FZX_OPTS+=("--header=${id#*:}: ${value:-(not set)}  type #rrggbb, 0-255 or $([[ "$id" == fzx:* ]] && echo SGR || echo "fzf's syntax") for your own")
}

fzx::module_main "$@"
