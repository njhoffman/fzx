#!/usr/bin/env bash
# glyphs menu entries; the Unicode ones where the Unicode data is installed

glyphs::manifest() {
  fzx::entry glyphs "Nerd Font glyphs"
  fzx::entry glyphs:unicode "Unicode characters by name"
  fzx::entry glyphs:blocks "Unicode blocks"
  fzx::entry glyphs:emoji "Emoji by name"
}

glyphs::applicable() {
  local dir="${FZX_GLYPHS_UNICODE_DIR:-/usr/share/unicode}"
  case "$1" in
    glyphs:unicode | glyphs:blocks) [[ -r "$dir/UnicodeData.txt" && -r "$dir/Blocks.txt" ]] ;;
    glyphs:emoji) [[ -r "$dir/emoji/emoji-test.txt" ]] ;;
    *) command -v jq > /dev/null ;;
  esac
}
