#!/usr/bin/env bash
# colors theme: the data behind colors:theme and colors:pick. Every color setting: fzf's --color keys, with
# the values the user's fzf options give them, and fzx's FZX_COLORS, with the config layers'. Edits wait in
# the colors session's state/theme_pending until saved to ~/.config/fzx/theme.sh, a config layer of its own
# (after config.sh) that only this screen writes.
#
# Ids are fzf:KEY and fzx:KEY. fzf values are fzf's syntax (`214:bold`, `#17a9b3`, `-1`, `red:italic`),
# fzx values SGR parameters (`1;38;5;214`). A pending value "-" resets the key: it drops the saved override.

# fzf's --color keys: name, the key it falls back to ("-": none), what it colors (fzf 0.74's COLOR NAMES)
COLORS_FZF_KEYS='fg	-	text
list-fg	fg	text in the list section
selected-fg	list-fg	text of selected lines
preview-fg	fg	text in the preview
bg	-	background
list-bg	bg	background of the list section
selected-bg	list-bg	background of selected lines
preview-bg	bg	background of the preview
input-bg	bg	background of the input window
header-bg	bg	background of the header window
footer-bg	bg	background of the footer window
hl	-	highlighted substrings
selected-hl	hl	highlighted substrings of selected lines
fg+	-	text of the current line
bg+	-	background of the current line
gutter	bg+	the gutter on the left
hl+	-	highlighted substrings of the current line
alt-bg	-	alternate background, for striped lines
query	-	the query
ghost	query	ghost text (--ghost)
disabled	query	the query when search is off (--disabled)
info	-	the info line (match counters)
border	-	borders (--border, the preview)
list-border	border	border of the list section
scrollbar	list-border	the scrollbar
separator	list-border	the separator on the info line
gap-line	list-border	the line on each gap
preview-border	border	border of the preview
preview-scrollbar	preview-border	the preview scrollbar
input-border	border	border of the input window
header-border	border	border of the header window
footer-border	border	border of the footer window
label	-	border labels
list-label	label	label of the list section
preview-label	label	label of the preview
input-label	label	label of the input window
header-label	label	label of the header window
footer-label	label	label of the footer window
prompt	-	the prompt
pointer	-	pointer to the current line
marker	-	multi-select marker
spinner	-	streaming input indicator
header	-	the header
footer	-	the footer
nth	-	the --nth parts of a line (attributes only)
nomatch	-	non-matching items in raw mode'

# the picker's attribute toggles, in table order, with their SGR codes and fzf names
# shellcheck disable=SC2034  # read by source.sh and actions.sh
COLORS_ATTRS=(bold:1 dim:2 italic:3 underline:4 reverse:7)

# what a base16 preset sets: fzf key, base color (00-0F). base16-fzf's 12 keys (bg bg+ fg fg+ hl hl+ header
# info pointer marker prompt spinner, as its template sets them), and the base16 styling guide's roles for the
# rest: 00 the background, 01 a lighter one, 02 the selection's, 03 comments and borders, 04-06 text, dark to
# light. Keys left out fall back to these (the key table's parents), unless the user's fzf options set them.
COLORS_PRESET_MAP='bg 00
bg+ 01
fg 04
fg+ 06
hl 0D
hl+ 0D
header 0D
info 0A
pointer 0C
marker 0C
prompt 0A
spinner 0C
gutter 00
query 05
ghost 03
disabled 03
border 03
separator 03
label 05
selected-fg 05
selected-bg 02
selected-hl 0D
preview-fg 05
footer 0D'

# colors::presets_file: the base16 schemes (presets-gen.sh makes it)
colors::presets_file() { printf '%s/presets.tsv' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; }

# colors::preset_row <slug> <var>: the preset's row in presets.tsv (fails for one it does not have)
colors::preset_row() {
  local _row
  _row="$(awk -F'\t' -v s="$1" '$1 == s { print; exit }' "$(colors::presets_file)")"
  printf -v "$2" '%s' "$_row"
  [[ -n "$_row" ]]
}

