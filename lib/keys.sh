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

# fzx::keys_page [bound key...]: keys in use (fzx's, given as arguments, then the user's, then fzf's
# defaults; the first that binds a key wins) and the free ones
fzx::keys_page() {
  local -A fzx=() user=() def=() all=()
  local k a name b=$'\e[1m' r=$'\e[0m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m"
  for k in "$@"; do
    fzx::key_name "$k" name
    fzx[$name]=1 all[$name]=1
  done
  while IFS=$'\t' read -r k a; do
    [[ -n "$k" ]] || continue
    fzx::key_name "$k" name
    user[$name]="$a" all[$name]=1
  done < <(fzx::user_binds)
  while IFS=$'\t' read -r k a; do
    def[$k]="$a" all[$k]=1
  done <<< "$FZX_FZF_DEFAULT_BINDS"

  printf '%skeys in use%s %s(fzx, then yours, then fzf'"'"'s defaults: the first one wins)%s\n' "$b" "$r" "$d" "$r"
  local what under
  while IFS= read -r k; do
    under=""
    if [[ -n "${fzx[$k]:-}" ]]; then
      what="" under="${user[$k]+yours: ${user[$k]}}"
      [[ -n "${def[$k]:-}" ]] && under+="${under:+, }fzf: ${def[$k]}"
      printf '  %-14s %-6s' "$k" fzx
    elif [[ -n "${user[$k]+set}" ]]; then
      what="${user[$k]}" under="${def[$k]:+fzf: ${def[$k]}}"
      printf '  %-14s %-6s' "$k" yours
    else
      what="${def[$k]}"
      printf '  %-14s %-6s' "$k" fzf
    fi
    # long actions (inline scripts) are cut to keep one line per key
    ((${#what} > 60)) && what="${what:0:57}..."
    ((${#under} > 60)) && under="${under:0:57}..."
    printf ' %s%s\n' "$what" "${under:+${what:+ }$d($under)$r}"
  done < <(printf '%s\n' "${!all[@]}" | LC_ALL=C sort)

  # ctrl-h/i/m/[ are bspace/tab/enter/esc to the terminal, so they are not offered
  local group keys c line
  printf '\n%sfree keys%s\n' "$b" "$r"
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
    printf '  %-10s %s\n' "$group" "${line:-none}"
  done
}
