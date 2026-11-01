#!/usr/bin/env bash
# glyphs actions: copy the selection's code points, names or UTF-8 escapes; update the Nerd Font names

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# glyphs::escape <code points>: "\uXXXX" per code point ("\UXXXXXXXX" above FFFF), as bash's $'...', zsh and
# python read them
glyphs::escape() {
  local cp c out=""
  for cp in $1; do
    c=$((16#$cp))
    if ((c > 0xFFFF)); then printf -v cp '\\U%08X' "$c"; else printf -v cp '\\u%04X' "$c"; fi
    out+="$cp"
  done
  printf '%s\n' "$out"
}

# glyphs::update: the latest glyph names from Nerd Fonts (FZX_GLYPHS_NERD_URL) into the cache, used from then
# on instead of the module's own; kept only when it is a glyph table
glyphs::update() {
  local file="$FZX_CACHE_DIR/glyphs/glyphnames.json" tmp
  mkdir -p -- "${file%/*}" || return
  tmp="$file.$BASHPID"
  printf 'downloading %s\n' "$FZX_GLYPHS_NERD_URL"
  if ! command curl -fsSL -m 60 -o "$tmp" -- "$FZX_GLYPHS_NERD_URL" ||
    ! command jq -e '.METADATA.version and (length > 100)' -- "$tmp" > /dev/null 2>&1; then
    rm -f -- "$tmp"
    printf 'glyphs: the download failed or is not a glyph table\n' >&2
    return 1
  fi
  mv -f -- "$tmp" "$file"
  command jq -r '"Nerd Fonts \(.METADATA.version) (\(.METADATA.date[0:10])): \(length - 1) glyphs"' -- "$file"
}

# glyphs::action <code|name|escape|update> <values...> (code: the code point fields; name: the names; escape:
# the code point fields)
glyphs::action() {
  local action="${1:-}" v out=()
  shift
  case "$action" in
    code) for v; do [[ -n "$v" ]] && out+=("U+${v// / U+}"); done ;;
    name) for v; do [[ -n "$v" ]] && out+=("$v"); done ;;
    escape) for v; do [[ -n "$v" ]] && out+=("$(glyphs::escape "$v")"); done ;;
    update)
      glyphs::update
      local rc=$?
      [[ -n "${FZX_SESSION_DIR:-}" ]] && { printf '\npress a key '; IFS= read -rsn1 < /dev/tty || :; }
      return "$rc"
      ;;
    *)
      printf 'glyphs: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  ((${#out[@]})) || return 0
  fzx::require builtin
  printf '%s\n' "${out[@]}" | fzx::clip
}

# glyphs::transform <enter|into> <name> <group>: enter accepts (prints the glyphs), except in blocks, where it
# opens the block as into does; into opens a block (blocks: the row's, unicode: the character's) as a child
# session listing its characters
glyphs::transform() {
  local name="${1:-}" block="${2:-}" group="${3:-}"
  [[ "$name" == enter && "${FZX_MODE:-}" != blocks ]] && { printf 'accept'; return 0; }
  case "${FZX_MODE:-}" in
    blocks) ;;
    unicode) block="$group" ;;
    *) return 0 ;;
  esac
  [[ -n "$block" && "$block" != - ]] || return 0
  fzx::require nav
  fzx::nav goto glyphs:unicode --block "$block"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$GLYPHS_DIR" glyphs
  glyphs::action "$@"
}
