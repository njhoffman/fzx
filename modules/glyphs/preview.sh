#!/usr/bin/env bash
# glyphs preview: the glyph in a few colors and on a light and a dark background, its name, code points,
# UTF-8 bytes and the ways to write it, then its neighbours: the rows of 16 code points around it (a single
# code point), with it marked. A block: its first characters, 16 to a row.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# glyphs::grid <first> <last> [mark]: the code points first..last (numbers), 16 to a row under a hex header,
# the mark reversed ([x] under NO_COLOR); with the unicode list built, code points it does not name are dim
# dots (private use stays: the Nerd Font glyphs live there); rows with nothing to show are left out
glyphs::grid() {
  local first="$1" last="$2" mark="${3:--1}" d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' on=$'\e[7m' off=$'\e[0m'
  local known="$FZX_CACHE_DIR/glyphs/unicode.tsv"
  [[ -n "${NO_COLOR+x}" ]] && d="" r="" on="[" off="]"
  [[ -s "$known" ]] || known=/dev/null
  LC_ALL=C awk -F'\t' -v first="$first" -v last="$last" -v mark="$mark" -v d="$d" -v r="$r" -v on="$on" -v off="$off" \
    -v all="$([[ "$known" == /dev/null ]] && echo 1 || echo 0)" "$GLYPHS_AWK_UTF8"'
    { have[hex($2)] = 1 }
    END {
      printf "%s      ", d; for (i = 0; i < 16; i++) printf " %X ", i; printf "%s\n", r
      for (row = first - first % 16; row <= last; row += 16) {
        line = ""; shown = 0
        for (c = row; c < row + 16; c++) {
          if (c < first || c > last || (c >= 55296 && c <= 57343) || c < 33 || (c >= 127 && c < 161)) { line = line "   "; continue }
          g = utf8(c); shown++
          if (c == mark) line = line (on == "[" ? "[" g "]" : " " on g off " ")
          else if (all || (c in have) || (c >= 57344 && c <= 63743) || c >= 983040) line = line " " g " "
          else { line = line " " d "·" r " "; shown-- } }
        if (shown) printf "%s%05X%s %s\n", d, row, r, line } }' "$known"
}

# glyphs::preview <glyph> <code points> <name> <group>
glyphs::preview() {
  local g="${1:-}" cps="${2:-}" name="${3:-}" group="${4:-}" b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  local c bytes esc="" u="" html="" cp first last
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  [[ -n "$g" ]] || return 0
  if [[ "${FZX_MODE:-}" == blocks ]]; then
    first="${cps%%..*}" last="${cps##*..}"
    printf '%s%s%s  %sU+%s..U+%s%s\n\n' "$b" "$name" "$r" "$d" "$first" "$last" "$r"
    first=$((16#$first)) last=$((16#$last))
    ((last - first > 255)) && last=$((first + 255))
    glyphs::grid "$first" "$last"
    return 0
  fi
  if [[ -z "${NO_COLOR+x}" ]]; then
    printf '\n   %s   \e[38;5;203m%s\e[0m   \e[38;5;114m%s\e[0m   \e[38;5;75m%s\e[0m   \e[30;48;5;254m %s \e[0m   \e[97;48;5;236m %s \e[0m\n\n' \
      "$g" "$g" "$g" "$g" "$g" "$g"
  else
    printf '\n   %s\n\n' "$g"
  fi
  for cp in $cps; do
    c=$((16#$cp))
    u+="${u:+ }U+$cp"
    html+="&#x$cp;"
    if ((c > 0xFFFF)); then printf -v cp '\\U%08X' "$c"; else printf -v cp '\\u%04X' "$c"; fi
    esc+="$cp"
  done
  bytes="$(printf '%s' "$g" | od -An -tx1 | tr -s ' \n' ' ' | sed 's/^ //; s/ $//; s/\([0-9a-f][0-9a-f]\)/\\x\1/g; s/ //g')"
  printf '%sname%s     %s\n%scode%s     %s\n%sgroup%s    %s\n' "$d" "$r" "$name" "$d" "$r" "$u" "$d" "$r" "$group"
  printf '%sescape%s   %s  %s(bash $'"'"'...'"'"', zsh, python)%s\n%sutf-8%s    %s\n%shtml%s     %s\n' \
    "$d" "$r" "$esc" "$d" "$r" "$d" "$r" "$bytes" "$d" "$r" "$html"
  # neighbours: only for a single code point
  [[ "$cps" == *" "* ]] && return 0
  c=$((16#$cps))
  printf '\n'
  glyphs::grid $((c - c % 16 - 16 < 0 ? 0 : c - c % 16 - 16)) $((c - c % 16 + 31)) "$c"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && glyphs::preview "$@"
