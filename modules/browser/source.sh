#!/usr/bin/env bash
# browser source: history or bookmarks of every Chromium-family and Firefox profile, as rows
#   src  url  display  title  extra  date  epoch  label
# src is "chrome:Default" or "firefox:abcd.default" (browser name, then the profile directory); extra is the
# visit count (history) or the folder (bookmarks). Mode from $FZX_MODE: history (default) or bookmarks.
# $FZX_TOGGLES: chrome and firefox pick the browsers (both when unset). $FZX_SORT: history by recent
# (default) or visits. Databases are copied first: a running browser keeps them locked.

# browser::profiles: "src<TAB>label<TAB>directory" per profile of the browsers the toggles leave on
browser::profiles() {
  local toggles=" ${FZX_TOGGLES-chrome firefox} " name dir d base label ini src
  if [[ "$toggles" == *" chrome "* ]]; then
    for name in "${!FZX_BROWSER_CHROMIUM_DIRS[@]}"; do
      dir="${FZX_BROWSER_CHROMIUM_DIRS[$name]}"
      [[ -d "$dir" ]] || continue
      for d in "$dir"/*/; do
        d="${d%/}" base="${d##*/}"
        [[ -f "$d/History" || -f "$d/Bookmarks" ]] || continue
        # the profile's own name from Local State, else its directory
        label=""
        [[ -f "$dir/Local State" ]] &&
          label="$(command jq -r --arg p "$base" '.profile.info_cache[$p].name // empty' "$dir/Local State" 2> /dev/null)"
        printf '%s:%s\t%s %s\t%s\n' "$name" "$base" "$name" "${label:-$base}" "$d"
      done
    done
  fi
  if [[ "$toggles" == *" firefox "* ]]; then
    ini="${FZX_BROWSER_FIREFOX_DIR:-$HOME/.mozilla/firefox}/profiles.ini"
    [[ -f "$ini" ]] || return 0
    awk -v root="${ini%/*}" '
      function flush() {
        if (path != "") printf "firefox:%s\tfirefox %s\t%s\n", base(path), (name != "" ? name : base(path)), (rel ? root "/" path : path)
        path = ""; name = ""; rel = 1
      }
      function base(p) { sub(/.*\//, "", p); return p }
      /^\[/ { flush(); prof = ($0 ~ /^\[Profile/); next }
      prof && /^Name=/ { name = substr($0, 6) }
      prof && /^Path=/ { path = substr($0, 6) }
      prof && /^IsRelative=/ { rel = (substr($0, 12) == "1") }
      END { flush() }' "$ini" | while IFS=$'\t' read -r src label d; do
      [[ -f "$d/places.sqlite" ]] && printf '%s\t%s\t%s\n' "$src" "$label" "$d"
    done
    return 0
  fi
}

# browser::_copy <tmpdir> <file...>: copy a database and its journal files (-wal, -journal) into tmpdir
browser::_copy() {
  local tmp="$1" f
  shift
  for f; do
    [[ -f "$f" ]] || continue
    command cp -- "$f" "$tmp/" 2> /dev/null || return 1
    [[ -f "$f-wal" ]] && command cp -- "$f-wal" "$tmp/" 2> /dev/null
    [[ -f "$f-journal" ]] && command cp -- "$f-journal" "$tmp/" 2> /dev/null
  done
  return 0
}

# browser::_clean <column>: SQL for the column with tabs and newlines as spaces (they would break the rows)
browser::_clean() {
  printf "replace(replace(replace(coalesce(%s, ''), char(9), ' '), char(10), ' '), char(13), ' ')" "$1"
}

# browser::_sql <db> <query>: tab-separated rows (an unreadable database lists nothing)
browser::_sql() {
  command sqlite3 -batch -noheader -separator $'\t' "$1" "$2" 2> /dev/null || :
}

# browser::_history <src> <label> <dir>: "src title url visits date epoch label" rows of one profile
browser::_history() {
  local src="$1" label="$2" dir="$3" tmp max="${FZX_BROWSER_HISTORY_MAX:-5000}" title
  [[ "$max" =~ ^[0-9]+$ ]] || max=5000
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/fzx-browser.XXXXXX")" || return 0
  if [[ "$src" == firefox:* ]]; then
    title="$(browser::_clean title)"
    browser::_copy "$tmp" "$dir/places.sqlite" && browser::_sql "$tmp/places.sqlite" "
      SELECT $title, url, visit_count, strftime('%Y-%m-%d %H:%M', last_visit_date / 1000000, 'unixepoch', 'localtime'),
        last_visit_date / 1000000
      FROM moz_places WHERE last_visit_date IS NOT NULL AND hidden = 0 AND url NOT LIKE 'place:%'
      ORDER BY last_visit_date DESC LIMIT $max"
  else
    title="$(browser::_clean title)"
    # Chrome counts microseconds from 1601
    browser::_copy "$tmp" "$dir/History" && browser::_sql "$tmp/History" "
      SELECT $title, url, visit_count,
        strftime('%Y-%m-%d %H:%M', last_visit_time / 1000000 - 11644473600, 'unixepoch', 'localtime'),
        last_visit_time / 1000000 - 11644473600
      FROM urls WHERE hidden = 0 AND last_visit_time > 0 ORDER BY last_visit_time DESC LIMIT $max"
  fi | awk -F'\t' -v OFS='\t' -v s="$src" -v l="$label" 'NF >= 5 { print s, $1, $2, $3, $4, $5, l }'
  rm -rf -- "$tmp"
}

# browser::_bookmarks <src> <label> <dir>: "src title url folder date epoch label" rows of one profile
browser::_bookmarks() {
  local src="$1" label="$2" dir="$3" tmp title
  if [[ "$src" != firefox:* ]]; then
    [[ -f "$dir/Bookmarks" ]] || return 0
    # Chrome's Bookmarks is JSON: folders nest, dates are microseconds from 1601
    command jq -r --arg s "$src" --arg l "$label" '
      def clean: gsub("[\t\n\r]"; " ");
      def walk_bm($p):
        if .type == "folder" then (.name | clean) as $n | (.children // [])[] | walk_bm(if $p == "" then $n else $p + "/" + $n end)
        elif .type == "url" then
          (((.date_added // "0") | tonumber) / 1000000 - 11644473600 | floor) as $t
          | [$s, (.name // "" | clean), .url, $p, (if $t > 0 then ($t | strflocaltime("%Y-%m-%d")) else "" end), ([$t, 0] | max), $l] | @tsv
        else empty end;
      .roots | to_entries[] | .value | objects | walk_bm("")' "$dir/Bookmarks" 2> /dev/null
    return 0
  fi
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/fzx-browser.XXXXXX")" || return 0
  title="$(browser::_clean b.title)"
  # folders by their path from the root (menu, toolbar, unfiled, mobile); the tags folder repeats bookmarks
  browser::_copy "$tmp" "$dir/places.sqlite" && browser::_sql "$tmp/places.sqlite" "
    WITH RECURSIVE f(id, path) AS (
      SELECT id, '' FROM moz_bookmarks WHERE parent = 0
      UNION ALL
      SELECT b.id, CASE WHEN f.path = '' THEN coalesce(b.title, '') ELSE f.path || '/' || coalesce(b.title, '') END
      FROM moz_bookmarks b JOIN f ON b.parent = f.id WHERE b.type = 2)
    SELECT CASE WHEN coalesce(b.title, '') = '' THEN $(browser::_clean p.title) ELSE $title END, p.url, f.path,
      strftime('%Y-%m-%d', b.dateAdded / 1000000, 'unixepoch', 'localtime'), b.dateAdded / 1000000
    FROM moz_bookmarks b JOIN moz_places p ON p.id = b.fk JOIN f ON f.id = b.parent
    WHERE b.type = 1 AND p.url NOT LIKE 'place:%' AND f.path NOT LIKE 'tags%'
    ORDER BY f.path, b.position" |
    awk -F'\t' -v OFS='\t' -v s="$src" -v l="$label" 'NF >= 5 { print s, $1, $2, $3, $4, $5, l }'
  rm -rf -- "$tmp"
}

# browser::rows <label width>: the display column; rows come in as "src title url extra date epoch label"
browser::rows() {
  local lw="${1:-20}" mode="${FZX_MODE:-history}" c=$'\e['"${FZX_COLORS[browser_chrome]:-38;5;75}m"
  local f=$'\e['"${FZX_COLORS[browser_firefox]:-38;5;209}m" d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && c="" f="" d="" r=""
  awk -F'\t' -v OFS='\t' -v lw="$lw" -v mode="$mode" -v c="$c" -v f="$f" -v d="$d" -v r="$r" '
    function pad(t, w) { return length(t) > w ? substr(t, 1, w - 1) "…" : sprintf("%-" w "s", t) }
    {
      col = ($1 ~ /^firefox:/) ? f : c
      mid = mode == "bookmarks" ? pad($4, 24) : pad($5, 16)
      disp = col pad($7, lw) r "  " d mid r "  " pad($2, 60) "  " d $3 r
      print $1, $3, disp, $2, $4, $5, $6, $7
    }'
}

browser::source() {
  local mode="${FZX_MODE:-history}" fn sort="${FZX_SORT:-recent}" src label dir profiles lw=0
  case "$mode" in
    history) fn=browser::_history ;;
    bookmarks) fn=browser::_bookmarks ;;
    *)
      printf 'browser: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
  command -v sqlite3 > /dev/null || [[ "$mode" == bookmarks ]] || { printf 'browser: needs sqlite3\n' >&2; return 1; }
  profiles="$(browser::profiles)"
  # the profile column as wide as the widest label, at most 30
  while IFS=$'\t' read -r src label dir; do
    ((${#label} > lw)) && lw=${#label}
  done <<< "$profiles"
  ((lw > 30)) && lw=30
  # the header row (lib/header.sh; history, which has a sort): the date marked when sorted by it
  fzx::require header
  fzx::header_print 2 "$([[ "$sort" == recent ]] && echo VISITED)" \
    PROFILE "$lw" 0 "" 0 0 VISITED 16 0 "" 0 0 TITLE 60 0 "" 0 0 URL 0 0
  while IFS=$'\t' read -r src label dir; do
    [[ -n "$src" ]] && "$fn" "$src" "$label" "$dir"
  done <<< "$profiles" | {
    # history: the newest (or most visited) first across profiles; bookmarks keep each profile's order
    if [[ "$mode" == history && "$sort" == visits ]]; then
      sort -t$'\t' -s -k4,4nr -k6,6nr
    elif [[ "$mode" == history ]]; then
      sort -t$'\t' -s -k6,6nr
    else
      cat
    fi
  } | browser::rows "$lw"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" browser
  browser::source "$@"
}
