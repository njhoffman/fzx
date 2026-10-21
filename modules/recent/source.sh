#!/usr/bin/env bash
# recent source. Lines are "absolute path<TAB>display", best first; files that no longer exist are dropped.
# Mode from $FZX_MODE: nvim (telescope-frecency's database), fasd (fasd -f). Args are words: each must
# appear in the path, in order, ignoring case.

# nvim: telescope-frecency's score, the open count times the average weight of its timestamps by age
# (Julian days: under 4 hours 100, a day 80, 3 days 60, a week 40, a month 20, 90 days 10, older 0)
recent::nvim() {
  command sqlite3 -readonly -separator $'\t' "$FZX_RECENT_NVIM_DB" "
    SELECT CAST(f.count * SUM(CASE WHEN t.age < 0.1667 THEN 100 WHEN t.age < 1 THEN 80 WHEN t.age < 3 THEN 60
                                   WHEN t.age < 7 THEN 40 WHEN t.age < 30 THEN 20 WHEN t.age < 90 THEN 10 ELSE 0 END)
                / COUNT(*) AS INTEGER) AS score, f.path
    FROM files f JOIN (SELECT file_id, julianday('now') - timestamp AS age FROM timestamps) t ON t.file_id = f.id
    GROUP BY f.id ORDER BY score DESC, MIN(t.age)"
}

# recent::match [words...]: "score<TAB>path" lines whose path holds every word, in order, ignoring case
recent::match() {
  awk -F'\t' -v words="$*" 'BEGIN { n = split(tolower(words), w, " ") }
    { p = tolower($2); pos = 1; ok = 1
      for (i = 1; i <= n; i++) { j = index(substr(p, pos), w[i]); if (!j) { ok = 0; break }; pos += j + length(w[i]) - 1 }
      if (ok) print }'
}

# recent::format: "score<TAB>path" -> "path<TAB>display" (dim score, prettypath when on), existing files only
recent::format() {
  local dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m' in line
  in="$(cat)"
  [[ -n "$in" ]] || return 0
  fzx::require pretty
  if fzx::pretty_on; then
    awk -F'\t' -v dim="$dim" -v rst="$rst" 'NR == FNR { shown[$1] = $2; next }
      { disp = ($2 in shown) ? shown[$2] : "  " $2; printf "%s\t%s%5s%s  %s\n", $2, dim, $1, rst, disp }' \
      <(cut -f2 <<< "$in" | fzx::pretty) - <<< "$in"
  else
    awk -F'\t' -v home="$HOME" -v dim="$dim" -v rst="$rst" '
      { shown = $2; if (index(shown, home "/") == 1) shown = "~" substr(shown, length(home) + 1)
        n = split(shown, parts, "/"); name = parts[n]
        printf "%s\t%s%5s%s  %s%s%s%s\n", $2, dim, $1, rst, dim, substr(shown, 1, length(shown) - length(name)), rst, name }' <<< "$in"
  fi | while IFS= read -r line; do
    [[ -f "${line%%$'\t'*}" ]] && printf '%s\n' "$line"
  done
}

# recent::source [words...]
recent::source() {
  case "${FZX_MODE:-nvim}" in
    nvim) recent::nvim ;;
    fasd) command fasd -f -R -s | awk '{ s = $1; sub(/^[^ ]+ +/, ""); printf "%d\t%s\n", s, $0 }' ;;
    *)
      printf 'recent: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac | recent::match "$@" | recent::format
  return 0
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" recent
  recent::source "$@"
}
