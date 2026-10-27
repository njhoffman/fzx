#!/usr/bin/env bash
# recent source. Lines are "absolute path<TAB>display", best first; paths that no longer exist are dropped.
# Mode from $FZX_MODE. Files: nvim (telescope-frecency's database), fasd (fasd -f); args are words, each of
# which must appear in the path, in order, ignoring case. Directories: zlua (z.lua), dirs (zoxide),
# fasd-dirs (fasd -d), visited (fasd, by last visit); args are keywords for the tool, which matches them
# its own way (zoxide: the last word against the last path component).

# recent::kind [mode]: files or dirs
recent::kind() {
  case "${1:-${FZX_MODE:-nvim}}" in
    nvim | fasd) echo files ;;
    *) echo dirs ;;
  esac
}

# recent::zlua <var>: the z.lua script (FZX_RECENT_ZLUA, or found in the usual places), or fail
recent::zlua() {
  local _s="${FZX_RECENT_ZLUA:-}" _c
  [[ "$_s" == none ]] && return 1
  if [[ -z "$_s" ]]; then
    for _c in "${ZLUA_SCRIPT:-}" "$HOME"/.zinit/plugins/*z.lua/z.lua "$HOME"/.local/share/zinit/plugins/*z.lua/z.lua \
      "$HOME/.local/share/z.lua/z.lua"; do
      [[ -n "$_c" && -f "$_c" ]] && { _s="$_c"; break; }
    done
  fi
  [[ -n "$_s" && -f "$_s" ]] || return 1
  printf -v "$1" '%s' "$_s"
}

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

# recent::score: "score path" (the tools' own spacing) -> "score<TAB>path", scores under 10 with a decimal
recent::score() {
  awk '{ s = $1; sub(/^ *[^ ]+ +/, ""); printf "%s\t%s\n", (s < 10 ? sprintf("%.1f", s) : sprintf("%.0f", s)), $0 }'
}

# recent::format <files|dirs>: "score<TAB>path" -> "path<TAB>display" (dim score, prettypath when on, as
# directories in the dirs kind), only paths that still exist as that kind
recent::format() {
  local kind="$1" dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m' in line test=-f pretty=() width=5
  [[ "$kind" == dirs ]] && test=-d pretty=(--dirs) width=7
  in="$(cat)"
  [[ -n "$in" ]] || return 0
  fzx::require pretty
  if fzx::pretty_on; then
    # prettypath decorates the paths; joined back to their scores by path, in the input's order (by path,
    # not by line: an older prettypath can drop lines, which keep a plain display)
    awk -F'\t' -v dim="$dim" -v rst="$rst" -v w="$width" 'NR == FNR { shown[$1] = $2; next }
      { path = $2; sub(/\/$/, "", path); disp = (path in shown) ? shown[path] : "  " path
        printf "%s\t%s%*s%s  %s\n", path, dim, w, $1, rst, disp }' \
      <(cut -f2 <<< "$in" | fzx::pretty "${pretty[@]}") - <<< "$in"
  else
    awk -F'\t' -v home="$HOME" -v dim="$dim" -v rst="$rst" -v w="$width" '
      { path = $2; sub(/\/$/, "", path); shown = path
        if (index(shown, home "/") == 1) shown = "~" substr(shown, length(home) + 1)
        n = split(shown, parts, "/"); name = parts[n]
        printf "%s\t%s%*s%s  %s%s%s%s\n", path, dim, w, $1, rst, dim, substr(shown, 1, length(shown) - length(name)), rst, name }' <<< "$in"
  fi | while IFS= read -r line; do
    test "$test" "${line%%$'\t'*}" && printf '%s\n' "$line"
  done
}

# recent::source [words...]
recent::source() {
  local mode="${FZX_MODE:-nvim}" zl
  case "$mode" in
    nvim) recent::nvim | recent::match "$@" ;;
    fasd) command fasd -f -R -s | awk '{ s = $1; sub(/^[^ ]+ +/, ""); printf "%d\t%s\n", s, $0 }' | recent::match "$@" ;;
    zlua)
      if ! recent::zlua zl; then
        printf 'recent: z.lua not found (set FZX_RECENT_ZLUA)\n' >&2
        return 2
      fi
      # z.lua lists the best match last
      command "$FZX_RECENT_ZLUA_LUA" "$zl" -l "$@" | tac | recent::score
      ;;
    dirs) command zoxide query --list --score -- "$@" | recent::score ;;
    fasd-dirs) command fasd -d -R -s "$@" | recent::score ;;
    visited) command fasd -d -t -R -l "$@" | awk '{ printf "%d\t%s\n", NR, $0 }' ;;
    *)
      printf 'recent: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac | recent::format "$(recent::kind "$mode")"
  # zoxide and fasd exit non-zero when nothing matches the words; an empty list is not an error
  return 0
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" recent
  recent::source "$@"
}