# colors::preset_items <slug>: what the preset sets, "key<TAB>#rrggbb", in the key table's order
colors::preset_items() {
  local row
  colors::preset_row "$1" row || return 1
  {
    printf '%s\n' "$COLORS_FZF_KEYS" | sed 's/^/K\t/'
    printf '%s\n' "$COLORS_PRESET_MAP" | sed 's/^/M\t/; s/ /\t/'
    printf 'R\t%s\n' "$row"
  } | awk -F'\t' '
    $1 == "K" { n++; k[n] = $2 }
    $1 == "M" { m[$2] = $3 }
    $1 == "R" { for (i = 0; i < 16; i++) c[sprintf("%02X", i)] = $(i + 5) }
    END { for (i = 1; i <= n; i++) if (k[i] in m) print k[i] "\t#" c[m[k[i]]] }'
}

# colors::theme_preset <slug>: the preset as the pending fzf edits: every pending fzf edit goes, the preset's
# keys are set, and the saved fzf keys it does not set are reset, so its look is whole; fzx's edits stay
colors::theme_preset() {
  local f items saved
  items="$(colors::preset_items "$1")" || { printf 'colors: no preset %s\n' "$1" >&2; return 1; }
  colors::theme_pending_file f || return 1
  saved="$(colors::theme_saved)"
  {
    [[ -r "$f" ]] && awk -F'\t' '$1 !~ /^fzf:/' "$f"
    printf '%s\n' "$items" | sed 's/^/fzf:/'
    printf '%s\n' "$saved" | awk -F'\t' -v set="$(printf '%s\n' "$items" | cut -f1 | tr '\n' ' ')" '
      BEGIN { n = split(set, s, " "); for (i = 1; i <= n; i++) in_set["fzf:" s[i]] = 1 }
      $1 ~ /^fzf:/ && !($1 in in_set) { print $1 "\t-" }'
  } > "$f.tmp" && mv -- "$f.tmp" "$f"
}

# colors::theme_file: where save writes
colors::theme_file() { printf '%s/theme.sh' "${FZX_CONFIG_DIR:-$HOME/.config/fzx}"; }

# colors::_fzf_alias <key>: fzf's long names to the short ones the list shows
colors::_fzf_alias() {
  case "$1" in
    current-fg) printf 'fg+' ;;
    current-bg) printf 'bg+' ;;
    current-hl) printf 'hl+' ;;
    input-fg) printf 'query' ;;
    header-fg) printf 'header' ;;
    footer-fg) printf 'footer' ;;
    *) printf '%s' "$1" ;;
  esac
}

# colors::_shell_words: stdin split into words the way fzf reads its options file and FZF_DEFAULT_OPTS:
# whitespace between words, single and double quotes, backslash escapes; a line starting with # is a
# comment. One word per line, newlines inside a word turned into spaces (--color takes either).
colors::_shell_words() {
  awk '
    /^[ \t]*#/ { next }
    { text = text $0 "\n" }
    END {
      n = length(text); w = ""; inw = 0; q = ""
      for (i = 1; i <= n; i++) {
        c = substr(text, i, 1)
        if (q == "\047") { if (c == "\047") q = ""; else w = w (c == "\n" ? " " : c); continue }
        if (q == "\"") {
          if (c == "\"") q = ""
          else if (c == "\\" && i < n) { i++; c = substr(text, i, 1); w = w c }
          else w = w (c == "\n" ? " " : c)
          continue
        }
        if (c == "\047" || c == "\"") { q = c; inw = 1; continue }
        if (c == "\\" && i < n) { i++; c = substr(text, i, 1); if (c != "\n") w = w c; inw = 1; continue }
        if (c == " " || c == "\t" || c == "\n") { if (inw) print w; w = ""; inw = 0; continue }
        w = w c; inw = 1
      }
      if (inw) print w
    }'
}

