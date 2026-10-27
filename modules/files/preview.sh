#!/usr/bin/env bash
# files preview: a header line (the path under ~, its size; a directory's entry count), then the file's
# contents (bat when available), an image (chafa), a directory tree, or a grep hit in context.

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
  local path="${1:-}" line="${2:-}" cols="${FZF_PREVIEW_COLUMNS:-80}" lines="${FZF_PREVIEW_LINES:-40}"
  [[ -e "$path" ]] || {
    printf 'no such file: %s\n' "$path"
    return 1
  }
  files::header "$path"
  if [[ -d "$path" ]]; then
    if command -v eza > /dev/null; then
      command eza --color=always --icons --group-directories-first -a --tree --level=2 -- "$path" | tail -n +2
    else
      command ls -la --color=always -- "$path"
    fi
    return 0
  fi
  case "${path,,}" in
    *.png | *.jpg | *.jpeg | *.gif | *.webp | *.bmp | *.tif | *.tiff | *.ico | *.avif)
      if command -v chafa > /dev/null; then
        command chafa --format="${FZX_FILES_IMAGE_FORMAT:-symbols}" --size="${cols}x$((lines > 2 ? lines - 1 : 1))" \
          --animate=off -- "$path" 2> /dev/null && return 0
      fi
      command -v file > /dev/null && command file -b -- "$path"
      return 0
      ;;
  esac
  if command -v bat > /dev/null; then
    local range=()
    [[ "$line" =~ ^[0-9]+$ ]] && range=(--highlight-line "$line" --line-range "$((line > 10 ? line - 10 : 1)):")
    command bat --color=always --style=numbers --paging=never "${range[@]}" -- "$path"
  else
    command cat -- "$path"
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && files::preview "$@"
