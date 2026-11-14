#!/usr/bin/env bash
# header: a list's header row, naming its columns, the one it is sorted by marked (FZX_SORTED_SHOW header or
# both). Sources print it first and fzf shows it through --header-lines=1, which opts_build adds when
# FZX_SORT_HEADER is 1 (lib/components.sh sets it per view). Cells are padded like the rows' columns and
# colored in the text only: FZX_COLORS[header_column] (empty: fzf's header color), the sorted one in
# FZX_COLORS[header_sorted] followed by the arrow of the sort's direction (FZX_SORTED_ARROWS).

# fzx::header_arrow <var>: the current sort's arrow (FZX_SORT_DESC picks descending), "" for none
fzx::header_arrow() {
  local _a=() _x
  read -r -a _a <<< "${FZX_SORTED_ARROWS-↑ ↓}"
  _x="${_a[${FZX_SORT_DESC:-0} == 1 ? 1 : 0]:-${_a[0]:-}}"
  printf -v "$1" '%s' "$_x"
}

# fzx::header_width <text>: the text's width in columns (characters, whatever the locale)
fzx::header_width() {
  printf '%s' "$1" | LC_ALL=C.UTF-8 wc -m
}

# fzx::header_vars: FZX_HEADER_VARS (awk -v arguments) and FZX_HEADER_AWK (awk functions) for a source that
# builds its rows in awk:
#   hon                  1 when the view has a header row (FZX_SORT_HEADER)
#   hwidth(name, on)     the cell's width: the name, plus the arrow when on (the sorted column)
#   hcell(name, w, right, on)
#                        the cell padded to w (right-aligned when right), the padding uncolored
# Prepend FZX_HEADER_AWK to the program: awk "${FZX_HEADER_VARS[@]}" "$FZX_HEADER_AWK"'...'
fzx::header_vars() {
  local arrow col="${FZX_COLORS[header_column]:-}" srt="${FZX_COLORS[header_sorted]:-1}" aw=0
  fzx::header_arrow arrow
  [[ -n "$arrow" ]] && aw="$(fzx::header_width "$arrow")"
  [[ -n "${NO_COLOR:+x}" ]] && col="" srt=""
  # shellcheck disable=SC2034  # read by the sources
  FZX_HEADER_VARS=(-v "hon=${FZX_SORT_HEADER:-0}" -v "hcol=$col" -v "hsort=$srt" -v "harrow=$arrow" -v "harroww=$aw")
  # shellcheck disable=SC2034
  FZX_HEADER_AWK='
    function hwidth(name, on) { return length(name) + (on ? harroww : 0) }
    function hcell(name, w, right, on,  t, n, code, p) {
      n = hwidth(name, on); t = name (on ? harrow : ""); code = on ? hsort : hcol
      if (code != "" && t != "") t = "\033[" code "m" t "\033[0m"
      p = w > n ? sprintf("%" (w - n) "s", "") : ""
      return right ? p t : t p
    }
  '
}

# fzx::header_cell <var> <name> <width> <right 0|1> <on 0|1>: hcell for sources that build rows in bash
fzx::header_cell() {
  local -n _hc_out="$1"
  local _name="$2" _w="$3" _right="$4" _on="$5" _t _n _code _p="" _arrow=""
  ((_on)) && fzx::header_arrow _arrow
  _t="$_name$_arrow"
  _n="${#_name}"
  [[ -n "$_arrow" ]] && _n=$((_n + $(fzx::header_width "$_arrow")))
  if ((_on)); then _code="${FZX_COLORS[header_sorted]:-1}"; else _code="${FZX_COLORS[header_column]:-}"; fi
  [[ -n "${NO_COLOR:+x}" ]] && _code=""
  [[ -n "$_code" && -n "$_t" ]] && _t=$'\e['"${_code}m$_t"$'\e[0m'
  ((_w > _n)) && printf -v _p '%*s' $((_w - _n)) ''
  if ((_right)); then _hc_out="$_p$_t"; else _hc_out="$_t$_p"; fi
}

# fzx::header_print [-z] <hidden fields> <sorted name> [<name> <width> <right 0|1>]...: the header row, when the
# view has one (FZX_SORT_HEADER): that many empty tab-separated fields (the rows' ids), then the cells, one
# space apart, the one named <sorted> marked (the last cell's width is usually 0: unpadded; an empty cell of
# width 0 makes a two-space gap). A cell named "\t" (width and alignment ignored) is a field break after the
# previous cell's space. -z ends it with NUL, for a list read with --read0
fzx::header_print() {
  [[ "${FZX_SORT_HEADER:-0}" == 1 ]] || return 0
  local nul=0
  [[ "$1" == -z ]] && nul=1 && shift
  local fields="$1" sorted="$2" line="" cell i
  shift 2
  for ((i = 0; i < fields; i++)); do line+=$'\t'; done
  while (($# >= 3)); do
    if [[ "$1" == $'\t' ]]; then
      line+=$'\t'
      shift 3
      continue
    fi
    fzx::header_cell cell "$1" "$2" "$3" "$([[ -n "$1" && "$1" == "$sorted" ]] && echo 1 || echo 0)"
    line+="$cell"
    shift 3
    (($#)) && line+=" "
  done
  if ((nul)); then printf '%s\0' "$line"; else printf '%s\n' "$line"; fi
}
