#!/usr/bin/env bash
# man source. Lines are "id<TAB>display": the id is "name(section)" for man pages, the page name for tldr.
# Mode from $FZX_MODE: commands (FZX_MAN_SECTIONS), all, tldr, zsh (the zsh manual's entries; the id is
# "page:name", zshoptions:AUTO_CD).

# man::pages: `man -k .` as "name<TAB>section<TAB>description", one line per name ("a, b (1) - x" lists
# both), first occurrence of each name and section
man::pages() {
  command man -k . 2> /dev/null |
    awk '{
      i = index($0, " - "); if (!i) next
      head = substr($0, 1, i - 1); desc = substr($0, i + 3)
      if (!match(head, /\([^)]*\)[ \t]*$/)) next
      sec = substr(head, RSTART + 1, RLENGTH - 1); sub(/\)[ \t]*$/, "", sec)
      names = substr(head, 1, RSTART - 1); sub(/[ \t]+$/, "", names)
      n = split(names, list, /, */)
      for (j = 1; j <= n; j++) if (list[j] != "" && !seen[list[j] SUBSEP sec]++) print list[j] "\t" sec "\t" desc
    }'
}

# man::tldr_dir <var>: tealdeer's pages directory (FZX_MAN_TLDR_PAGES, else `tldr --show-paths`)
man::tldr_dir() {
  local _d="${FZX_MAN_TLDR_PAGES:-}"
  [[ -n "$_d" ]] || _d="$(command tldr --show-paths 2> /dev/null | awk -F': *' '/^Pages dir/ { print $2 }')"
  _d="${_d%/}"
  printf -v "$1" '%s' "$_d"
}

