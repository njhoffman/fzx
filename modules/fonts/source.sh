#!/usr/bin/env bash
# fonts source: fontconfig's families (each font's first family name) as rows "family  sample file
# display": the style count, a mono marker and the file formats. The sample file is the family's regular
# style (Regular, Book, Normal, Roman, Medium), else its first. $FZX_TOGGLES: mono lists monospace
# families only (fontconfig spacing mono, dual or charcell).

# fonts::list: "family<TAB>style<TAB>spacing<TAB>format<TAB>file" per font file
fonts::list() {
  command fc-list --format '%{family[0]}\t%{style[0]}\t%{spacing}\t%{fontformat}\t%{file}\n' 2> /dev/null
}

fonts::source() {
  local mono=0 m=$'\e['"${FZX_COLORS[fonts_mono]:-38;5;114}m" d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ " ${FZX_TOGGLES:-} " == *" mono "* ]] && mono=1
  [[ -n "${NO_COLOR:+x}" ]] && m="" d="" r=""
  command -v fc-list > /dev/null || { printf 'fonts: needs fc-list (fontconfig)\n' >&2; return 1; }
  fonts::list | sort -t$'\t' -k1,1f -k1,1 -k2,2 | awk -F'\t' -v OFS='\t' -v mono="$mono" -v m="$m" -v d="$d" -v r="$r" '
    function pad(t, w) { return length(t) > w ? substr(t, 1, w - 1) "…" : sprintf("%-" w "s", t) }
    function flush(   kind, s) {
      if (fam == "") return
      if (mono && !ismono) { fam = ""; return }
      kind = ismono ? m "mono" r : "    "
      s = n == 1 ? "1 style" : n " styles"
      print fam, (reg != "" ? reg : first), pad(fam, 40) "  " kind "  " d pad(s, 10) "  " fmts r
      fam = ""
    }
    $1 == "" { next }
    $1 != fam {
      flush(); fam = $1; n = 0; ismono = 0; reg = ""; first = $5; fmts = ""; delete seenf
    }
    {
      n++
      if ($3 == "100" || $3 == "90" || $3 == "110") ismono = 1
      if (reg == "" && $2 ~ /^(Regular|Book|Normal|Roman|Medium)$/) reg = $5
      if ($4 != "" && !($4 in seenf)) { seenf[$4] = 1; fmts = fmts (fmts == "" ? "" : ", ") $4 }
    }
    END { flush() }'
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" fonts
  fonts::source "$@"
}
