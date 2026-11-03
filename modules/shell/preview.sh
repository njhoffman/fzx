#!/usr/bin/env bash
# shell preview, by kind: a command's locations on PATH, then its tldr page (else its man page); a zsh
# builtin's entry in zshbuiltins(1); an alias's expansion and what its first word is; a function's
# definition (else its source file); a parameter's type and whole value (arrays an element a line,
# associations key -> value, *PATH scalars a directory a line)

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
# shellcheck source=../../lib/render.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/render.sh"

# shell::zsh_code: stdin highlighted as zsh (bat), within the preview's width
shell::zsh_code() { FZF_PREVIEW_COLUMNS="${FZF_PREVIEW_COLUMNS:-80}" fzx::render_text --language zsh --style plain; }

# shell::help <name>: the tldr page, else the man page rendered at the preview's width; fails with neither
shell::help() {
  local cols="${FZF_PREVIEW_COLUMNS:-80}" page
  command -v tldr > /dev/null && command tldr --color always -- "$1" 2> /dev/null && return 0
  page="$(MANWIDTH="$cols" command man -- "$1" 2> /dev/null | command col -bx)" || return 1
  [[ -n "$page" ]] || return 1
  fzx::render_text --language man --style plain <<< "$page"
}

# shell::builtin_doc <name>: the builtin's entry in zshbuiltins(1): from its heading to the next one
shell::builtin_doc() {
  MANWIDTH="${FZF_PREVIEW_COLUMNS:-80}" command man zshbuiltins 2> /dev/null | command col -bx |
    awk -v n="$1" '
      /^       [^ ]/ { if (on && $1 != n) exit; if ($1 == n) on = 1 }
      on { print }' | sed 's/^       //'
}

# shell::dump_line <kind> <name>: the dump's line for it
shell::dump_line() {
  local dump
  shell::dump dump 2> /dev/null || return 1
  awk -F'\t' -v k="$1" -v n="$2" '$1 == k && $(k == "alias" ? 3 : 2) == n { print; exit }' "$dump"
}

# shell::unquote <zsh-quoted value>: the value(s) zsh reads back, one per line (an association's as
# "key -> value"); the quoted text itself without zsh
shell::unquote() {
  if ! command -v zsh > /dev/null; then
    printf '%s\n' "$1"
    return 0
  fi
  # the dump is the user's own shell's, written owner-only: zsh reads its quoting back
  command zsh -f -c '
    if [[ "$2" == association ]]; then typeset -A v; eval "v=$1"; for k in ${(ko)v}; do print -r -- "$k -> ${v[$k]}"; done
    elif [[ "$2" == array ]]; then eval "v=$1"; print -rl -- "${v[@]}"
    else eval "v=$1"; print -r -- "$v"; fi' _ "$1" "$2"
}

shell::preview_command() {
  local name="$1" kind="$2" b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' p t line
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  case "$kind" in
    builtin)
      printf '%s%s%s  %szsh builtin%s\n\n' "$b" "$name" "$r" "$d" "$r"
      shell::builtin_doc "$name"
      return 0
      ;;
    reserved)
      printf '%s%s%s  %szsh reserved word (zshmisc(1))%s\n' "$b" "$name" "$r" "$d" "$r"
      return 0
      ;;
  esac
  printf '%s%s%s\n' "$b" "$name" "$r"
  # every one on PATH (the first one runs), with where a link leads
  while IFS= read -r p; do
    t=""
    [[ -L "$p" ]] && t="  -> $(readlink -f -- "$p")"
    printf '%s%s%s\n' "$p" "$d$t" "$r"
  done < <(type -ap -- "$name" 2> /dev/null | awk '!seen[$0]++')
  # whatis matches any case: the name's own page, section 1 first
  line="$(command man -f -- "$name" 2> /dev/null | awk -v n="$name" 'index($0, n " (") == 1' | sort -t'(' -k2,2 | head -1)"
  [[ -n "$line" ]] && printf '%s%s%s\n' "$d" "$line" "$r"
  printf '\n'
  shell::help "$name" || printf '%sno tldr or man page%s\n' "$d" "$r"
}

