#!/usr/bin/env bash
# colors source. Lines are "id<TAB>display<TAB>hex<TAB>sgr": the id is the color number, the X11 name or
# the FZX_COLORS key; hex is empty for fzx colors; sgr is the foreground's SGR parameters.
# Mode from $FZX_MODE: 256 (xterm-256.tsv), 16 (the terminal's own 8 colors and their bright twins; no hex:
# the terminal sets them), names (FZX_COLORS_RGB_TXT), fzx (every config layer), theme (every color setting,
# fzf's and fzx's, to change; theme.sh), pick (the theme's value picker, `--key ID`) and presets (base16 schemes).

COLORS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./theme.sh
source "$COLORS_DIR/theme.sh"

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

# colors::sixteen: 30-37 and 90-97, each as a background swatch, then normal, bold, faint and on its
# background; the id is the foreground's SGR code
colors::sixteen() {
  local names=(black red green yellow blue magenta cyan white) i c
  for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if ((i < 8)); then c=$((30 + i)); else c=$((82 + i)); fi
    printf '%s\t\e[%sm    \e[0m %2d %-15s \e[%sm%-6s\e[0m \e[1;%sm%-6s\e[0m \e[2;%sm%-6s\e[0m \e[%s;7m %-6s\e[0m\t\t%s\n' \
      "$c" "$((c + 10))" "$c" "$( ((i < 8)) && echo "${names[i]}" || echo "bright ${names[i - 8]}")" \
      "$c" normal "$c" bold "$c" faint "$c" invert "$c"
  done
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

# colors::theme_sgr <id> <value> <var>: what a setting's swatch is drawn in: fzx values are SGR already,
# fzf's are converted (backgrounds as backgrounds)
colors::theme_sgr() {
  local _k="${1#*:}"
  if [[ "$1" == fzx:* ]]; then
    printf -v "$3" '%s' "$2"
  else
    colors::fzf_sgr "$2" "$(colors::_is_bg "$_k" && echo 1 || echo 0)" "$3"
  fi
}

# colors::theme: one row per setting, "id<TAB>display<TAB>value<TAB>sgr": a mark for an unsaved change, the swatch,
# the key, its value (an fzf key nothing sets: the key it falls back to, drawn in that one's color) and
# where the value comes from
colors::theme() {
  local id val org sgr key parent shown swatch mark D=$'\e[38;5;244m' R=$'\e[0m' M=""
  local -A eff=() parents=()
  [[ -z "${NO_COLOR:+x}" ]] && M=$'\e['"${FZX_COLORS[title_loop]:-1;38;5;214}m"
  while IFS=$'\t' read -r key parent _; do parents[$key]="$parent"; done <<< "$COLORS_FZF_KEYS"
  # read splits on a separator that is not whitespace, or the empty values would run together
  while IFS=$'\x1f' read -r id val org _ _; do
    key="${id#*:}" shown="$val"
    # an unset fzf key shows the one it falls back to, the nearest that is set
    if [[ "$id" == fzf:* && -z "$val" ]]; then
      parent="${parents[$key]:--}" shown="(fzf's default)"
      while [[ "$parent" != - ]]; do
        if [[ -n "${eff[$parent]:-}" ]]; then val="${eff[$parent]}" shown="(as $parent)"; break; fi
        parent="${parents[$parent]:--}"
      done
    fi
    [[ "$id" == fzf:* && -n "$val" ]] && eff[$key]="$val"
    sgr=""
    [[ -n "$val" ]] && colors::theme_sgr "$id" "$val" sgr
    if [[ -z "$sgr" ]]; then
      swatch="      "
    elif [[ "$id" == fzf:* ]] && colors::_is_bg "$key"; then
      swatch=$'\e['"${sgr}m      $R"
    else
      swatch=$'\e['"${sgr}m Abc  $R"
    fi
    mark=" "
    [[ "$org" == pending || "$org" == reset ]] && mark="${M}●$R"
    # the value as set (empty for an fzf key nothing sets), not the one it falls back to
    [[ "$shown" == "(as "* || "$shown" == "(fzf's default)" ]] && val=""
    printf '%s\t%s %s %-22s %-24s %s%s%s\t%s\t%s\n' "$id" "$mark" "$swatch" "$key" "$shown" "$D" "$org" "$R" "$val" "$sgr"
  done < <(colors::theme_values | tr '\t' '\037')
}

# colors::pick [--key ID]: the value picker: a reset row ("-"), then the 256 palette in the attributes the
# toggles have on. The id is the color number; nothing matching the query means the query is the value
colors::pick() {
  local attrs="" a name
  for a in "${COLORS_ATTRS[@]}"; do
    name="${a%%:*}"
    [[ " ${FZX_TOGGLES:-} " == *" $name "* ]] && attrs+="${a#*:};"
  done
  printf -- '-\t\e[38;5;244m%-6s\e[0m reset: back to the value the config layers or fzf give\t\t\n' reset
  awk -F'\t' -v A="$attrs" '{
    printf "%s\t\033[48;5;%sm      \033[0m \033[%s38;5;%sm%3s %-20s\033[0m %s\t%s\t%s38;5;%s\n", $1, $1, A, $1, $1, $2, $3, $3, A, $1 }' \
    "$COLORS_DIR/xterm-256.tsv"
}

# colors::presets: the base16 presets, "slug<TAB>display<TAB><TAB>": the name, its 16 colors, the author
# (without the links and addresses)
colors::presets() {
  awk -F'\t' -v D=$'\e[38;5;244m' -v R=$'\e[0m' '
    /^#/ || NF < 19 { next }
    {
      a = $3; gsub(/ *[(<][^)>]*[)>]/, "", a)
      s = ""
      for (i = 4; i <= 19; i++) s = s sprintf("\033[48;2;%d;%d;%dm  ", hex(substr($i, 1, 2)), hex(substr($i, 3, 2)), hex(substr($i, 5, 2)))
      printf "%s\t%-28s %s%s %s%s%s\t\t\n", $1, substr($2, 1, 28), s, R, D, a, R
    }
    function hex(h,   i, v) { v = 0; for (i = 1; i <= 2; i++) v = v * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1; return v }' \
    "$(colors::presets_file)"
}

colors::source() {
  case "${FZX_MODE:-256}" in
    256) colors::palette ;;
    16) colors::sixteen ;;
    names) colors::names ;;
    fzx) colors::fzx ;;
    theme) colors::theme ;;
    pick) colors::pick "$@" ;;
    presets) colors::presets ;;
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
