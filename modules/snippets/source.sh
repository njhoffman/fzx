#!/usr/bin/env bash
# snippets source (lib/snippets.sh keeps them). Modes from $FZX_MODE:
#   saved    "id<TAB>display": named snippets by name: the name, the text's first line, its line count
#   history  "id<TAB>display": what fzx pasted, newest first: when, from where, the text's first line

# snippets::_line <file> <var>: the file's first line (shown as text: control characters dropped), with a
# mark when more follow
snippets::_line() {
  local _sl_first _sl_n
  IFS= read -r _sl_first < "$1" || :
  _sl_n="$(awk 'END { print NR }' "$1")"
  _sl_first="${_sl_first//[[:cntrl:]]/}"
  ((_sl_n > 1)) && _sl_first+="  (+$((_sl_n - 1)) lines)"
  printf -v "$2" '%s' "$_sl_first"
}

# snippets::_age <ns time> <var>: how long ago, "12s" to "3y"
snippets::_age() {
  local _a_d=$((${EPOCHSECONDS:-$(date +%s)} - ${1:0:-9}))
  ((_a_d < 0)) && _a_d=0
  if ((_a_d < 60)); then printf -v "$2" '%ss' "$_a_d"
  elif ((_a_d < 3600)); then printf -v "$2" '%sm' $((_a_d / 60))
  elif ((_a_d < 86400)); then printf -v "$2" '%sh' $((_a_d / 3600))
  elif ((_a_d < 86400 * 60)); then printf -v "$2" '%sd' $((_a_d / 86400))
  elif ((_a_d < 86400 * 365)); then printf -v "$2" '%smo' $((_a_d / 2592000))
  else printf -v "$2" '%sy' $((_a_d / 31536000)); fi
}

# snippets::source
snippets::source() {
  local dir d entry name line age src n=$'\e['"${FZX_COLORS[snippets_name]:-38;5;117}m" dim=$'\e['"${FZX_COLORS[snippets_dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && n="" dim="" r=""
  fzx::require snippets
  fzx::snippets_dir dir
  case "${FZX_MODE:-saved}" in
    saved)
      [[ -d "$dir/saved" ]] || return 0
      for d in "$dir/saved"/*/; do
        d="${d%/}"
        [[ -f "$d/name" && -f "$d/value" ]] || continue
        name="$(< "$d/name")"
        snippets::_line "$d/value" line
        printf '%s\t%s\t%s%-24s%s %s\n' "${d##*/}" "$name" "$n" "${name//[[:cntrl:]]/}" "$r" "$line"
      done | LC_ALL=C sort -t$'\t' -k2,2 | cut -f1,3
      ;;
    history)
      [[ -d "$dir/history" ]] || return 0
      command ls -1 -- "$dir/history" 2> /dev/null | LC_ALL=C sort -r | while IFS= read -r entry; do
        [[ "$entry" == .* ]] && continue
        snippets::_age "${entry%%.*}" age
        src="${entry#*.}"
        snippets::_line "$dir/history/$entry" line
        printf '%s\t%s%4s %-8s%s %s\n' "$entry" "$dim" "$age" "$src" "$r" "$line"
      done
      ;;
    *)
      printf 'snippets: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" snippets
  snippets::source "$@"
}
