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
# Sections: this screen's keys, fzx's keys, the global keys (the user's FZF_DEFAULT_OPTS(_FILE) binds, then
# fzf's defaults; the first that binds a key wins), the components, then the free keys. A key fzx takes
# over from a global binding says what it shadows.
fzx::keys_page() {
  local -A user=() def=() all=() mine=()
  local module="" entry k a name scope desc width rows_mod=() rows_fzx=() comps=()
  local r=$'\e[0m' b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m"
  local cap=$'\e['"${FZX_COLORS[help_key]:-1;38;5;223;48;5;236}m"
  width="${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}"
  for entry in "$@"; do
    case "$entry" in
      m:*) module="${entry#m:}" ;;
      c:*) comps+=("${entry#c:}") ;;
      k:*)
        IFS=$'\t' read -r scope k desc <<< "${entry#k:}"
        fzx::key_name "$k" name
        [[ -n "${mine[$name]:-}" ]] && continue
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
    printf '  %s %-12s %s %s%s%s\n' "$cap" "$key" "$r" "$tag" "$text" "$note"
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

  local row
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

  # the components: names, their keys in brackets; the action menu reaches actions without keys
  if ((${#comps[@]})); then
    _keys_title help_module components "modes, toggles, sort orders, actions"
    local kind line=""
    for kind in mode toggle sort action; do
      line=""
      for row in "${comps[@]}"; do
        IFS=$'\t' read -r k name a desc <<< "$row"
        [[ "$k" == "$kind" ]] || continue
        line+="${line:+  }$name"
        [[ -n "$a" && "$a" != - ]] && line+=" ${d}[$a]$r"
      done
      [[ -n "$line" ]] && printf '  %s%-8s%s %s\n' "$b" "${kind}s" "$r" "$line"
    done
  fi

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
      line+="${line:+ }$c"
    done
    printf '  %s%-10s%s %s\n' "$b" "$group" "$r" "$(printf '%s' "${line:-none}" | fold -s -w "$((width > 30 ? width - 14 : 16))" | sed '2,$s/^/             /')"
  done
  printf '\n  %sany cursor movement returns to the normal preview%s\n' "$d" "$r"
}
