#!/usr/bin/env bash
# files preview: a header line (the path under ~, its size; a directory's entry count), then the contents
# rendered by type (lib/preview.sh: code, markdown, images, media tags, archives, ...) or a grep hit in context.

# files::size <bytes>: 1023B, 14.4K, 3.1M, ...
files::size() {
  awk -v b="$1" 'BEGIN { split("B K M G T", u, " "); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d%s" : "%.1f%s"), b, u[i] }'
}

# files::header <path>: "~/dir/" dim, the name bold, then the size (or entry count) dim
files::header() {
  local path="$1" shown dir name info n dim=$'\e[38;5;244m' b=$'\e[1m' rst=$'\e[0m'
  shown="${path/#$HOME/\~}"
  name="${shown##*/}"
  dir="${shown%"$name"}"
  if [[ -d "$path" ]]; then
    shopt -s nullglob dotglob
    local entries=("$path"/*)
    n="${#entries[@]}"
    info="$n entr$( ((n == 1)) && echo y || echo ies)"
  else
    info="$(files::size "$(stat -L -c %s -- "$path" 2> /dev/null || echo 0)")"
  fi
  [[ -L "$path" ]] && info+="  -> $(readlink -- "$path")"
  printf '%s%s%s%s%s  %s%s%s\n' "$dim" "$dir" "$rst$b" "$name" "$rst" "$dim" "$info" "$rst"
}

# files::flags_preview <text>: the args screen's check of what is typed: the command's added flags, or why one
# is refused
files::flags_preview() {
  local words=() err ok=$'\e[32m' bad=$'\e[31m' dim=$'\e[38;5;244m' rst=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && ok="" bad="" dim="" rst=""
  declare -F fzx::session_args > /dev/null || fzx::require session
  # shellcheck source=./source.sh
  declare -F files::flags_parse > /dev/null || source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :
  fzx::session_args
  files::args "${FZX_ARGS[@]}" 2> /dev/null || return 0
  if files::flags_parse "$FILES_TOOL" "$1" words err; then
    if ((${#words[@]})); then
      printf '%sadds:%s %s %s\n' "$ok" "$rst" "$FILES_TOOL" "${words[*]}"
    else
      printf '%sno flags: enter clears them%s\n' "$dim" "$rst"
    fi
  else
    printf '%srefused:%s %s\n' "$bad" "$rst" "$err"
  fi
}

# files::replace_preview <path> <line> <replacement>: the match's line as it is (red, -) and as the
# replacement leaves it (green, +), between FZX_FILES_REPLACE_CONTEXT (3) lines on each side
files::replace_preview() {
  local path="$1" line="$2" repl="$3" c="${FZX_FILES_REPLACE_CONTEXT:-3}" new
  local red=$'\e[31m' green=$'\e[32m' dim=$'\e[38;5;244m' rst=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && red="" green="" dim="" rst=""
  [[ "$line" =~ ^[0-9]+$ ]] || return 0
  declare -F fzx::session_args > /dev/null || fzx::require session
  # shellcheck source=./source.sh
  declare -F files::args > /dev/null || source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :
  fzx::session_args
  files::args "${FZX_ARGS[@]}" 2> /dev/null || return 0
  new="$(sed -n "${line}p" -- "$path" | command rg --no-config --passthru --color=never --smart-case --replace "$repl" -- "$FILES_TERM")"
  [[ -z "$repl" ]] && printf '%s(the replacement is empty: the match is deleted)%s\n' "$dim" "$rst"
  awk -v n="$line" -v c="$c" -v new="$new" -v red="$red" -v green="$green" -v dim="$dim" -v rst="$rst" '
    NR < n - c { next }
    NR > n + c { exit }
    NR == n { printf "%s%5d - %s%s\n%s%5s + %s%s\n", red, NR, $0, rst, green, "", new, rst; next }
    { printf "%s%5d%s   %s\n", dim, NR, rst, $0 }' "$path"
}

# files::preview <path> [line]
files::preview() {
  local path="${1:-}" line="${2:-}" lines="${FZF_PREVIEW_LINES:-40}"
  if [[ "${FZX_MODE:-}" == args ]]; then
    files::flags_preview "$1"
    return 0
  fi
  # no row (an empty list): nothing to show
  [[ -n "$path" ]] || return 0
  [[ -e "$path" ]] || {
    printf 'no such file: %s\n' "$path"
    return 1
  }
  files::header "$path"
  if [[ "${FZX_MODE:-}" == replace ]]; then
    files::replace_preview "$path" "$line" "${3-}"
    return 0
  fi
  declare -F fzx::preview_body > /dev/null || fzx::require preview
  FZX_PREVIEW_IMAGE_FORMAT="${FZX_FILES_IMAGE_FORMAT:-symbols}" FZX_PREVIEW_BAT_STYLE="${FZX_PREVIEW_BAT_STYLE:-numbers}" \
    FZF_PREVIEW_LINES="$((lines > 2 ? lines - 1 : 1))" fzx::preview_body "$path" "$line"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=../../lib/core.sh
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/core.sh"
  files::preview "$@"
fi
