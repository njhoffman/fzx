#!/usr/bin/env bash
# files menu entries

files::manifest() {
  fzx::entry files "Files under this directory"
  fzx::entry files:dirs "Directories under this directory"
  fzx::entry files:grep "Search file contents as you type"
}

files::applicable() {
  case "$1" in
    files:grep) command -v rg > /dev/null ;;
    *) command -v fd > /dev/null || command -v fdfind > /dev/null ;;
  esac
}

files::summary() {
  local fd=fd n
  command -v fd > /dev/null || fd=fdfind
  case "$1" in
    files) n="$("$fd" --type f --hidden --exclude .git . | wc -l)" && printf '%s files\n' "${n// /}" ;;
    files:dirs) n="$("$fd" --type d --hidden --exclude .git . | wc -l)" && printf '%s directories\n' "${n// /}" ;;
    files:grep)
      # what a search reads: the files ripgrep would open, and their size
      local args=(--files --hidden --null --glob '!.git') ex
      for ex in "${FZX_FILES_EXCLUDES[@]}"; do args+=(--glob "!$ex"); done
      command rg "${args[@]}" 2> /dev/null | xargs -0 -r stat -c %s -- 2> /dev/null |
        awk '{ n++; b += $1 } END { split("B K M G T", u, " "); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ }
          printf "%d files, %s%s\n", n, (i > 1 && b < 10 ? sprintf("%.1f", b) : sprintf("%d", b)), u[i] }'
      ;;
  esac
}