# man::tldr: "name<TAB>platform<TAB>description" from the pages' first "> " line, common first; without
# a pages directory, tealdeer's list alone
man::tldr() {
  local dir p files=()
  man::tldr_dir dir
  if [[ -z "$dir" || ! -d "$dir/pages.en" ]]; then
    command tldr --list 2> /dev/null | awk '{ print $0 "\tcommon\t" }'
    return
  fi
  for p in common "${FZX_MAN_TLDR_PLATFORMS[@]}"; do
    [[ -d "$dir/pages.en/$p" ]] && files+=("$dir/pages.en/$p"/*.md)
  done
  ((${#files[@]})) || return 0
  awk '/^> / && !done[FILENAME]++ {
      n = FILENAME; sub(/\.md$/, "", n); p = n; sub(/.*\//, "", n); sub(/\/[^\/]*$/, "", p); sub(/.*\//, "", p)
      if (seen[n]++) next
      d = $0; sub(/^> /, "", d); print n "\t" p "\t" d
    }' "${files[@]}"
}

# The zsh manual's pages the zsh mode lists, as page:kind (man::zsh_index names the sections it reads)
MAN_ZSH_PAGES=(zshoptions:option zshbuiltins:builtin zshparam:parameter zshzle:widget)

# man::zsh_index: "name<TAB>kind<TAB>summary<TAB>page" for every entry of the zsh manual's lists: options,
# builtins, the parameters the shell sets and uses, the standard widgets and the zle builtins. An entry is a
# line at man's 7-column indent followed by its text at 14; a tag of 6 characters or fewer has its text on
# the same line from column 15, and a long synopsis goes on indented 8 to 13. The summary is the text's first
# sentence. A builtin whose entry only points elsewhere ("See the section ...") gives way to that entry
# (bindkey, zle, vared in zshzle).
man::zsh_index() {
  local page kind
  for page in "${MAN_ZSH_PAGES[@]}"; do
    kind="${page#*:}" page="${page%%:*}"
    MANWIDTH=1000 command man "$page" 2> /dev/null | command col -bx | awk -v page="$page" -v kind="$kind" '
      function want(s) {
        if (page == "zshoptions") return s == "DESCRIPTION OF OPTIONS"
        if (page == "zshbuiltins") return s == "SHELL BUILTIN COMMANDS"
        if (page == "zshparam") return s ~ /^PARAMETERS (SET|USED) BY THE SHELL$/
        if (page == "zshzle") return s == "STANDARD WIDGETS" || s == "ZLE BUILTINS"
      }
      function flush() {
        if (tag == "") return
        name = tag; sub(/[ \t].*/, "", name)
        ok = 1
        if (kind == "option" && name !~ /^[A-Z][A-Z0-9_]+$/) ok = 0
        if (kind == "parameter" && name !~ /^([A-Za-z_][A-Za-z0-9_]*|[*@#?$!_0-]|ARGC)$/) ok = 0
        if (kind == "widget" && name !~ /^[a-z][a-z0-9.-]*$/) ok = 0
        if (kind == "builtin" && name !~ /^([a-z][a-z0-9_.-]*|[.:\[-]+)$/) ok = 0
        k = kind; if (page == "zshzle" && sect == "ZLE BUILTINS") k = "zle builtin"
        s = body; gsub(/  +/, " ", s); sub(/^ /, "", s); sub(/^(<[A-Z]> ?)+/, "", s)
        if (match(s, /[.:]( |$)/)) s = substr(s, 1, RSTART)
        if (ok && !seen[name]++) printf "%s\t%s\t%s\t%s\n", name, k, s, page
        tag = ""; body = ""
      }
      /^[A-Z][A-Z0-9 ()-]+$/ { flush(); pending = 0; sect = $0; next }
      !want(sect) { next }
      # a short tag has its text on the same line, at column 15
      /^       [^ ]/ && substr($0, 15, 1) != " " && (substr($0, 8, 7) ~ /^[^ ]+  +$/ || (substr($0, 8, 7) ~ /^[^ ]+ $/ && substr($0, 15, 1) ~ /[A-Z]/)) {
        flush(); tag = substr($0, 8, 7); sub(/ +$/, "", tag); body = substr($0, 15); pending = 0; next
      }
      /^       [^ ]/ { flush(); cand = $0; sub(/^ +/, "", cand); pending = 1; next }
      # a synopsis that goes on, indented 8 to 13 (set and print in zshbuiltins)
      { ind = match($0, /[^ ]/) - 1 }
      ind > 7 && ind < 14 && pending { next }
      /^              [^ ]/ {
        if (pending) { tag = cand; body = ""; pending = 0 }
        if (tag != "" && length(body) < 400) body = body " " $0
        next
      }
      /^$/ { next }
      { pending = 0 }
      END { flush() }'
  done | awk -F'\t' '{ row[NR] = $0; name[NR] = $1; see[NR] = $3 ~ /^See the section/; if (!see[NR]) real[$1] = 1 }
    END { for (i = 1; i <= NR; i++) if (!see[i] || !real[name[i]]) print row[i] }'
}

# man::zsh_cached: man::zsh_index, kept under $FZX_CACHE_DIR/man keyed by the pages' files and times (the
# index renders four long pages: seconds); an index for other pages (another zsh) is removed
man::zsh_cached() {
  local key f p files=()
  for p in "${MAN_ZSH_PAGES[@]}"; do
    f="$(command man -w "${p%%:*}" 2> /dev/null)" && [[ -n "$f" ]] && files+=("$f")
  done
  ((${#files[@]})) || return 0
  key="$(stat -c '%n %Y' -- "${files[@]}" 2> /dev/null | cksum | cut -d' ' -f1)"
  f="${FZX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fzx}/man/zsh-$key.tsv"
  if [[ ! -s "$f" ]]; then
    if ! mkdir -p -- "${f%/*}" || ! man::zsh_index > "$f.$$" || ! mv -f -- "$f.$$" "$f"; then
      rm -f -- "$f.$$"
      man::zsh_index
      return
    fi
    find "${f%/*}" -maxdepth 1 -name 'zsh-*.tsv' ! -name "${f##*/}" -delete 2> /dev/null
  fi
  command cat -- "$f"
}

# man::format <tldr|man|zsh>: "name<TAB>section<TAB>description" -> "id<TAB>display", shorter names first, then
# by name: fzf scores "ls" in "ls" and "lsw" alike, and its length tiebreak counts the description too, so
# the list's order (--tiebreak=begin,index) puts the exact name first
man::format() {
  local kind="$1" n=$'\e['"${FZX_COLORS[man_name]:-1;38;5;117}m" s=$'\e['"${FZX_COLORS[man_section]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && n="" s="" r=""
  awk -F'\t' '{ print length($1) "\t" $0 }' | LC_ALL=C sort -t$'\t' -k1,1n -k2,2 -k3,3 | cut -f2- |
    awk -F'\t' -v kind="$kind" -v n="$n" -v s="$s" -v r="$r" '{
      id = kind == "tldr" ? $1 : kind == "zsh" ? $4 ":" $1 : $1 "(" $2 ")"
      printf "%s\t%s%-28s%s %s%-*s%s %s\n", id, n, $1, r, s, (kind == "zsh" ? 11 : 8), $2, r, $3 }'
}

# man::source
man::source() {
  case "${FZX_MODE:-commands}" in
    commands)
      man::pages | awk -F'\t' -v secs="${FZX_MAN_SECTIONS[*]}" 'BEGIN { n = split(secs, want, " ") }
        { for (i = 1; i <= n; i++) if (index($2, want[i]) == 1) { print; next } }' | man::format man
      ;;
    all) man::pages | man::format man ;;
    tldr) man::tldr | man::format tldr ;;
    zsh) man::zsh_cached | man::format zsh ;;
    *)
      printf 'man: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" man
  man::source "$@"
}
