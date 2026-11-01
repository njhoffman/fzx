#!/usr/bin/env bash
# history source: zsh-histdb's commands, one row per command (its latest run), as
# "history id<TAB>columns<TAB>command". The id is the latest run's history.id; the command text is looked up by id
# (history::argv), since a command can span lines.
# Mode from $FZX_MODE: session (FZX_HISTDB_SESSION, else this host's latest session), directory ($PWD and
# below, logical and resolved), host (this machine), global (every host; each row names its host).
# Toggles: failed (only commands whose latest run failed), succeeded (only those whose latest run did not;
# a run that exits with one of FZX_HISTORY_INTERRUPTED, 130 and 141, was interrupted: it is neither),
# runs (one row per run instead of per command). Sort recent (default), frequent or frecent (runs weighted
# by how recent they are; a run a day old counts half).
# Rows: the age of the latest run, the run count, the failed icon, the latest run's duration, the host
# (global), the command colored by its parts (a failed one in red).
# host and global by recency are cached ($FZX_CACHE_DIR/history): each run reads only the runs added since,
# and the rows are formatted afresh, so ages stay current.

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

# the raw row's columns: history id, command id, start, runs, exit status, duration, host, command (its
# newlines as \x1e, which history::format draws as lines or as ↵; tabs as spaces)
HISTORY_RAW_COLS="ifnull(history.exit_status, 0), ifnull(history.duration, ''), ifnull(places.host, ''),
  replace(replace(commands.argv, char(10), char(30)), char(9), ' ')"

# history::raw <where> <order: recent|frequent|frecent> [extra condition]: one raw row per command, its
# latest run's columns (sqlite takes bare columns from the row holding max())
history::raw() {
  local order
  case "$2" in
    frequent) order="count(*) desc, max(history.start_time) desc" ;;
    frecent) order="sum(1.0 / (1 + max($(date +%s) - history.start_time, 0) / 86400.0)) desc, max(history.start_time) desc" ;;
    *) order="max(history.start_time) desc" ;;
  esac
  history::sql "
    select history.id, history.command_id, max(history.start_time), count(*), $HISTORY_RAW_COLS
    from history
      join commands on commands.id = history.command_id
      join places on places.id = history.place_id
    where $1 ${3:+and $3}
    group by history.command_id
    order by $order"
}

# history::raw_runs <where>: one raw row per run, newest first (the runs toggle)
history::raw_runs() {
  history::sql "
    select history.id, history.command_id, history.start_time, '', $HISTORY_RAW_COLS
    from history
      join commands on commands.id = history.command_id
      join places on places.id = history.place_id
    where $1
    order by history.start_time desc, history.id desc"
}

# history::cache_dir: where host and global keep their rows
history::cache_dir() { printf '%s/history' "$FZX_CACHE_DIR"; }

