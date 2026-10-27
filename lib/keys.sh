#!/usr/bin/env bash
# keys: which keys are taken (fzx, the user's fzf options, fzf's defaults) and which are free.
# `fzx keys [KEY...]` prints the page; the help key (f1) runs it with the keys the screen binds.

# fzf's default bindings (fzf 0.74 man page, AVAILABLE ACTIONS), "key<TAB>action"
FZX_FZF_DEFAULT_BINDS='alt-b	backward-word
alt-bs	backward-kill-word
alt-d	kill-word
alt-down	down-match
alt-f	forward-word
alt-left	backward-word
alt-right	forward-word
alt-/	toggle-wrap-word
alt-up	up-match
bspace	backward-delete-char
btab	toggle+up
ctrl-a	beginning-of-line
ctrl-b	backward-char
ctrl-bspace	backward-delete-char
ctrl-c	abort
ctrl-d	delete-char/eof
ctrl-e	end-of-line
ctrl-f	forward-char
ctrl-g	abort
ctrl-h	backward-delete-char
ctrl-j	down
ctrl-k	up
ctrl-l	clear-screen
ctrl-n	down-match
ctrl-p	up-match
ctrl-q	abort
ctrl-/	toggle-wrap-word
ctrl-u	unix-line-discard
ctrl-w	unix-word-rubout
ctrl-y	yank
del	delete-char
double-click	accept
down	down
end	end-of-line
enter	accept
esc	abort
home	beginning-of-line
left	backward-char
pgdn	page-down
pgup	page-up
right	forward-char
shift-down	preview-down
shift-left	backward-word
shift-right	forward-word
shift-up	preview-up
tab	toggle+down
up	up'

# fzx::key_name <key> <var>: fzf's synonyms folded into one name
fzx::key_name() {
  local _k="$1"
  case "$_k" in
    return | ctrl-m) _k=enter ;;
    ctrl-i) _k=tab ;;
    shift-tab) _k=btab ;;
    bs) _k=bspace ;;
    page-up) _k=pgup ;;
    page-down) _k=pgdn ;;
    delete) _k=del ;;
    alt-bspace) _k=alt-bs ;;
  esac
  printf -v "$2" '%s' "$_k"
}

# fzx::key_label <key> <var> [style]: how a key is shown (FZX_KEY_STYLE, or the style given): full (fzf's
# name, ctrl-x alt-left), short (^X M-x C-M-left S-up) or glyph (⌃X ⌥x ⌃⌥← ⇧↑). Only for display: config
# and binds keep fzf's names.
fzx::key_label() {
  local _k="$1" _style="${3:-${FZX_KEY_STYLE:-full}}" _mods="" _base _out=""
  if [[ "$_style" != short && "$_style" != glyph ]]; then
    printf -v "$2" '%s' "$_k"
    return
  fi
  _base="$_k"
  # the modifiers in front; a trailing "-" (alt--) is the key itself
  while [[ "$_base" =~ ^(ctrl|alt|shift)-(.+)$ ]]; do
    _mods+="${BASH_REMATCH[1]:0:1}"
    _base="${BASH_REMATCH[2]}"
  done
  # alt-X (alt and a capital) is alt-shift-x
  [[ "$_base" =~ ^[A-Z]$ ]] && _mods+=s
  [[ "$_base" == btab || "$_base" == shift-tab ]] && _mods+=s _base=tab
  if [[ "$_style" == short ]]; then
    if [[ "$_mods" == c && ${#_base} -eq 1 ]]; then
      _out="^${_base^^}"
    else
      [[ "$_mods" == *c* ]] && _out+="C-"
      [[ "$_mods" == *a* ]] && _out+="M-"
      [[ "$_mods" == *s* && ! "$_base" =~ ^[A-Z]$ ]] && _out+="S-"
      _out+="$_base"
    fi
  else
    [[ "$_mods" == *c* ]] && _out+="⌃"
    [[ "$_mods" == *a* ]] && _out+="⌥"
    [[ "$_mods" == *s* ]] && _out+="⇧"
    case "$_base" in
      left) _base="←" ;; right) _base="→" ;; up) _base="↑" ;; down) _base="↓" ;;
      enter | return) _base="↵" ;; tab) _base="⇥" ;; bspace | bs) _base="⌫" ;; del | delete) _base="⌦" ;;
      esc) _base="⎋" ;; space) _base="␣" ;; home) _base="↖" ;; end) _base="↘" ;;
      pgup | page-up) _base="⇞" ;; pgdn | page-down) _base="⇟" ;;
      f[0-9]*) _base="F${_base#f}" ;;
      [a-z]) [[ "$_mods" == *c* ]] && _base="${_base^^}" ;;
    esac
    _out+="$_base"
  fi
  printf -v "$2" '%s' "$_out"
}

