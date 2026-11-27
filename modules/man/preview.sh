#!/usr/bin/env bash
# man preview: the page rendered at the preview's width (lib/render.sh: bat when installed), or the tldr page

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
# shellcheck source=../../lib/render.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/render.sh"

# man::split <id> <name var> <section var>: "name(section)" apart; a bare name has no section
man::split() {
  local _id="$1"
  if [[ "$_id" =~ ^(.+)\(([^\(\)]+)\)$ ]]; then
    printf -v "$2" '%s' "${BASH_REMATCH[1]}"
    printf -v "$3" '%s' "${BASH_REMATCH[2]}"
  else
    printf -v "$2" '%s' "$_id"
    printf -v "$3" ''
  fi
}

# man::page <id>: the page as plain text, MANWIDTH wide
man::page() {
  local name sec
  man::split "$1" name sec
  command man ${sec:+"$sec"} -- "$name" 2> /dev/null | command col -bx
}

# man::zsh_entry <page:name>: the entry's text out of the zsh manual page, MANWIDTH wide: from the line at
# man's 7-column indent whose first word is the name (in the sections the index reads, as man::zsh_index
# finds it) to the next such line once the entry's own text has started
man::zsh_entry() {
  local page="${1%%:*}" name="${1#*:}"
  command man "$page" 2> /dev/null | command col -bx | awk -v name="$name" '
    function inline(l) { return length(l) > 14 && substr(l, 15, 1) != " " && substr(l, 8, 7) ~ /^[^ ]+ +$/ }
    /^[A-Z][A-Z0-9 ()-]+$/ { if (on) exit; sect = $0; cand = ""; next }
    sect !~ /^(DESCRIPTION OF OPTIONS|SHELL BUILTIN COMMANDS|PARAMETERS (SET|USED) BY THE SHELL|STANDARD WIDGETS|ZLE BUILTINS)$/ { next }
    on {
      if ($0 ~ /^       [^ ]/ && body) exit
      print
      if ($0 ~ /^              [^ ]/) body = 1
      next
    }
    # a line naming the entry is taken once its text follows (a wrapped sentence that starts with the
    # name is not); a short tag with its text on the same line at once
    /^       [^ ]/ {
      if ($1 == name && inline($0)) { print; on = 1; body = 1; next }
      if ($1 == name && cand == "") { cand = $0; next }
      if (cand != "") cand = cand "\n" $0
      next
    }
    { ind = match($0, /[^ ]/) - 1 }
    ind > 7 && ind < 14 && cand != "" { cand = cand "\n" $0; next }
    /^              [^ ]/ && cand != "" { print cand; print; on = 1; body = 1; next }
    { cand = "" }'
}

# man::preview <id>
man::preview() {
  local id="${1:-}" cols="${FZF_PREVIEW_COLUMNS:-80}"
  [[ -n "$id" ]] || return 0
  if [[ "${FZX_MODE:-commands}" == tldr ]]; then
    command tldr --color always -- "$id" 2> /dev/null || printf 'no tldr page: %s\n' "$id"
    return 0
  fi
  if [[ "${FZX_MODE:-commands}" == zsh ]]; then
    # the entry's 7 columns of indent go: the text keeps the preview's width
    MANWIDTH="$((cols + 7))" man::zsh_entry "$id" | sed -e 's/^       //' | fzx::render_text --language man --style plain
    return 0
  fi
  MANWIDTH="$cols" man::page "$id" | fzx::render_text --language man --style plain
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && man::preview "$@"
