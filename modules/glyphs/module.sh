#!/usr/bin/env bash
# glyphs: Nerd Font glyphs, Unicode characters and blocks, and emoji, by name. `fzx -m glyphs[:unicode|:blocks|
# :emoji]`, `fzx -m glyphs:unicode --block NAME`. Enter prints the glyph; alt-c, alt-n and alt-e copy its code
# points, name or escape; in blocks enter opens the block.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS_FOR: read by lib/actions.sh
glyphs::opts() {
  glyphs::args "${FZX_ARGS[@]}" || return
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=5
    --accept-nth=1
    --tiebreak=index
    --multi
    --preview "$(fzx::cb preview '{1}' '{2}' '{3}' '{4}')"
    "--preview-window=right,45%,nohidden"
  )
  [[ -n "$GLYPHS_BLOCK" ]] && FZX_OPTS+=("--header=$GLYPHS_BLOCK")
  FZX_ACTION_ARGS_FOR['code']='{+2}'
  FZX_ACTION_ARGS_FOR['name']='{+3}'
  FZX_ACTION_ARGS_FOR['escape']='{+2}'
  if fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb transform enter '{3}' '{4}')" "print the glyphs; blocks: open the block"
    fzx::bind "${FZX_KEYS[glyphs.into]}" "transform:$(fzx::cb transform into '{3}' '{4}')" \
      "blocks: open the block; unicode: the character's block"
  fi
}

fzx::module_main "$@"
