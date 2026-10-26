#!/usr/bin/env bash
# todos preview: todo-fzf's card. The section, the item's state, priority, category and due date, its title
# and file:line, then its details (the text after the title, continuation lines joined into paragraphs) as
# markdown through mdpreview, else bat, else glow, else plain.
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# todos::preview <id>: id is "file\x1fstart line\x1ftitle"
todos::preview() {
  local file start _title row end section title due over prio cat isdone width md rule
  IFS=$'\x1f' read -r file start _title <<< "${1:-}"
  [[ -f "$file" && "$start" =~ ^[0-9]+$ ]] || return 0
  # the done toggle on: completed items parse too
  # \x1f-separated: read merges runs of tabs, which drops empty fields (an item without a due date)
  row="$(FZX_TOGGLES="done" todos::parse "$file" | awk -F'\t' -v OFS=$'\x1f' -v n="$start" '$1 == n { $1 = $1; print }')"
  [[ -n "$row" ]] || { printf 'the item at %s:%s is gone (reload with ctrl-r)\n' "$file" "$start"; return 0; }
  IFS=$'\x1f' read -r start end section title due over prio cat isdone <<< "$row"
  width="${FZF_PREVIEW_COLUMNS:-80}"
  local R=$'\e[0m' DIM=$'\e[2m' B=$'\e[1m' CYAN=$'\e[36m' RED=$'\e[1;31m' YEL=$'\e[33m' GREEN=$'\e[32m' mark
  case "$prio" in 1) mark="${RED}● P1 high${R}" ;; 3) mark="${DIM}○ P3 low${R}" ;; *) mark="${YEL}● P2 normal${R}" ;; esac
  printf '%s%s%s\n\n' "$DIM" "$section" "$R"
  if ((isdone)); then printf '%s☑%s completed\n\n' "$GREEN" "$R"; else printf '☐ incomplete\n\n'; fi
  printf '%s   %s%s%s' "$mark" "$CYAN" "${cat:-uncategorized}" "$R"
  if [[ -n "$due" ]]; then
    if ((over)); then printf '   %sdue %s OVERDUE%s' "$RED" "$due" "$R"; else printf '   %sdue %s%s' "$YEL" "$due" "$R"; fi
  fi
  printf '\n%s%s%s   %s%s:%s%s\n' "$B" "$title" "$R" "$DIM" "${file/#$HOME/\~}" "$start" "$R"
  printf -v rule '%*s' "$width" ''
  printf '%s%s%s\n' "$DIM" "${rule// /─}" "$R"
  md="$(sed -n "${start},${end}p" "$file" | awk '
    NR == 1 {
      sub(/^- \[[ xX]\] /, ""); sub(/^\*\*[^*]+\*\* */, "")
      gsub(/\(p[123]\) */, ""); gsub(/\(due [0-9-]+\) */, ""); gsub(/\[[a-z][a-z0-9-]*\] */, ""); sub(/^: */, "")
      if ($0 ~ /[^ ]/) { printf "%s", $0; prev = $0 }
      next
    }
    {
      sub(/^  /, "")
      if ($0 ~ /^[ \t]*([-*+]|[0-9]+\.) / || $0 ~ /^[ \t]*$/ || prev ~ /^[ \t]*$/) { printf "%s%s", (NR > 1 ? "\n" : ""), $0 }
      else { sub(/^[ \t]+/, ""); printf " %s", $0 }
      prev = $0
    }
    END { print "" }')"
  if [[ "$md" != *[![:space:]]* ]]; then
    printf '%s(no details)%s\n' "$DIM" "$R"
  elif command -v mdpreview > /dev/null; then
    # mdpreview opens its argument by name: a real file, not a process substitution
    local tmp
    tmp="$(mktemp --suffix=.md)"
    printf '%s\n' "$md" > "$tmp"
    mdpreview --columns "$width" "$tmp"
    rm -f -- "$tmp"
  elif command -v bat > /dev/null; then
    printf '%s\n' "$md" | command bat --color=always --style=plain --language=markdown --wrap=auto --terminal-width="$width"
  elif command -v glow > /dev/null; then
    printf '%s\n' "$md" | glow -s dark -w "$width" -
  else
    printf '%s\n' "$md"
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && todos::preview "$@"
