#!/usr/bin/env bash
# todos source: the items of TODO.md files in the format Claude Code keeps (`- [ ] **Title.** (pN)
# [category] text`, `## N. Section` headings, continuation lines indented), the format todo-status reads.
# Rows are "id<TAB>display<TAB>line<TAB>title": id is "file\x1fstart line\x1ftitle" (the done action checks
# the title is still on that line), line the printable "TODO.md:LINE ☐  (Pn) [category] Title" and title
# the plain title.
# Modes: here (the TODO.md at the top of the current repository, else in this directory), all (the TODO.md
# at the top of every repository under ghq and FZX_TODOS_ROOTS, plus FZX_TODOS_FILES). Toggle done: completed
# items too. Sort: urgency (open first, overdue, priority, due date, file order) or file (file order).

# todos::here: the TODO.md for the current directory
todos::here() {
  local top
  top="$(git rev-parse --show-toplevel 2> /dev/null)" || top="$PWD"
  [[ -f "$top/TODO.md" ]] && printf '%s\n' "$top/TODO.md"
}

# todos::files: every TODO.md the mode covers, resolved and deduplicated
todos::files() {
  local root dir
  case "${FZX_MODE:-here}" in
    here) todos::here ;;
    all)
      {
        command -v ghq > /dev/null && command ghq list -p 2> /dev/null | while IFS= read -r dir; do
          [[ -f "$dir/TODO.md" ]] && printf '%s\n' "$dir/TODO.md"
        done
        for root in "${FZX_TODOS_ROOTS[@]}"; do
          [[ -d "$root" ]] && find -L "$root" -mindepth 2 -maxdepth 4 -name TODO.md -path '*/TODO.md' 2> /dev/null
        done
        printf '%s\n' "${FZX_TODOS_FILES[@]}"
      } | xargs -r -d '\n' realpath -e -- 2> /dev/null | awk '!seen[$0]++'
      ;;
    *) return 1 ;;
  esac
}

# todos::parse <file>: "start<TAB>end<TAB>section<TAB>title<TAB>due<TAB>overdue<TAB>priority<TAB>category<TAB>
# done" per item (todo-status -l's fields minus the checkbox); completed items only with the done toggle
todos::parse() {
  awk -v today="${TODO_TODAY:-$(date +%F)}" -v all="$([[ " ${FZX_TOGGLES:-} " == *" done "* ]] && echo 1)" '
    BEGIN { ncat = split("bug feature refactor docs test chore perf", cats, " "); for (i = 1; i <= ncat; i++) iscat[cats[i]] = 1 }
    function category(t,  w) {
      while (match(t, /\[[a-z][a-z0-9-]*\]/)) {
        w = substr(t, RSTART + 1, RLENGTH - 2)
        if (w in iscat) return w
        t = substr(t, RSTART + RLENGTH)
      }
      return ""
    }
    function title(t) {
      if (match(t, /^\*\*[^*]+\*\*/)) t = substr(t, 3, RLENGTH - 4)
      sub(/ *\(p[123]\) */, " ", t); sub(/^ +/, "", t); sub(/ +$/, "", t); sub(/\.$/, "", t)
      return t
    }
    function flush(  due, prio, cat) {
      if (item == "") return
      prio = match(body, /\(p[123]\)/) ? substr(body, RSTART + 2, 1) + 0 : 2
      cat = category(body)
      due = match(body, /\(due [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)/) ? substr(body, RSTART + 5, 10) : ""
      gsub(/\t/, " ", item)
      printf "%d\t%d\t%s\t%s\t%s\t%d\t%d\t%s\t%d\n", start, end, head, item, due, (due != "" && due < today && !isdone), prio, cat, isdone
      item = ""
    }
    !nsec && /^Categories:/ { for (i = 2; i <= NF; i++) iscat[$i] = 1; next }
    /^ ? ? ?(```+|~~~+)/ {
      if (item != "" && $0 ~ /^[ \t]/) { body = body " " $0; end = NR } else flush()
      marker = $0; sub(/^ */, "", marker); rest = marker; sub(/^`+|^~+/, "", rest)
      size = length(marker) - length(rest); char = substr(marker, 1, 1)
      if (fence == "") { fence = char; fence_size = size }
      else if (char == fence && size >= fence_size && rest ~ /^[ \t]*$/) fence = ""
      next
    }
    fence != "" { if (item != "") { body = body " " $0; if (NF) end = NR }; next }
    /^## / { flush(); nsec++; head = substr($0, 4); gsub(/\t/, " ", head); next }
    /^- \[ \] / { flush(); isdone = 0; item = title(substr($0, 7)); body = $0; start = end = NR; next }
    /^- \[[xX]\] / { flush(); if (all) { isdone = 1; item = title(substr($0, 7)); body = $0; start = end = NR }; next }
    /^[ \t]/ { if (item != "") { body = body " " $0; if (NF) end = NR }; next }
    /^[^ \t]/ { flush() }
    END { flush() }' "$1"
}

