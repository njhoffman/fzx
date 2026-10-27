#!/usr/bin/env bash
# history source: zsh-histdb's commands, one row per command (its latest run), as
# "history id<TAB>display". The id is the latest run's history.id; the command text is looked up by id
# (history::argv), since a command can span lines.
# Mode from $FZX_MODE: session (FZX_HISTDB_SESSION, else this host's latest session), directory ($PWD and
# below, logical and resolved), host (this machine), global (every host). Toggle failed: only commands whose
# latest run failed. Sort recent (default) or frequent.

# history::sql <query>: read-only sqlite3 on the histdb file, fields split by \x1f
history::sql() {
  command sqlite3 -readonly -cmd ".timeout 2000" -separator $'\x1f' "$FZX_HISTDB_FILE" "$1"
}

# history::quote <text>: an SQL string literal
history::quote() { printf "'%s'" "${1//\'/\'\'}"; }

# history::host: the host histdb records (zsh's $HOST)
history::host() { printf '%s' "${HOST:-$(hostname)}"; }

# history::session: the shell's histdb session from the widget, else the latest session on this host
history::session() {
  if [[ "${FZX_HISTDB_SESSION:-}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$FZX_HISTDB_SESSION"
    return
  fi
  history::sql "select max(session) from history join places on places.id = history.place_id
    where places.host = $(history::quote "$(history::host)")"
}

# history::where <mode>: the SQL condition for a mode
history::where() {
  local dir real
  case "$1" in
    session) printf 'history.session = %s' "$(history::session)" ;;
    directory)
      dir="${PWD%/}" real="$(pwd -P)"
      # histdb stores the logical $PWD; match the resolved path as well (a symlinked checkout)
      printf "places.host = %s and (places.dir = %s or places.dir like %s escape '!' or places.dir = %s or places.dir like %s escape '!')" \
        "$(history::quote "$(history::host)")" "$(history::quote "$dir")" "$(history::quote "$(history::like "$dir")/%")" \
        "$(history::quote "$real")" "$(history::quote "$(history::like "$real")/%")"
      ;;
    host) printf 'places.host = %s' "$(history::quote "$(history::host)")" ;;
    global) printf '1' ;;
    *) return 1 ;;
  esac
}

# history::like <text>: LIKE metacharacters escaped with ! (the escape character in history::where)
history::like() {
  local s="${1//!/!!}"
  s="${s//%/!%}"
  printf '%s' "${s//_/!_}"
}

# history::argv <history id...>: the command text of each run, NUL-terminated
history::argv() {
  local id argv
  for id in "$@"; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    # $(...) drops the newline sqlite3 ends the row with; newlines inside the command stay
    argv="$(history::sql "select commands.argv from history join commands on commands.id = history.command_id
      where history.id = $id")" || return
    printf '%s\0' "$argv"
  done
}

history::source() {
  local where order having="" dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" red=$'\e['"${FZX_COLORS[history_failed]:-38;5;203}m" rst=$'\e[0m'
  local failed
  fzx::require icons
  fzx::icon failed failed
  [[ -r "$FZX_HISTDB_FILE" ]] || { printf 'history: no histdb database at %s\n' "$FZX_HISTDB_FILE" >&2; return 2; }
  where="$(history::where "${FZX_MODE:-host}")" || { printf 'history: unknown mode: %s\n' "$FZX_MODE" >&2; return 2; }
  [[ " ${FZX_TOGGLES:-} " == *" failed "* ]] && having="having last_status != 0"
  case "${FZX_SORT:-recent}" in
    frequent) order="runs desc, last_start desc" ;;
    *) order="last_start desc" ;;
  esac
  # bare columns with max(): sqlite takes them from the row holding the maximum, the latest run
  history::sql "
    select history.id, max(history.start_time) as last_start, count(*) as runs,
      ifnull(history.exit_status, 0) as last_status,
      case
        when max(history.start_time) >= cast(strftime('%s', 'now', 'start of day') as integer) then strftime('%H:%M', max(history.start_time), 'unixepoch', 'localtime')
        when max(history.start_time) >= cast(strftime('%s', 'now', 'start of year') as integer) then strftime('%m/%d', max(history.start_time), 'unixepoch', 'localtime')
        -- this sqlite's strftime has no %y
        else strftime('%m/%d/', max(history.start_time), 'unixepoch', 'localtime') ||
          substr(strftime('%Y', max(history.start_time), 'unixepoch', 'localtime'), 3)
      end,
      replace(replace(commands.argv, char(10), ' ↵ '), char(9), ' ')
    from history
      join commands on commands.id = history.command_id
      join places on places.id = history.place_id
    where $where
    group by history.command_id
    $having
    order by $order" |
    awk -F'\x1f' -v dim="$dim" -v red="$red" -v rst="$rst" -v failed="$failed" -v sort="${FZX_SORT:-recent}" \
      -v hl=$'\e['"${FZX_COLORS[sorted]:-4}m" '
      # the failed icon (or as much blank) between the count and the command, so commands line up; the
      # sorted column (the time, or the count) also in the sorted color
      { mark = failed == "" ? "" : ($4 != 0 ? red failed rst " " : "  ")
        n = $3 > 1 ? $3 "x" : ""
        printf "%s\t%s%*s%s%s%s %*s%s%s%s  %s%s%s%s\n", $1, dim, 8 - length($5), "", (sort == "frequent" ? "" : hl), $5, rst dim,
          5 - length(n), "", (sort == "frequent" && n != "" ? hl : ""), n, rst, mark, ($4 != 0 ? red : ""), $6, ($4 != 0 ? rst : "") }'
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" history
  history::source "$@"
}
