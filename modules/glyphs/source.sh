#!/usr/bin/env bash
# glyphs source. Lines are "glyph<TAB>code points<TAB>name<TAB>group<TAB>display": the glyph is what enter
# prints and ctrl-y copies, the code points are hex and space-separated (an emoji may be several), the group
# is a Nerd Font's set (cod, md, ...), a character's Unicode block or an emoji's group and subgroup.
# blocks rows are "name<TAB>first..last<TAB>name<TAB>-<TAB>display".
# Mode from $FZX_MODE: nerd (the module's data/glyphnames.json, or the one `update` downloaded), unicode
# (FZX_GLYPHS_UNICODE_DIR's UnicodeData.txt; `--block NAME`: that block's only), blocks (Blocks.txt), emoji
# (emoji/emoji-test.txt, fully-qualified ones). Each list is built once into $FZX_CACHE_DIR/glyphs and again
# when its source is newer.

GLYPHS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# glyphs::args [--block NAME] [--]: GLYPHS_BLOCK
glyphs::args() {
  declare -g GLYPHS_BLOCK=""
  while (($#)); do
    case "$1" in
      --block) GLYPHS_BLOCK="${2:-}" && shift 2 ;;
      --) shift; break ;;
      *) printf 'glyphs: unknown argument: %s\n' "$1" >&2; return 2 ;;
    esac
  done
}

# glyphs::nerd_json: the glyph names in use: the downloaded ones when there are, else the module's own
glyphs::nerd_json() {
  local f="$FZX_CACHE_DIR/glyphs/glyphnames.json"
  [[ -s "$f" ]] || f="$GLYPHS_DIR/data/glyphnames.json"
  printf '%s\n' "$f"
}

# glyphs::_unicode_file <name>: a file of the Unicode data, or a message and failure
glyphs::_unicode_file() {
  local f="${FZX_GLYPHS_UNICODE_DIR:-/usr/share/unicode}/$1"
  [[ -r "$f" ]] || {
    printf 'glyphs: no %s (FZX_GLYPHS_UNICODE_DIR; Debian and Ubuntu: the unicode-data package)\n' "$f" >&2
    return 2
  }
  printf '%s\n' "$f"
}

# glyphs::cached <name> <source file> <builder...>: the cache file, built from the source when it is missing
# or older than the source (only on success)
glyphs::cached() {
  local name="$1" src="$2" file tmp
  shift 2
  file="$FZX_CACHE_DIR/glyphs/$name"
  if [[ ! -s "$file" || "$src" -nt "$file" ]]; then
    mkdir -p -- "${file%/*}" || return
    tmp="$file.$BASHPID"
    if ! "$@" > "$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
    mv -f -- "$tmp" "$file"
  fi
  printf '%s\n' "$file"
}

