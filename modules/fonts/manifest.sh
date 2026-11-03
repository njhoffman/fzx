#!/usr/bin/env bash
# fonts menu entry, where fontconfig is installed

fonts::manifest() {
  fzx::entry fonts "Fonts (fontconfig families)"
}

fonts::applicable() {
  command -v fc-list > /dev/null
}

# fonts::summary <target>: the family count
fonts::summary() {
  local n
  n="$(command fc-list --format '%{family[0]}\n' 2> /dev/null | sort -u | wc -l)"
  printf '%d families\n' "$((n))"
}
