#!/usr/bin/env bash
# colors preview: a swatch the preview's width, sample text in the color on the terminal's background, a
# dark and a light one, and the color's values and codes

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# colors::preview <id> <hex> <sgr>
colors::preview() {
  local id="${1:-}" hex="${2:-}" sgr="${3:-}" cols="${FZF_PREVIEW_COLUMNS:-60}" bg="" line rgb name hsl
  local fg_re='(^|;)38;(5;[0-9]+|2;[0-9]+;[0-9]+;[0-9]+)($|;)'
  local D=$'\e[38;5;244m' R=$'\e[0m' text="The quick brown fox jumps over the lazy dog"
  [[ -n "$id" && -n "$sgr" ]] || return 0
  # the background twin of a foreground color: 38;5;N -> 48;5;N, 38;2;R;G;B -> 48;2;R;G;B
  [[ "$sgr" =~ $fg_re ]] && bg="48;${BASH_REMATCH[2]}"
  if [[ -n "$bg" ]]; then
    printf -v line '%*s' "$cols" ''
    for _ in 1 2 3 4; do printf '\e[%sm%s\e[0m\n' "$bg" "$line"; done
  fi
  printf '\n  \e[%sm%s\e[0m\n' "$sgr" "$text"
  printf '  \e[%s;48;5;236m %s \e[0m\n' "$sgr" "$text"
  printf '  \e[%s;48;5;254m %s \e[0m\n' "$sgr" "$text"
  printf '  \e[1;%sm%s\e[0m\n\n' "$sgr" "$text"
  case "${FZX_MODE:-256}" in
    256)
      IFS=$'\t' read -r _ name _ rgb hsl < <(awk -F'\t' -v n="$id" '$1 == n' "$COLORS_DIR/xterm-256.tsv")
      printf '%snumber%s  %s\n%sname%s    %s\n%shex%s     %s\n%srgb%s     %s\n%shsl%s     %s\n' \
        "$D" "$R" "$id" "$D" "$R" "$name" "$D" "$R" "$hex" "$D" "$R" "${rgb#rgb}" "$D" "$R" "${hsl#hsl}"
      ;;
    names)
      rgb="${sgr#38;2;}"
      printf '%sname%s    %s\n%shex%s     %s\n%srgb%s     (%s)\n' "$D" "$R" "$id" "$D" "$R" "$hex" "$D" "$R" "${rgb//;/,}"
      awk -v rgb="$rgb" -v D="$D" -v R="$R" "$COLORS_AWK_PALETTE"'
        BEGIN { palette(); split(rgb, c, ";"); n = nearest(c[1], c[2], c[3])
          printf "%snearest%s \033[48;5;%dm    \033[0m %d (%d,%d,%d)\n", D, R, n, n, pr[n], pg[n], pb[n] }'
      ;;
    fzx) printf '%skey%s     FZX_COLORS[%s]\n%svalue%s   %s\n' "$D" "$R" "$id" "$D" "$R" "$sgr" ;;
  esac
  printf '%ssgr%s     %s\n%sescape%s  \\e[%sm%s\n' "$D" "$R" "$sgr" "$D" "$R" "$sgr" "${bg:+  ${D}background$R \\e[${bg}m}"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && colors::preview "$@"