# todos::label <file>: how a file is named in rows: TODO.md in here mode, else its repository's name
todos::label() {
  local top
  if [[ "${FZX_MODE:-here}" == here ]]; then
    printf 'TODO.md'
    return
  fi
  top="$(git -C "${1%/*}" rev-parse --show-toplevel 2> /dev/null)" || top="${1%/*}"
  printf '%s/%s' "${top##*/}" "${1#"$top"/}"
}

todos::source() {
  local file label
  todos::files | while IFS= read -r file; do
    label="$(todos::label "$file")"
    todos::parse "$file" | awk -v file="$file" -v label="$label" '{ print file "\t" label "\t" $0 }'
  done | awk -F'\t' -v order="${FZX_SORT:-urgency}" -v mode="${FZX_MODE:-here}" -v nocolor="${NO_COLOR+x}" '
    BEGIN {
      R = "\033[0m"; RED = "\033[1;31m"; DIM = "\033[2m"; YEL = "\033[33m"; CYAN = "\033[36m"; BLUE = "\033[34m"; GREEN = "\033[32m"; WHITE = "\033[2;37m"
      if (nocolor != "") R = RED = DIM = YEL = CYAN = BLUE = GREEN = WHITE = ""
    }
    {
      file = $1; label = $2; start = $3; section = $5; title = $6; due = $7; over = $8; prio = $9; cat = $10; done = $11
      # the project column: the section heading up to its colon (without its number) in here mode, the
      # repository in all mode
      proj = (mode == "here") ? section : label; sub(/:.*/, "", proj); sub(/^[0-9]+\. +/, "", proj); sub(/\/TODO\.md$/, "", proj)
      if (length(proj) > 28) proj = substr(proj, 1, 27) "~"
      mark = done ? DIM "P" prio R : prio == 1 ? RED "P1" R : prio == 3 ? DIM "P3" R : YEL "P2" R
      box = done ? GREEN "☑" R : WHITE "☐" R
      tag = due == "" ? "" : (over ? "  " RED "[due " due ", OVERDUE]" R : "  " (done ? DIM : YEL) "[due " due "]" R)
      line = label ":" start " " (done ? "☑" : "☐") "  (P" prio ")" (cat == "" ? "" : " [" cat "]") " " title (due == "" ? "" : " [due " due "]")
      key = order == "file" ? sprintf("%s %09d", file, start) : sprintf("%d %d %d %s %s %09d", done, !over, prio, (due == "" ? "9999-99-99" : due), file, start)
      # the id: file, line and title, \x1f-separated (titles can hold colons); done checks the title
      printf "%s\t%s\037%s\037%s\t%s  %s  %s%-8s%s  %s%-28s%s  %s%s\t%s\t%s\n", key, file, start, title, box, mark, CYAN, (cat == "" ? "-" : cat), R, BLUE, proj, R, (done ? DIM title R : title), tag, line, title
    }' | sort -t $'\t' -k1,1 | cut -f2-
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" todos
  todos::source "$@"
}