# the awk function writing a code point's UTF-8 bytes (run under LC_ALL=C, so %c is a byte)
GLYPHS_AWK_UTF8='
  function hex(s,   i, n) { n = 0; s = toupper(s); for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789ABCDEF", substr(s, i, 1)) - 1; return n }
  function utf8(c) {
    if (c < 128) return sprintf("%c", c)
    if (c < 2048) return sprintf("%c%c", 192 + int(c / 64), 128 + c % 64)
    if (c < 65536) return sprintf("%c%c%c", 224 + int(c / 4096), 128 + int(c / 64) % 64, 128 + c % 64)
    return sprintf("%c%c%c%c", 240 + int(c / 262144), 128 + int(c / 4096) % 64, 128 + int(c / 64) % 64, 128 + c % 64) }'

# glyphs::_build_nerd <json>: "glyph  code  nf-name  set" per glyph, by name
glyphs::_build_nerd() {
  command jq -r 'to_entries[] | select(.key != "METADATA") |
    [.value.char, (.value.code | ascii_upcase), "nf-" + .key, (.key | split("-")[0])] | join("\t")' -- "$1" |
    LC_ALL=C sort -t $'\t' -k3,3
}

# glyphs::_build_unicode <UnicodeData.txt> <Blocks.txt>: "glyph  code  name  block" per named character:
# controls, surrogates, private use and the ranges ("<CJK Ideograph, First>") left out; names in lower case
glyphs::_build_unicode() {
  LC_ALL=C awk -F';' "$GLYPHS_AWK_UTF8"'
    NR == FNR { if ($0 ~ /^[0-9A-F]/) { split($1, r, /\.\./); nb++; lo[nb] = hex(r[1]); hi[nb] = hex(r[2]); bn[nb] = substr($2, 2) } next }
    $2 ~ /^</ || $3 ~ /^(Cc|Cs|Co)$/ { next }
    { c = hex($1); while (b <= nb && hi[b] < c) b++
      printf "%s\t%s\t%s\t%s\t%s\n", utf8(c), $1, tolower($2), (b <= nb && lo[b] <= c ? bn[b] : "-"), $3 }' \
    b=1 "$2" "$1"
}

# glyphs::_build_emoji <emoji-test.txt>: "emoji  code points  name  group / subgroup" per fully-qualified emoji
glyphs::_build_emoji() {
  awk '
    /^# group: / { g = substr($0, 10); next }
    /^# subgroup: / { s = substr($0, 13); next }
    /; fully-qualified / {
      cp = $0; sub(/ *;.*/, "", cp)
      rest = $0; sub(/^[^#]*# /, "", rest)
      e = rest; sub(/ .*/, "", e)
      name = rest; sub(/^[^ ]+ E[0-9.]+ /, "", name)
      printf "%s\t%s\t%s\t%s / %s\n", e, cp, name, g, s }' "$1"
}

# glyphs::nerd: the Nerd Font rows: the glyph, its name with the set dimmed, the code point
glyphs::nerd() {
  local file n=$'\e[38;5;180m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && n="" d="" r=""
  file="$(glyphs::cached nerd.tsv "$(glyphs::nerd_json)" glyphs::_build_nerd "$(glyphs::nerd_json)")" || return
  awk -F'\t' -v OFS='\t' -v n="$n" -v d="$d" -v r="$r" '
    { rest = substr($3, length($4) + 5)
      print $1, $2, $3, $4, sprintf("%s  %snf-%s-%s%s%s%*s %sU+%s%s", $1, d, $4, r, n, rest, 44 - length($3), "", d, $2, r) }' "$file"
}

# glyphs::unicode: the named characters (a block's only with --block), with the block dimmed; a combining
# mark is shown on a dotted circle
glyphs::unicode() {
  local data blocks file n=$'\e[38;5;152m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && n="" d="" r=""
  data="$(glyphs::_unicode_file UnicodeData.txt)" && blocks="$(glyphs::_unicode_file Blocks.txt)" || return 2
  file="$(glyphs::cached unicode.tsv "$data" glyphs::_build_unicode "$data" "$blocks")" || return
  awk -F'\t' -v OFS='\t' -v n="$n" -v d="$d" -v r="$r" -v block="${GLYPHS_BLOCK:-}" '
    block != "" && $4 != block { next }
    { shown = $5 ~ /^M[ne]$/ ? "◌" $1 : $1
      print $1, $2, $3, $4, sprintf("%s  %sU+%-6s%s %s%s%s  %s%s%s", shown, d, $2, r, n, $3, r, d, $4, r) }' "$file"
}

# glyphs::blocks: the Unicode blocks with their first visible character, range and how many named
# characters each has
glyphs::blocks() {
  local data blocks file n=$'\e[38;5;152m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && n="" d="" r=""
  data="$(glyphs::_unicode_file UnicodeData.txt)" && blocks="$(glyphs::_unicode_file Blocks.txt)" || return 2
  file="$(glyphs::cached unicode.tsv "$data" glyphs::_build_unicode "$data" "$blocks")" || return
  awk -F'\t' -v OFS='\t' -v n="$n" -v d="$d" -v r="$r" '
    # the first visible character stands for the block (not a space or a combining mark)
    NR == FNR { count[$4]++; if (first[$4] == "" && $5 !~ /^(Z|M)/) first[$4] = $1; next }
    /^[0-9A-F]/ { split($0, p, /; */); name = p[2]; range = p[1]
      print name, range, name, "-", sprintf("%s %s%-40s%s %s%-14s %6d%s", (first[name] == "" ? " " : first[name]), n, name, r, d, range, count[name], r) }' \
    "$file" FS=';' "$blocks"
}

# glyphs::emoji: the fully-qualified emoji with their group and subgroup
glyphs::emoji() {
  local test file n=$'\e[38;5;223m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && n="" d="" r=""
  test="$(glyphs::_unicode_file emoji/emoji-test.txt)" || return 2
  file="$(glyphs::cached emoji.tsv "$test" glyphs::_build_emoji "$test")" || return
  awk -F'\t' -v OFS='\t' -v n="$n" -v d="$d" -v r="$r" '
    { print $1, $2, $3, $4, sprintf("%s  %s%-48s%s %s%s%s", $1, n, $3, r, d, $4, r) }' "$file"
}

glyphs::source() {
  glyphs::args "$@" || return
  case "${FZX_MODE:-nerd}" in
    nerd) glyphs::nerd ;;
    unicode) glyphs::unicode ;;
    blocks) glyphs::blocks ;;
    emoji) glyphs::emoji ;;
    *)
      printf 'glyphs: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$GLYPHS_DIR" glyphs
  glyphs::source "$@"
}
