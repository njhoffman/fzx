#!/usr/bin/env bash
# man source. Lines are "id<TAB>display": the id is "name(section)" for man pages, the page name for tldr.
# Mode from $FZX_MODE: commands (FZX_MAN_SECTIONS), all, tldr.

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

# man::format <tldr|man>: "name<TAB>section<TAB>description" -> "id<TAB>display", shorter names first, then
# by name: fzf scores "ls" in "ls" and "lsw" alike, and its length tiebreak counts the description too, so
# the list's order (--tiebreak=begin,index) puts the exact name first
man::format() {
  local kind="$1" n=$'\e['"${FZX_COLORS[man_name]:-1;38;5;117}m" s=$'\e['"${FZX_COLORS[man_section]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && n="" s="" r=""
  awk -F'\t' '{ print length($1) "\t" $0 }' | LC_ALL=C sort -t$'\t' -k1,1n -k2,2 -k3,3 | cut -f2- |
    awk -F'\t' -v kind="$kind" -v n="$n" -v s="$s" -v r="$r" '{
      id = kind == "tldr" ? $1 : $1 "(" $2 ")"
      printf "%s\t%s%-28s%s %s%-8s%s %s\n", id, n, $1, r, s, $2, r, $3 }'
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
