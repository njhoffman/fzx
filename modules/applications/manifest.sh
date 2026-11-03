#!/usr/bin/env bash
# applications menu entry, where a desktop entry directory exists

applications::manifest() {
  fzx::entry applications "Applications (desktop entries)"
}

applications::applicable() {
  [[ -d /usr/share/applications || -d "${XDG_DATA_HOME:-$HOME/.local/share}/applications" ]]
}

# applications::summary <target>: how many desktop files there are
applications::summary() {
  local d n=0 f
  for d in "${XDG_DATA_HOME:-$HOME/.local/share}/applications" /usr/local/share/applications /usr/share/applications; do
    for f in "$d"/*.desktop; do [[ -e "$f" ]] && ((n++)); done
  done
  printf '%d entries\n' "$n"
}
