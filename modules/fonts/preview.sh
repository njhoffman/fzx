#!/usr/bin/env bash
# fonts preview: a sample in the font (ImageMagick renders it once per font file into
# $FZX_CACHE_DIR/fonts, chafa draws it), then the family's styles with their files, spacing and formats

# fonts::_pattern <family>: a fontconfig pattern that matches the family exactly (\ - : , = escaped)
fonts::_pattern() {
  printf ':family=%s\n' "$(printf '%s' "$1" | sed 's/[\\:,=-]/\\&/g')"
}

# fonts::sample <font file> <rows>: the sample drawn in <rows> rows; nothing without magick or chafa, with
# FZX_FONTS_SAMPLE_ROWS=0, or when the font cannot be rendered
fonts::sample() {
  local file="$1" rows="$2" cols="${FZF_PREVIEW_COLUMNS:-80}" dir key img text
  ((rows >= 3)) && [[ -f "$file" ]] || return 0
  command -v chafa > /dev/null && command -v magick > /dev/null || return 0
  dir="${FZX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fzx}/fonts"
  # one image per font file and sample settings
  key="$(printf '%s\n' "$file" "${FZX_FONTS_SAMPLE:-}" "${FZX_FONTS_SAMPLE_FG:-}" "${FZX_FONTS_SAMPLE_BG:-}" \
    "${FZX_FONTS_SAMPLE_POINTS:-}" | cksum | cut -d' ' -f1)"
  img="$dir/$key.png"
  if [[ ! -s "$img" || "$file" -nt "$img" ]]; then
    mkdir -p -- "$dir" || return 0
    # label: treats % as an escape and a leading @ as a file to read
    text="$(printf '%b' "${FZX_FONTS_SAMPLE:-The quick brown fox}")"
    text="${text//%/%%}"
    [[ "$text" == @* ]] && text=" $text"
    if ! command magick -background "${FZX_FONTS_SAMPLE_BG:-none}" -fill "${FZX_FONTS_SAMPLE_FG:-#d0d0d0}" \
      -font "$file" -pointsize "${FZX_FONTS_SAMPLE_POINTS:-48}" "label:$text" "$img.$BASHPID.png" 2> /dev/null; then
      rm -f -- "$img.$BASHPID.png"
      return 0
    fi
    mv -f -- "$img.$BASHPID.png" "$img"
  fi
  command chafa --format="${FZX_PREVIEW_IMAGE_FORMAT:-symbols}" --size="${cols}x$rows" --animate=off -- "$img" 2> /dev/null
  printf '\n'
}

# fonts::preview <family> <sample file>
fonts::preview() {
  local fam="${1:-}" file="${2:-}" rows="${FZX_FONTS_SAMPLE_ROWS:-10}" lines="${FZF_PREVIEW_LINES:-40}" out
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && b="" d="" r=""
  [[ -n "$fam" ]] || return 0
  # the sample takes at most half the preview
  ((rows > lines / 2)) && rows=$((lines / 2))
  fonts::sample "$file" "$rows"
  printf '%s%s%s\n\n' "$b" "$fam" "$r"
  out="$(command fc-list --format '%{style[0]}\t%{spacing}\t%{fontformat}\t%{file}\n' "$(fonts::_pattern "$fam")" 2> /dev/null |
    sort -t$'\t' -k1,1)"
  [[ -n "$out" ]] || { printf 'no fonts in this family (any more)\n'; return 0; }
  awk -F'\t' -v d="$d" -v r="$r" '
    {
      sp = $2 == "100" ? "mono" : $2 == "90" ? "dual" : $2 == "110" ? "charcell" : "proportional"
      if (!(sp in seen)) { seen[sp] = 1; sps = sps (sps == "" ? "" : ", ") sp }
      if (!($3 in seenf)) { seenf[$3] = 1; fmts = fmts (fmts == "" ? "" : ", ") $3 }
      styles[++n] = sprintf("  %-24s %s%s%s", $1, d, $4, r)
    }
    END {
      printf "%sspacing%s  %s\n%sformat%s   %s\n\n%s%d style%s%s\n", d, r, sps, d, r, fmts, d, n, (n == 1 ? "" : "s"), r
      for (i = 1; i <= n; i++) print styles[i]
    }' <<< "$out"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" fonts
  fonts::preview "$@"
}