shell::preview_alias() {
  local name="$1" kind line value first _k _n b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' p
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  line="$(shell::dump_line alias "$name")" || return 0
  shell::split "$line" _k kind _n value
  value="$(shell::unquote "$value")"
  # as it would be defined: single-quoted
  printf "alias %s%s%s='%s'\n" "$([[ "$kind" == global ]] && echo '-g ')" "$([[ "$kind" == suffix ]] && echo '-s ')" "$name" \
    "${value//\'/\'\\\'\'}" | shell::zsh_code
  # what the first word is: another alias, a function, a builtin or a command
  first="${value%%[[:space:]]*}"
  [[ -n "$first" && "$first" != "$name" ]] || return 0
  printf '\n%sruns%s %s%s%s' "$d" "$r" "$b" "$first" "$r"
  if line="$(shell::dump_line alias "$first")" && [[ -n "$line" ]]; then
    printf '  %san alias%s\n' "$d" "$r"
  elif line="$(shell::dump_line function "$first")" && [[ -n "$line" ]]; then
    printf '  %sa function%s\n' "$d" "$r"
  elif line="$(shell::dump_line builtin "$first")" && [[ -n "$line" ]]; then
    printf '  %sa zsh builtin%s\n' "$d" "$r"
  elif p="$(type -P -- "$first")"; then
    printf '  %s%s%s\n\n' "$d" "$p" "$r"
    shell::help "$first" || :
  else
    printf '  %snot found%s\n' "$d" "$r"
  fi
}

shell::preview_function() {
  local name="$1" line file auto dir body _k _n d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && d="" r=""
  line="$(shell::dump_line function "$name")" || return 0
  shell::split "$line" _k _n file auto
  [[ -n "$file" ]] && printf '%s%s%s%s\n\n' "$d" "${file/#$HOME/\~}" "$([[ "$auto" == 1 ]] && echo '  (autoload, not loaded yet)')" "$r"
  shell::dump_dir dir
  # its definition as `functions` printed it (non-completion functions), else its file
  body="$(awk -v n="$name" '$0 == n " () {" { on = 1 } on { print } on && $0 == "}" { exit }' "$dir/functions.zsh" 2> /dev/null)"
  if [[ -n "$body" ]]; then
    printf '%s\n' "$body" | shell::zsh_code
  elif [[ -f "$file" ]]; then
    shell::zsh_code < "$file"
  else
    printf '%sno definition saved (completion functions are listed by name only)%s\n' "$d" "$r"
  fi
}

# shell::lines <name>: stdin, a *PATH value a directory a line
shell::lines() {
  if [[ "$1" == *PATH ]]; then tr ':' '\n'; else cat; fi
}

shell::preview_param() {
  local name="$1" b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' type value hidden base _n
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  shell::split "$(shell::param_rows | awk -F'\t' -v n="$name" '$1 == n { print; exit }')" _n type value hidden
  [[ -n "$type" ]] || return 0
  printf '%s%s%s  %s%s%s\n\n' "$b" "$name" "$r" "$d" "${type//-/ }" "$r"
  if [[ "$hidden" == 1 ]]; then
    printf '%smasked: the name matches FZX_SHELL_SECRETS; the reveal toggle shows exported values%s\n' "$d" "$r"
    return 0
  fi
  base="${type%%-*}"
  if [[ "$value" == $'\001'* ]]; then
    # from the environment: raw, with tabs, newlines and backslashes escaped
    value="${value#$'\001'}"
    printf '%b' "$value" | shell::lines "$name"
    printf '\n'
  elif [[ "$base" == array || "$base" == association ]]; then
    shell::unquote "$value" "$base" | cat -n
  else
    shell::unquote "$value" | shell::lines "$name"
  fi
}

# shell::preview <name> <kind>
# shell::preview_completion <command>: its bindings from zsh-complete's cached list (provider, function,
# file, upstream and revision), then the main function's file
shell::preview_completion() {
  local file b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' main="" k c src fn path up rev
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  shell::completions_file file
  printf '%s%s%s\n\n' "$b" "$1" "$r"
  while IFS=$'\t' read -r k c src fn path up rev; do
    [[ "$k" == active && "$c" == "$1" ]] || continue
    [[ -z "$main" || "$fn" == "_$1" ]] && main="$path"
    printf '%sprovider%s  %s\n%sfunction%s  %s\n%sfile%s      %s\n' "$d" "$r" "$src" "$d" "$r" "$fn" "$d" "$r" "${path/#"$HOME"/\~}"
    [[ "$up" != unknown && -n "$up" ]] && printf '%supstream%s  %s\n' "$d" "$r" "$up"
    [[ "$rev" != unknown && -n "$rev" ]] && printf '%srevision%s  %s\n' "$d" "$r" "$rev"
    printf '\n'
  done < <(grep -F $'\t'"$1"$'\t' "$file" 2> /dev/null)
  [[ -n "$main" ]] || { printf 'no completion for %s (any more): alt-R asks zsh-complete again\n' "$1"; return 0; }
  [[ -r "$main" ]] && head -n "${FZF_PREVIEW_LINES:-60}" -- "$main" | shell::zsh_code
  return 0
}

shell::preview() {
  case "${2:-}" in
    completion) shell::preview_completion "$1" ;;
    command | builtin | reserved) shell::preview_command "$1" "$2" ;;
    alias | galias | salias) shell::preview_alias "$1" ;;
    function) shell::preview_function "$1" ;;
    param) shell::preview_param "$1" ;;
    *) return 0 ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" shell
  shell::preview "$@"
}
