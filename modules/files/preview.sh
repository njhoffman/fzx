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

# files::preview <path> [line]
files::preview() {
  local path="${1:-}" line="${2:-}" lines="${FZF_PREVIEW_LINES:-40}"
  [[ -e "$path" ]] || {
    printf 'no such file: %s\n' "$path"
    return 1
  }
  files::header "$path"
  declare -F fzx::preview_body > /dev/null || fzx::require preview
  FZX_PREVIEW_IMAGE_FORMAT="${FZX_FILES_IMAGE_FORMAT:-symbols}" FZX_PREVIEW_BAT_STYLE="${FZX_PREVIEW_BAT_STYLE:-numbers}" \
    FZF_PREVIEW_LINES="$((lines > 2 ? lines - 1 : 1))" fzx::preview_body "$path" "$line"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=../../lib/core.sh
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../lib/core.sh"
  files::preview "$@"
fi