# history::cache_clear: drop the cached rows (after forgetting commands)
history::cache_clear() { rm -f -- "$(history::cache_dir)"/*.rows "$(history::cache_dir)"/*.last 2> /dev/null || :; }

# history::raw_cached <mode> <where>: history::raw by recency, from the cache plus the runs added since.
# The commands run since (from the last cached run on: histdb fills a run's status and duration when it
# ends) are queried afresh and lead; the cached rows of the rest follow in their order. A database whose
# last run is older than the cache's (replaced, or rows removed) is read whole again.
history::raw_cached() {
  local mode="$1" where="$2" dir key rows last cached="" now_last tmp
  dir="$(history::cache_dir)"
  key="$mode"
  [[ "$mode" == host ]] && key="host-$(history::host)"
  # v2: the newline marker; v1 rows held " ↵ ", and are removed rather than read
  key="${key//[^A-Za-z0-9._-]/_}"
  rm -f -- "$dir/$key.rows" "$dir/$key.last" 2> /dev/null || :
  key+=.v2
  rows="$dir/$key.rows" last="$dir/$key.last"
  now_last="$(history::sql 'select ifnull(max(id), 0) from history')" || return
  [[ -s "$rows" && -s "$last" ]] && read -r cached < "$last"
  mkdir -p -- "$dir" || {
    history::raw "$where" recent
    return
  }
  tmp="$rows.$BASHPID"
  # tee -p: the cache is written whole even when fzf stops reading (a quick pick)
  local -a ps
  if [[ "$cached" =~ ^[0-9]+$ ]] && ((cached <= now_last)); then
    {
      history::raw "$where" recent "history.command_id in (select history.command_id from history
        join places on places.id = history.place_id where history.id >= $cached and $where)" |
        tee -p -- "$tmp.new"
      [[ "${PIPESTATUS[*]}" == "0 0" ]] || exit 1
      awk -F'\x1f' 'FILENAME == ARGV[1] { seen[$2] = 1; next } !($2 in seen)' "$tmp.new" "$rows"
    } | tee -p -- "$tmp"
    ps=("${PIPESTATUS[@]}")
    rm -f -- "$tmp.new"
  else
    history::raw "$where" recent | tee -p -- "$tmp"
    ps=("${PIPESTATUS[@]}")
  fi
  if [[ "${ps[*]}" == "0 0" ]]; then
    mv -f -- "$tmp" "$rows" && printf '%s\n' "$now_last" > "$last"
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

# history::interrupted_sql: FZX_HISTORY_INTERRUPTED as an SQL list ("130,141"; "-1" for none)
history::interrupted_sql() {
  local c out=""
  for c in ${FZX_HISTORY_INTERRUPTED-130 141}; do
    [[ "$c" =~ ^[0-9]+$ ]] && out+="${out:+,}$c"
  done
  printf '%s' "${out:--1}"
}

# history::format <mode>: raw rows -> "id<TAB>display" rows, filtered by the failed and succeeded toggles
history::format() {
  local failed interrupted hosts=""
  fzx::require icons
  fzx::icon failed failed
  fzx::icon interrupted interrupted
  [[ "$1" == global ]] && hosts="$(history::sql 'select distinct host from places order by host' | tr '\n' ' ')"
  # mawk formats about twice as fast; the rows only measure ASCII (ages, counts, hosts)
  local awk=awk
  command -v mawk > /dev/null && awk=mawk
  # shellcheck disable=SC2016  # the program looks for "$" in commands
  "$awk" -F'\x1f' -v now="$(date +%s)" -v sort="${FZX_SORT:-recent}" -v toggles=" ${FZX_TOGGLES:-} " \
    -v failed="$failed" -v interrupted="$interrupted" -v intr="$(history::interrupted_sql)" \
    -v ic="${FZX_COLORS[history_interrupted]:-38;5;179}" -v hosts="$hosts" \
    -v ml="${FZX_HISTORY_MULTILINE:-1}" -v maxl="${FZX_HISTORY_MAX_LINES:-4}" -v me="$(history::host)" -v nocolor="${NO_COLOR+x}" \
    -v dim="${FZX_COLORS[dim]:-38;5;244}" -v red="${FZX_COLORS[history_failed]:-38;5;203}" \
    -v hl="${FZX_COLORS[sorted]:-4}" '
    function esc(code) { return nocolor != "" ? "" : "\033[" code "m" }
    function c(code, text) { return nocolor != "" || text == "" ? text : "\033[" code "m" text "\033[0m" }
    # a span of seconds as 45s, 12m, 3h, 5d, 2w, 4mo or 3y
    function span(s) {
      return s < 60 ? int(s) "s" : s < 3600 ? int(s / 60) "m" : s < 86400 ? int(s / 3600) "h" : \
        s < 1209600 ? int(s / 86400) "d" : s < 5184000 ? int(s / 604800) "w" : s < 31536000 ? int(s / 2592000) "mo" : int(s / 31536000) "y"
    }
    # the age in a color that fades with it
    function agecolor(s) { return s < 3600 ? "38;5;255" : s < 86400 ? "38;5;252" : s < 604800 ? "38;5;248" : s < 2592000 ? "38;5;245" : "38;5;240" }
    function durcolor(s) { return s > 300 ? red : s > 60 ? "38;5;221" : dim }
    # the command colored by its parts: command words bold, options blue, quoted text green, variables
    # cyan, operators yellow, the newline marks dim. Branches on the first character and uses prebuilt
    # escapes: this runs on every word of every row.
    function command(a,  n, w, i, out, word, first, q, ch, last, core, tail) {
      n = split(a, w, " "); out = ""; first = 1; q = ""
      for (i = 1; i <= n; i++) {
        word = w[i]; ch = substr(word, 1, 1); last = substr(word, length(word))
        if (q != "") {
          core = word; if (last ~ /[;,)|&]/) sub(/[;,)|&]+$/, "", core)
          if (substr(core, length(core)) == q) { q = ""; first = last == ";" }
          word = QS word E
        } else if (ch == "\047" || ch == "\"") {
          core = word; if (last ~ /[;,)|&]/) sub(/[;,)|&]+$/, "", core)
          if (length(core) == 1 || substr(core, length(core)) != ch) q = ch
          word = QS word E; first = q == "" && last == ";"
        } else if (word in ops) { word = OP word E; first = 1 }
        else if (word in redir) word = OP word E
        else if (word == "↵") { word = NL word E; first = 1 }
        else {
          tail = ""
          if (last == ";" && length(word) > 1) { tail = OP ";" E; word = substr(word, 1, length(word) - 1) }
          if (first) {
            first = (word in prefix) || (index(word, "=") > 1 && word ~ /^[A-Za-z_][A-Za-z0-9_]*=/)
            word = CW word E
          } else if (ch == "-") word = OPT word E
          else if (index(word, "$")) word = VAR word E
          else word = ARG word E
          if (tail != "") { word = word tail; first = 1 }
        }
        out = out (i > 1 ? " " : "") word
      }
      return out
    }
    BEGIN {
      only_failed = index(toggles, " failed ") > 0; only_ok = index(toggles, " succeeded ") > 0
      E = nocolor != "" ? "" : "\033[0m"
      CW = esc("1;38;5;255"); OPT = esc("38;5;110"); QS = esc("38;5;150"); VAR = esc("38;5;116")
      OP = esc("38;5;221"); ARG = esc("38;5;250"); NL = esc("38;5;240")
      split("| || && ; |& &", t, " "); for (i in t) ops[t[i]] = 1
      split("> >> < << >& &> 2> 2>> 1> 2>&1", t, " "); for (i in t) redir[t[i]] = 1
      split("sudo env time nohup exec command builtin noglob nice xargs watch do then else elif while until if ! { (", t, " "); for (i in t) prefix[t[i]] = 1
      split(intr, t, ","); for (i in t) stopped[t[i]] = 1
      split("110 151 180 216 146 174 109 186", pal, " ")
      nh = split(hosts, hl_, " "); hw = 0
      for (i = 1; i <= nh; i++) { hostc[hl_[i]] = hl_[i] == me ? dim : "38;5;" pal[(i - 1) % 8 + 1]; if (length(hl_[i]) > hw) hw = length(hl_[i]) }
      # the columns before the command, and the tab (--tabstop=1): continuation lines start under it
      pad = sprintf("%*s", 4 + 1 + 5 + 1 + (failed == "" ? 0 : 2) + 4 + 1 + (hw ? hw + 1 : 0) + 1, "")
      if (maxl < 1) maxl = 1
    }
    {
      st = $5 + 0
      # bad: the run failed; cut: it was interrupted (neither red nor failed)
      cut = st != 0 && (st "") in stopped; bad = st != 0 && !cut
      if (only_failed && !bad) next
      if (only_ok && bad) next
      age = now - $3; if (age < 0) age = 0
      a = span(age); n = $4 > 1 ? $4 "x" : ""
      d = ($6 != "" && $6 >= 1) ? span($6) : ""
      line = sprintf("%*s", 4 - length(a), "") (sort == "recent" ? c(agecolor(age) ";" hl, a) : c(agecolor(age), a))
      line = line " " sprintf("%*s", 5 - length(n), "") (sort == "frequent" && n != "" ? c(dim ";" hl, n) : c(dim, n))
      line = line " " (failed == "" ? "" : (bad ? c(red, failed) " " : cut ? c(ic, interrupted) " " : "  "))
      line = line sprintf("%*s", 4 - length(d), "") c(durcolor($6 + 0), d) " "
      if (hw) line = line c(($7 in hostc) ? hostc[$7] : dim, $7) sprintf("%*s", hw - length($7), "") " "
      # the command in a field of its own: the only one searched (--nth); a command over several lines
      # is an item over several lines (NUL-terminated, --read0), the lines under the first, up to maxl
      # of them; with multi-line off they are joined by ↵
      if (!ml) {
        cmd = $8; gsub(/\036/, " ↵ ", cmd)
        printf "%s\t%s\t%s\n", $1, line, (bad ? c(red, cmd) : command(cmd))
        next
      }
      nl = split($8, cl, "\036"); out = ""
      for (i = 1; i <= nl && i <= maxl; i++) out = out (i > 1 ? "\n" pad : "") (bad ? c(red, cl[i]) : command(cl[i]))
      if (nl > maxl) out = out "\n" pad c(dim, "… +" (nl - maxl) " lines")
      printf "%s\t%s\t%s%c", $1, line, out, 0
    }'
}

history::source() {
  local where mode="${FZX_MODE:-global}" sort="${FZX_SORT:-recent}"
  [[ -r "$FZX_HISTDB_FILE" ]] || { printf 'history: no histdb database at %s\n' "$FZX_HISTDB_FILE" >&2; return 2; }
  where="$(history::where "$mode")" || { printf 'history: unknown mode: %s\n' "$mode" >&2; return 2; }
  {
    if [[ " ${FZX_TOGGLES:-} " == *" runs "* ]]; then
      history::raw_runs "$where"
    elif [[ "$sort" == recent && ("$mode" == host || "$mode" == global) ]]; then
      history::raw_cached "$mode" "$where"
    else
      history::raw "$where" "$sort"
    fi
  } | history::format "$mode"
  return "${PIPESTATUS[0]}"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" history
  history::source "$@"
}