# colors::_color_items: --color specs (one per line on stdin) as "key<TAB>value" lines, aliases resolved;
# a base scheme (dark, light, 16, bw) as "base<TAB>NAME"
colors::_color_items() {
  local spec item key
  while IFS= read -r spec; do
    for item in ${spec//,/ }; do
      if [[ "$item" == *:* ]]; then
        key="$(colors::_fzf_alias "${item%%:*}")"
        printf '%s\t%s\n' "$key" "${item#*:}"
      else
        printf 'base\t%s\n' "$item"
      fi
    done
  done
}

# colors::_fzf_specs: the --color specs of the user's fzf options, in the order fzf reads them: the options
# file, then FZF_DEFAULT_OPTS
colors::_fzf_specs() {
  local prev="" w
  {
    [[ -n "${FZF_DEFAULT_OPTS_FILE:-}" && -r "$FZF_DEFAULT_OPTS_FILE" ]] && colors::_shell_words < "$FZF_DEFAULT_OPTS_FILE"
    [[ -n "${FZF_DEFAULT_OPTS:-}" ]] && colors::_shell_words <<< "$FZF_DEFAULT_OPTS"
  } | while IFS= read -r w; do
    if [[ "$prev" == --color ]]; then
      printf '%s\n' "$w"
    elif [[ "$w" == --color=* ]]; then
      printf '%s\n' "${w#--color=}"
    fi
    prev="$w"
  done
}

# colors::theme_saved: the saved overrides in theme.sh, "id<TAB>value" (it is read, not sourced, here)
colors::theme_saved() {
  local f line re_fzf re_fzx
  f="$(colors::theme_file)"
  [[ -r "$f" ]] || return 0
  re_fzf='^FZX_FZF_COLORS\+="\$\{FZX_FZF_COLORS:\+,\}(.*)"$'
  re_fzx='^FZX_COLORS\[([A-Za-z0-9_]+)\]="(.*)"$'
  while IFS= read -r line; do
    if [[ "$line" =~ $re_fzf ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}" | colors::_color_items | awk -F'\t' '$1 != "base" { print "fzf:" $1 "\t" $2 }'
    elif [[ "$line" =~ $re_fzx ]]; then
      printf 'fzx:%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
  done < "$f"
}

# colors::theme_pending_file <var>: the pending edits of the colors session (the parent when called from
# colors:pick or colors:presets)
colors::theme_pending_file() {
  local _dir="${FZX_SESSION_DIR:-}" _mode="" _parent=""
  [[ -n "$_dir" ]] || { printf -v "$1" '%s' "" && return 1; }
  fzx::_kv_get "$_dir/state/mode" _mode 2> /dev/null || :
  if [[ "$_mode" == pick || "$_mode" == presets ]] && fzx::_kv_get "$_dir/meta/parent" _parent 2> /dev/null; then
    _dir="$FZX_SESSIONS_DIR/$_parent"
  fi
  printf -v "$1" '%s' "$_dir/state/theme_pending"
}

# colors::theme_pending: the pending edits, "id<TAB>value", the last one per id
colors::theme_pending() {
  local f
  colors::theme_pending_file f || return 0
  [[ -r "$f" ]] || return 0
  awk -F'\t' '{ v[$1] = $2; if (!($1 in o)) { o[$1] = ++n; k[n] = $1 } } END { for (i = 1; i <= n; i++) print k[i] "\t" v[k[i]] }' "$f"
}

# colors::theme_pend <id> <value>: record an edit ("-": reset the key)
colors::theme_pend() {
  local f
  colors::theme_pending_file f || return 1
  printf '%s\t%s\n' "$1" "$2" >> "$f"
}

# colors::theme_unpend <id...>: forget the pending edits of these ids
colors::theme_unpend() {
  local f id tmp
  colors::theme_pending_file f || return 1
  [[ -f "$f" ]] || return 0
  tmp="$f.tmp"
  cp -- "$f" "$tmp"
  for id; do awk -F'\t' -v id="$id" '$1 != id' "$tmp" > "$tmp.1" && mv -- "$tmp.1" "$tmp"; done
  mv -- "$tmp" "$f"
}

# colors::_is_bg <fzf key>: the key colors a background
colors::_is_bg() { [[ "$1" == bg || "$1" == bg+ || "$1" == *-bg || "$1" == gutter ]]; }

# colors::fzf_sgr <value> <bg 0|1> <var>: an fzf color value as SGR parameters (empty: nothing to draw)
colors::fzf_sgr() {
  local _v="$2" _t _out=() _n _names=(black red green yellow blue magenta cyan white) _i _base
  local IFS=:
  for _t in $1; do
    case "$_t" in
      bold) _out+=(1) ;;
      dim) _out+=(2) ;;
      italic) _out+=(3) ;;
      underline) _out+=(4) ;;
      blink) _out+=(5) ;;
      reverse) _out+=(7) ;;
      strikethrough) _out+=(9) ;;
      -1) _out+=($((_v ? 49 : 39))) ;;
      \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
        _out+=("$((_v ? 48 : 38));2;$((16#${_t:1:2}));$((16#${_t:3:2}));$((16#${_t:5:2}))")
        ;;
      *)
        if [[ "$_t" =~ ^[0-9]+$ ]] && ((_t < 256)); then
          _out+=("$((_v ? 48 : 38));5;$_t")
        else
          _n="${_t#bright-}"
          for _i in "${!_names[@]}"; do
            [[ "${_names[_i]}" == "$_n" ]] || continue
            _base=$((_n == _t ? 30 : 90))
            [[ "$_t" == bright-* ]] && _base=90
            _out+=($((_base + _i + (_v ? 10 : 0))))
          done
        fi
        ;;
    esac
  done
  IFS=';'
  printf -v "$3" '%s' "${_out[*]}"
}