# fzx::pad <text> <width>: the text padded with spaces to width characters (printf pads by bytes)
fzx::pad() {
  local _n=$(($2 - ${#1}))
  ((_n > 0)) || _n=0
  printf '%s%*s' "$1" "$_n" ""
}

# fzx::user_binds: "key<TAB>action" for every --bind in FZF_DEFAULT_OPTS_FILE, then FZF_DEFAULT_OPTS
# (later wins, as in fzf). The options are split into shell words without evaluating anything (single and
# double quotes, backslash escapes and continuations, # comments at the start of a word). A --bind value
# may hold several bindings: a comma starts a new one when what follows up to the next ":" looks like a
# key name. Newlines inside an action become spaces.
fzx::user_binds() {
  {
    [[ -n "${FZF_DEFAULT_OPTS_FILE:-}" && -r "$FZF_DEFAULT_OPTS_FILE" ]] && cat -- "$FZF_DEFAULT_OPTS_FILE"
    printf '\n%s\n' "${FZF_DEFAULT_OPTS:-}"
  } | awk '
    function word(w) { if (next_bind) { binds(w); next_bind = 0 }
      else if (w == "--bind") next_bind = 1
      else if (substr(w, 1, 7) == "--bind=") binds(substr(w, 8)) }
    function binds(s,   c, key, rest, act, i, tail, k) {
      gsub(/\n/, " ", s)
      while (length(s)) {
        c = index(s, ":"); if (c < 2) return
        key = substr(s, 1, c - 1); rest = substr(s, c + 1); act = rest; s = ""
        for (i = 1; i <= length(rest); i++) {
          if (substr(rest, i, 1) != ",") continue
          tail = substr(rest, i + 1); k = index(tail, ":")
          if (k > 1 && k <= 16 && substr(tail, 1, k - 1) ~ /^[A-Za-z0-9_\/?-]+$/) {
            act = substr(rest, 1, i - 1); s = tail; break }
        }
        printf "%s\t%s\n", key, act
      } }
    { text = text $0 "\n" }
    END {
      n = length(text); w = ""; have = 0; q = ""
      for (i = 1; i <= n; i++) {
        c = substr(text, i, 1)
        if (q == "\047") { if (c == "\047") q = ""; else w = w c }
        else if (q == "\"") {
          if (c == "\"") q = ""
          else if (c == "\\" && index("\"\\$`\n", substr(text, i + 1, 1))) { i++; if (substr(text, i, 1) != "\n") w = w substr(text, i, 1) }
          else w = w c }
        else if (c == "\047" || c == "\"") { q = c; have = 1 }
        else if (c == "\\") { i++; if (substr(text, i, 1) != "\n") { w = w substr(text, i, 1); have = 1 } }
        else if (c ~ /[ \t\n]/) { if (have) word(w); w = ""; have = 0 }
        else if (c == "#" && !have) { while (i <= n && substr(text, i, 1) != "\n") i++ }
        else { w = w c; have = 1 }
      }
      if (have) word(w)
    }'
}

# fzx::keys_page [ENTRY...]: the shortcuts page (the help key, f1). Each ENTRY is one of
#   m:MODULE                              the screen's module (its section title)
#   k:SCOPE<TAB>KEY<TAB>DESCRIPTION       a key the screen binds; SCOPE is the module's name or "fzx"
#   c:KIND<TAB>NAME<TAB>KEY<TAB>DESC      a component row (mode, toggle, sort, action)
#   KEY                                   a key fzx binds, without a description (`fzx keys ctrl-r` by hand)
#   s:STYLE                               how keys are shown (FZX_KEY_STYLE: full, short, glyph)
#   l:grid                                the grid layout: every key by modifier, colored by who binds it
# With --toggle first, it prints the fzf actions for the help key instead: the list, or the grid when the
# list is what the key showed last (FZF_ACTION is still its show-preview), so pressing it again switches.
# Sections: the components, this screen's keys, fzx's keys, the global keys (the user's FZF_DEFAULT_OPTS(_FILE)
# binds, then fzf's defaults; the first that binds a key wins), then the free keys. A key fzx takes
# over from a global binding says what it shadows.
fzx::keys_page() {
  if [[ "${1:-}" == --toggle ]]; then
    shift
    local cmd
    if [[ "${FZF_ACTION:-}" == show-preview ]]; then
      printf -v cmd '%q ' "$FZX_BIN" keys "$@" l:grid
      # ignore: what FZF_ACTION shows next, so a third press brings the list back
      printf 'ignore+preview:%s' "$cmd"
    else
      printf -v cmd '%q ' "$FZX_BIN" keys "$@"
      printf 'show-preview+preview:%s' "$cmd"
    fi
    return 0
  fi
  local -A user=() def=() all=() mine=()
  local module="" entry k a name scope desc width rows_mod=() rows_fzx=() comps=() layout=list label
  local FZX_KEY_STYLE="${FZX_KEY_STYLE:-full}"
  local r=$'\e[0m' b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m"
  local cap=$'\e['"${FZX_COLORS[help_key]:-1;38;5;255;48;5;236}m"
  width="${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}"
  # the screen's mode (its session's, which follows in-place switches) and the module's modes: a key
  # whose description is scoped by mode ("status: stage; log: cherry-pick") shows this mode's part, and
  # is left out where no part names the mode
  local cur_mode="${FZX_MODE:-}" modes=() prefix scoped
  [[ -n "${FZX_SESSION_DIR:-}" && -f "$FZX_SESSION_DIR/state/mode" ]] && cur_mode="$(< "$FZX_SESSION_DIR/state/mode")"
  for entry in "$@"; do
    [[ "$entry" == c:mode$'\t'* ]] || continue
    IFS=$'\t' read -r _ name _ <<< "${entry#c:}"
    modes+=("$name")
  done
  fzx::require components
  for entry in "$@"; do
    case "$entry" in
      m:*) module="${entry#m:}" ;;
      s:*) FZX_KEY_STYLE="${entry#s:}" ;;
      l:*) layout="${entry#l:}" ;;
      c:*) comps+=("${entry#c:}") ;;
      k:*)
        IFS=$'\t' read -r scope k desc <<< "${entry#k:}"
        fzx::key_name "$k" name
        [[ -n "${mine[$name]:-}" ]] && continue
        if [[ "$scope" != fzx ]] && ((${#modes[@]})); then
          prefix=""
          [[ "$desc" =~ ^((default )?action: ) ]] && prefix="${BASH_REMATCH[1]}"
          # bound but idle in this mode: taken (not free), not listed
          if ! fzx::mode_desc "${desc#"$prefix"}" "$cur_mode" scoped "${modes[@]}"; then
            mine[$name]="$scope" all[$name]=1
            continue
          fi
          desc="$prefix$scoped"
        fi
        mine[$name]="$scope" all[$name]=1
        if [[ "$scope" == fzx ]]; then rows_fzx+=("$name"$'\t'"$desc"); else rows_mod+=("$name"$'\t'"$desc"); fi
        ;;
      *)
        fzx::key_name "$entry" name
        [[ -n "${mine[$name]:-}" ]] && continue
        mine[$name]=fzx all[$name]=1
        rows_fzx+=("$name"$'\t')
        ;;
    esac
  done
  while IFS=$'\t' read -r k a; do
    [[ -n "$k" ]] || continue
    fzx::key_name "$k" name
    user[$name]="$a" all[$name]=1
  done < <(fzx::user_binds)
  while IFS=$'\t' read -r k a; do
    def[$k]="$a" all[$k]=1
  done <<< "$FZX_FZF_DEFAULT_BINDS"

  # _keys_title <color key> <title> <subtitle>
  _keys_title() {
    local c=$'\e['"${FZX_COLORS[$1]:-1}m"
    printf '\n%s▌ %s%s  %s%s%s\n' "$c" "$2" "$r" "$d" "$3" "$r"
  }
  # _keys_row <key> <description> [note] [tag]: a keycap, an optional source tag ("yours", "fzf"), the
  # description and the dim note (what it shadows), cut to the preview's width
  _keys_row() {
    local key="$1" text="$2" note="${3:-}" tag="${4:-}" room
    room=$((width - 19 - (${#tag} ? 7 : 0)))
    ((room < 20)) && room=20
    # the note gives way first (down to 12 columns), then the description
    if [[ -n "$note" ]]; then
      local fit=$((room - ${#text} - 2))
      ((fit < 12)) && fit=12
      ((${#note} > fit)) && note="${note:0:fit-1}…"
      ((${#text} + ${#note} + 2 > room)) && text="${text:0:room-${#note}-3}…"
      note="  $d$note$r"
    fi
    ((${#text} > room)) && text="${text:0:room-1}…"
    case "$tag" in
      yours) tag=$'\e['"${FZX_COLORS[help_global]:-1}m"'yours '"$r " ;;
      fzf) tag="${d}fzf   $r " ;;
    esac
    fzx::key_label "$key" label
    printf '  %s %s %s %s%s%s\n' "$cap" "$(fzx::pad "$label" 12)" "$r" "$tag" "$text" "$note"
  }
  # what a fzx key takes over from the global bindings
  _keys_shadow() {
    local key="$1"
    if [[ -n "${user[$key]+set}" ]]; then
      printf 'over yours: %.30s' "${user[$key]}"
    elif [[ -n "${def[$key]:-}" ]]; then
      printf 'over fzf: %s' "${def[$key]}"
    fi
  }

  local row version
  # the f1 page (a screen's module given) opens with the version
  if [[ -n "$module" ]]; then
    fzx::version version
    printf '%sfzx %s%s\n' "$d" "$version" "$r"
  fi
  if [[ "$layout" == grid ]]; then
    fzx::_keys_grid
    return
  fi
  # the components: names, their keys in brackets; the action menu reaches actions without keys
  if ((${#comps[@]})); then
    _keys_title help_module components "modes, toggles, sort orders, actions"
    local kind line=""
    for kind in mode toggle sort action; do
      line=""
      for row in "${comps[@]}"; do
        IFS=$'\t' read -r k name a desc <<< "$row"
        [[ "$k" == "$kind" ]] || continue
        # a sort order of other modes only (scoped like actions): not this screen's
        [[ "$k" == sort ]] && ((${#modes[@]})) && ! fzx::mode_desc "$desc" "$cur_mode" scoped "${modes[@]}" && continue
        line+="${line:+  }$name"
        if [[ -n "$a" && "$a" != - ]]; then
          local ks=() kl=() kk
          fzx::split_keys "$a" ks
          for kk in "${ks[@]}"; do fzx::key_label "$kk" label; kl+=("$label"); done
          line+=" ${d}[$(IFS=,; printf '%s' "${kl[*]}")]$r"
        fi
      done
      [[ -n "$line" ]] && printf '  %s%-8s%s %s\n' "$b" "${kind}s" "$r" "$line"
    done
  fi

  if ((${#rows_mod[@]})); then
    _keys_title help_module "${module:-this screen}" "this screen's keys"
    for row in "${rows_mod[@]}"; do
      IFS=$'\t' read -r k desc <<< "$row"
      _keys_row "$k" "${desc:--}" "$(_keys_shadow "$k")"
    done
  fi
  if ((${#rows_fzx[@]})); then
    _keys_title help_fzx fzx "every fzx screen"
    for row in "${rows_fzx[@]}"; do
      IFS=$'\t' read -r k desc <<< "$row"
      _keys_row "$k" "${desc:--}" "$(_keys_shadow "$k")"
    done
  fi

  _keys_title help_global global "your fzf options, then fzf's defaults"
  local what src
  while IFS= read -r k; do
    [[ -n "${mine[$k]:-}" ]] && continue
    if [[ -n "${user[$k]+set}" ]]; then
      what="${user[$k]}" src=""
      [[ -n "${def[$k]:-}" && "${def[$k]}" != "$what" ]] && src="over fzf: ${def[$k]}"
      _keys_row "$k" "$what" "$src" yours
    else
      _keys_row "$k" "${def[$k]}" "" fzf
    fi
  done < <(printf '%s\n' "${!all[@]}" | LC_ALL=C sort)

  # ctrl-h/i/m/[ are bspace/tab/enter/esc to the terminal, so they are not offered
  local group keys c
  _keys_title help_free free "not bound by fzx, your options or fzf"
  for group in ctrl alt alt-shift fn; do
    case "$group" in
      ctrl) keys=(ctrl-{a..z}) ;;
      alt) keys=(alt-{a..z} alt-{0..9}) ;;
      alt-shift) keys=(alt-{A..Z}) ;;
      fn) keys=(f{1..12}) ;;
    esac
    line=""
    for c in "${keys[@]}"; do
      [[ "$c" == ctrl-[him] || -n "${all[$c]:-}" ]] && continue
      fzx::key_label "$c" label
      line+="${line:+ }$label"
    done
    printf '  %s%-10s%s %s\n' "$b" "$group" "$r" "$(printf '%s' "${line:-none}" | fold -s -w "$((width > 30 ? width - 14 : 16))" | sed '2,$s/^/             /')"
  done
  printf '\n  %sany cursor movement returns to the normal preview%s\n' "$d" "$r"
}

# fzx::_keys_grid: the keys page as a grid (keys_page's l:grid; reads its user, def, mine and all): a row
# per modifier, the keys fzf knows with it in groups (letters, digits, function keys, movement, editing),
# each in the color of who binds it (this screen, fzx, your options, fzf's defaults) or dim when free
fzx::_keys_grid() {
  local c_mod=$'\e['"${FZX_COLORS[help_module]:-1;38;5;45}m" c_fzx=$'\e['"${FZX_COLORS[help_fzx]:-1;38;5;213}m"
  local c_user=$'\e['"${FZX_COLORS[help_global]:-1;38;5;110}m" c_fzf=$'\e[38;5;252m' c_free=$'\e[38;5;238m'
  local nav="up down left right home end" row prefix groups group key norm cell label head color line len
  local letters lower upper
  lower="$(printf '%s ' {a..z})" upper="$(printf '%s ' {A..Z})"
  letters="$(printf '%s ' a b c d e f g j k l n o p q r s t u v w x y z)"
  printf '\n%s▌ keys%s  %sby modifier:%s %sthis screen%s %sfzx%s %syours%s %sfzf%s %sfree%s\n' "$c_mod" "$r" "$d" "$r" \
    "$c_mod" "$r" "$c_fzx" "$r" "$c_user" "$r" "$c_fzf" "$r" "$c_free" "$r"
  # "prefix|group|group...": the keys fzf takes with that modifier (checked against fzf 0.74)
  for row in \
    "|$(printf 'f%s ' {1..12})|$nav pgup pgdn|tab enter space bspace delete esc insert" \
    "ctrl-|$letters|$nav|space bspace delete" \
    "alt-|$lower|$(printf '%s ' {0..9})|$nav|enter space bspace delete" \
    "alt-shift-|$upper|$nav|delete" \
    "shift-|$nav|tab delete" \
    "ctrl-alt-|$lower|$nav|bspace delete" \
    "ctrl-shift-|$nav|delete"; do
    IFS='|' read -ra groups <<< "$row"
    prefix="${groups[0]}"
    case "${FZX_KEY_STYLE:-full}:$prefix" in
      *:) head="keys" ;;
      short:*) head="$prefix"; head="${head//ctrl-/C-}"; head="${head//alt-/M-}"; head="${head//shift-/S-}" ;;
      glyph:*) head="$prefix"; head="${head//ctrl-/⌃}"; head="${head//alt-/⌥}"; head="${head//shift-/⇧}" ;;
      *) head="$prefix" ;;
    esac
    for group in "${groups[@]:1}"; do
      line="" len=0
      for key in $group; do
        # alt-shift and a letter is fzf's alt-A
        norm="$prefix$key"
        [[ "$prefix" == alt-shift- && "$key" =~ ^[A-Z]$ ]] && norm="alt-$key"
        fzx::key_name "$norm" norm
        if [[ -n "${mine[$norm]:-}" ]]; then
          [[ "${mine[$norm]}" == fzx ]] && color="$c_fzx" || color="$c_mod"
        elif [[ -n "${user[$norm]+set}" ]]; then
          color="$c_user"
        elif [[ -n "${def[$norm]:-}" ]]; then
          color="$c_fzf"
        else
          color="$c_free"
        fi
        cell="$key"
        ((${#key} > 1)) && fzx::key_label "$key" cell
        # wrap under the row's head when the preview is too narrow
        if ((len && 14 + len + 1 + ${#cell} > width)); then
          printf '  %s%s%s%s\n' "$b" "$(fzx::pad "$head" 12)" "$r" "$line"
          head="" line="" len=0
        fi
        ((len)) && line+=" " len=$((len + 1))
        line+="$color$cell$r"
        len=$((len + ${#cell}))
      done
      printf '  %s%s%s%s\n' "$b" "$(fzx::pad "$head" 12)" "$r" "$line"
      head=""
    done
  done
  printf '\n  %sthe help key again: back to the list%s\n' "$d" "$r"
}
