#!/usr/bin/env bash
# files preview: file contents (bat when available), a directory listing, or a grep hit in context.

# files::preview <path> [line]
files::preview() {
  local path="${1:-}" line="${2:-}"
  if [[ -d "$path" ]]; then
    if command -v eza > /dev/null; then
      command eza --color=always --icons --group-directories-first -a --tree --level=2 -- "$path"
    else
      command ls -la --color=always -- "$path"
    fi
  elif [[ -f "$path" ]]; then
    if command -v bat > /dev/null; then
      local range=()
      [[ "$line" =~ ^[0-9]+$ ]] && range=(--highlight-line "$line" --line-range "$((line > 10 ? line - 10 : 1)):")
      command bat --color=always --style=numbers --paging=never "${range[@]}" -- "$path"
    else
      command cat -- "$path"
    fi
  else
    printf 'no such file: %s\n' "$path"
    return 1
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && files::preview "$@"