# colors::fzx_table_first: FZX_COLORS keys once each, "key<TAB>value<TAB>owner", as the layers give them
# without theme.sh (FZX_THEME_SKIP): fzx's own, then the modules' keys fzx does not have
# It loads every module's config (seconds), and the theme does not change it, so the colors session keeps
# it (state/theme_fzx_table)
colors::fzx_table_first() {
  local f="" cache=""
  colors::theme_pending_file f 2> /dev/null && cache="${f%/theme_pending}/theme_fzx_table"
  if [[ -n "$cache" && -s "$cache" ]]; then
    cat -- "$cache"
    return
  fi
  if [[ -n "$cache" ]]; then
    FZX_THEME_SKIP=1 colors::fzx_table | awk -F'\t' '!seen[$1]++' | tee -- "$cache"
  else
    FZX_THEME_SKIP=1 colors::fzx_table | awk -F'\t' '!seen[$1]++'
  fi
}

# colors::_fzx_fzf_colors_base: FZX_FZF_COLORS as the layers give it without theme.sh
colors::_fzx_fzf_colors_base() {
  (
    FZX_FZF_COLORS=""
    FZX_THEME_SKIP=1 fzx::config_load "" "" > /dev/null 2>&1
    printf '%s\n' "${FZX_FZF_COLORS:-}"
  )
}

# colors::theme_values: every setting with what it is now and where that comes from,
# "id<TAB>value<TAB>origin<TAB>description<TAB>value without the theme", value empty for a key nothing
# sets. origin: pending, reset (pending), theme (saved), fzx (FZX_FZF_COLORS in config.sh), fzf (the
# user's fzf options), default (fzx's defaults), or the module whose config sets it.
colors::theme_values() {
  local saved pending fzfopts fzxopts
  saved="$(colors::theme_saved)"
  pending="$(colors::theme_pending)"
  fzfopts="$(colors::_fzf_specs | colors::_color_items)"
  fzxopts="$(colors::_fzx_fzf_colors_base | colors::_color_items)"
  {
    printf '%s\n' "$COLORS_FZF_KEYS" | sed 's/^/K\t/'
    [[ -n "$fzfopts" ]] && printf '%s\n' "$fzfopts" | sed 's/^/F\t/'
    [[ -n "$fzxopts" ]] && printf '%s\n' "$fzxopts" | sed 's/^/X\t/'
    colors::fzx_table_first | sed 's/^/C\t/'
    [[ -n "$saved" ]] && printf '%s\n' "$saved" | sed 's/^/S\t/'
    [[ -n "$pending" ]] && printf '%s\n' "$pending" | sed 's/^/P\t/'
  } | awk -F'\t' '
    $1 == "K" { n++; id[n] = "fzf:" $2; desc[id[n]] = $4 }
    $1 == "F" && $2 != "base" { v["fzf:" $2] = $3; o["fzf:" $2] = "fzf" }
    $1 == "X" && $2 != "base" { v["fzf:" $2] = $3; o["fzf:" $2] = "fzx" }
    $1 == "C" { k = "fzx:" $2; n++; id[n] = k; desc[k] = "FZX_COLORS[" $2 "]"; v[k] = $3; o[k] = ($4 == "fzx" ? "default" : $4) }
    $1 == "S" { sv[$2] = $3 }
    $1 == "P" { pv[$2] = $3 }
    END {
      for (i = 1; i <= n; i++) {
        k = id[i]; base = v[k]; val = base; org = (k in o) ? o[k] : "default"
        if (k in sv) { val = sv[k]; org = "theme" }
        if (k in pv) { if (pv[k] == "-") { val = base; org = "reset" } else { val = pv[k]; org = "pending" } }
        print k "\t" val "\t" org "\t" desc[k] "\t" base
      }
    }'
}
