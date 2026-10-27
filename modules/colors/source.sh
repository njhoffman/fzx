#!/usr/bin/env bash
# colors source. Lines are "id<TAB>display<TAB>hex<TAB>sgr": the id is the color number, the X11 name or
# the FZX_COLORS key; hex is empty for fzx colors; sgr is the foreground's SGR parameters.
# Mode from $FZX_MODE: 256 (xterm-256.tsv), names (FZX_COLORS_RGB_TXT), fzx (every config layer).

COLORS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# awk functions: the 256 palette's rgb (16-231 the 6x6x6 cube, 232-255 the grays) and the nearest of
# 16-255 to an rgb (0-15 are left out: terminals redefine them)
COLORS_AWK_PALETTE='
  function palette(   i, l) {
    split("0 95 135 175 215 255", l, " ")
    for (i = 16; i < 232; i++) { pr[i] = l[int((i - 16) / 36) + 1]; pg[i] = l[int((i - 16) / 6) % 6 + 1]; pb[i] = l[(i - 16) % 6 + 1] }
    for (i = 232; i < 256; i++) pr[i] = pg[i] = pb[i] = 8 + 10 * (i - 232)
  }
  function nearest(r, g, b,   i, d, best, bd) {
    bd = -1
    for (i = 16; i < 256; i++) { d = (r - pr[i]) ^ 2 + (g - pg[i]) ^ 2 + (b - pb[i]) ^ 2; if (bd < 0 || d < bd) { bd = d; best = i } }
    return best
  }'

colors::palette() {
  awk -F'\t' '{
    rgb = $4; sub(/^rgb/, "", rgb)
    printf "%s\t\033[48;5;%sm      \033[0m \033[38;5;%sm%3s %-20s\033[0m %s \033[38;5;244m%s\033[0m\t%s\t38;5;%s\n", $1, $1, $1, $1, $2, $3, rgb, $3, $1 }' \
    "$COLORS_DIR/xterm-256.tsv"
}

colors::names() {
  [[ -r "$FZX_COLORS_RGB_TXT" ]] || {
    printf 'colors: no X11 color names at %s (FZX_COLORS_RGB_TXT)\n' "$FZX_COLORS_RGB_TXT" >&2
    return 2
  }
  # one spelling per color name: the ones without spaces ("AliceBlue", not "alice blue")
  awk "$COLORS_AWK_PALETTE"'
    BEGIN { palette() }
    /^!/ || NF != 4 || seen[tolower($4)]++ { next }
    { r = $1; g = $2; b = $3; hex = sprintf("#%02x%02x%02x", r, g, b); n = nearest(r, g, b)
      printf "%s\t\033[48;2;%d;%d;%dm      \033[0m \033[38;2;%d;%d;%dm%-24s\033[0m %s \033[38;5;244m≈\033[0m \033[38;5;%dm%3d\033[0m\t%s\t38;2;%d;%d;%d\n",
        $4, r, g, b, r, g, b, $4, hex, n, n, hex, r, g, b }' "$FZX_COLORS_RGB_TXT"
}

# colors::fzx: FZX_COLORS of every layer: fzx's (defaults and the user's), then each module's own keys,
# "key<TAB>value<TAB>owner"
colors::fzx_table() {
  local dir mod
  (
    unset FZX_COLORS
    declare -gA FZX_COLORS
    fzx::config_load "" ""
    for k in "${!FZX_COLORS[@]}"; do printf '%s\t%s\tfzx\n' "$k" "${FZX_COLORS[$k]}"; done | LC_ALL=C sort
  )
  for dir in "$FZX_ROOT"/modules/*/; do
    dir="${dir%/}" mod="${dir##*/}"
    [[ -f "$dir/config.sh" ]] || continue
    (
      unset FZX_COLORS
      declare -gA FZX_COLORS
      fzx::config_load "$dir" "$mod" > /dev/null 2>&1
      for k in "${!FZX_COLORS[@]}"; do printf '%s\t%s\t%s\n' "$k" "${FZX_COLORS[$k]}" "$mod"; done | LC_ALL=C sort
    )
  done | awk -F'\t' 'NR == FNR { global[$1] = $2; next } !(($1 in global) && global[$1] == $2)' <(
    unset FZX_COLORS
    declare -gA FZX_COLORS
    fzx::config_load "" ""
    for k in "${!FZX_COLORS[@]}"; do printf '%s\t%s\n' "$k" "${FZX_COLORS[$k]}"; done
  ) -
}

colors::fzx() {
  colors::fzx_table | awk -F'\t' '!seen[$1 SUBSEP $3]++ {
    printf "%s\t\033[%sm%-22s\033[0m \033[38;5;244m%-10s\033[0m %s\t\t%s\n", $1, $2, $1, $3, $2, $2 }'
}

colors::source() {
  case "${FZX_MODE:-256}" in
    256) colors::palette ;;
    names) colors::names ;;
    fzx) colors::fzx ;;
    *)
      printf 'colors: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$COLORS_DIR" colors
  colors::source "$@"
}
