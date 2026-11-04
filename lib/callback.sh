#!/usr/bin/env bash
# callback: handlers behind `fzx _cb <verb>`, invoked by fzf binds. Keep the load path minimal:
# preview runs on every focus change, so it loads only log and session.

# fzx::callback <load|source|preview|action|transform|mode|nav|layout|prompt> [args...]
# transform <name> [args]: <module>::transform from actions.sh, which prints fzf actions
# Handlers describe their stats row in _FZX_STAT=(event count detail [mode]); preview never does.
fzx::callback() {
  local verb="${1:-}" start end rc
  shift
  _FZX_STAT=()
  fzx::require log session
  fzx::session_attach || fzx::die 2 "callback '$verb' outside a session (FZX_SESSION=${FZX_SESSION:-})"
  fzx::meta_get module FZX_MODULE
  fzx::meta_get module_dir FZX_MODULE_DIR
  fzx::now_ms start

  case "$verb" in
    load) fzx::_cb_load ;;
    source) fzx::_cb_source reload ;;
    preview) fzx::_cb_call preview preview "$@" ;;
    action)
      fzx::_cb_action "$@" 2>> "$FZX_LOG_FILE"
      rc=$?
      _FZX_STAT=(action "$(($# > 0 ? $# - 1 : 0))" "${1:-}:$rc")
      (exit "$rc")
      ;;
    transform) fzx::_cb_actions fzx::_cb_call actions transform "$@" ;;
    notify)
      fzx::_cb_actions fzx::_cb_notify "$@"
      rc=$?
      _FZX_STAT=(action "$(($# > 0 ? $# - 1 : 0))" "${1:-}:$_FZX_NOTIFY_RC")
      (exit "$rc")
      ;;
    footer)
      fzx::require nav
      fzx::nav_footer
      ;;
    mode)
      fzx::require nav
      fzx::_cb_actions fzx::nav_mode "$@"
      ;;
    header)
      fzx::require nav
      fzx::nav_header
      ;;
    toggle)
      fzx::require nav
      fzx::_cb_actions fzx::nav_toggle "$@"
      ;;
    sort)
      fzx::require nav
      fzx::_cb_actions fzx::nav_sort "$@"
      ;;
    nav)
      fzx::require nav
      fzx::_cb_actions fzx::nav "$@"
      ;;
    trace) fzx::_cb_trace "$@" ;;
    prompt) fzx::_cb_prompt ;;
    layout)
      fzx::require layout
      fzx::_cb_actions fzx::layout "$@"
      ;;
    debug)
      fzx::require debug
      fzx::debug_preview "$@"
      ;;
    *)
      fzx::log error "unknown callback verb: $verb"
      printf 'fzx: unknown callback verb: %s\n' "$verb" >&2
      return 2
      ;;
  esac
  rc=$?

  fzx::now_ms end
  local level=info
  [[ "$verb" == preview || "$verb" == trace || "$verb" == prompt ]] && level=debug
  ((rc == 0)) || level=error
  fzx::log "$level" "cb $verb${*:+ $*} rc=$rc $((end - start))ms"
  if ((${#_FZX_STAT[@]})); then
    fzx::require stats
    # FZX_MODE inherited from fzf's environment goes stale after an in-place mode switch: resolve it,
    # unless the handler names the mode the event belongs to (_FZX_STAT[3])
    if [[ -n "${_FZX_STAT[3]:-}" ]]; then
      FZX_MODE="${_FZX_STAT[3]}"
    else
      fzx::_cb_mode
    fi
    fzx::stat "${_FZX_STAT[0]}" "$((end - start))" "${_FZX_STAT[1]}" "${_FZX_STAT[2]}"
  fi
  return "$rc"
}

# fzx::_cb_prompt: the loaded prompt of the current mode (fzx::_prompt_binds wrote one per mode), for
# load's transform-prompt; reads two files, no config
fzx::_cb_prompt() {
  local mode="" prompt=""
  fzx::session_modes
  fzx::session_mode mode
  fzx::meta_get "prompt.$mode" prompt || return 0
  printf '%s' "$prompt"
}

# fzx::_cb_actions <handler> [args...]: run a handler whose stdout is fzf actions, logging what it
# returns (debug level) so the actions fzf receives can be inspected with `fzx debug tail`
# (through a file, not $(...): the handler must run in this shell so the _FZX_STAT it sets survives)
fzx::_cb_actions() {
  local _out="" _rc _file="$FZX_SESSION_DIR/actions.$BASHPID"
  "$@" > "$_file" 2>> "$FZX_LOG_FILE"
  _rc=$?
  fzx::_kv_get "$_file" _out || :
  rm -f -- "$_file"
  fzx::log debug "actions: ${_out:-<none>}"
  printf '%s' "$_out"
  return "$_rc"
}

# current mode into FZX_MODE (exported, so the source sees it)
fzx::_cb_mode() {
  fzx::session_modes
  fzx::session_mode FZX_MODE
  export FZX_MODE
  # toggles and sort ride along with the mode
  fzx::require components
  local _modes=("${FZX_MODES[@]}")
  fzx::comp_load_session
  FZX_MODES=("${_modes[@]}")
  fzx::comp_current
}

# fzx::_cb_persist <var>: the module's persist policy for the current mode: a mode flagged nopersist (its
# rows follow the query, files:grep) keeps a cache:<ttl> module's data to the session
fzx::_cb_persist() {
  local _p _f=""
  fzx::meta_get persist _p || _p=session
  if [[ "$_p" == cache:* ]] && fzx::comp_field mode "$FZX_MODE" flags _f 2> /dev/null && [[ ",$_f," == *,nopersist,* ]]; then
    _p=session
  fi
  printf -v "$1" '%s' "$_p"
}

# serve cached data for the current mode when present (session cache, then the persistent cache for
# cache:<ttl> modules), otherwise run the source. persist=none always runs the source.
fzx::_cb_load() {
  local data persist view
  fzx::_cb_mode
  # an action flagged reload or restart asked for fresh data (nav restart, the actions menu)
  if [[ -f "$FZX_SESSION_DIR/state/fresh" ]]; then
    rm -f -- "$FZX_SESSION_DIR/state/fresh"
    fzx::_cb_source reload
    return
  fi
  fzx::_cb_persist persist
  fzx::data_key view
  fzx::data_path data "$view"
  if [[ "$persist" != none && -f "$data" ]]; then
    fzx::log debug "load: cache hit $data"
    _FZX_STAT=(cache "$(fzx::_cb_lines "$data")" session)
    cat -- "$data"
    return
  fi
  if [[ "$persist" == cache:* ]] && fzx::_cb_persistent_load "$persist" "$data"; then
    return
  fi
  fzx::_cb_source miss
}

# fzx::_cb_count: count the items on stdin: lines, or NULs for a module with FZX_READ0 (meta/read0)
fzx::_cb_count() {
  local _r=0
  fzx::meta_get read0 _r 2> /dev/null || _r=0
  if [[ "$_r" == 1 ]]; then
    tr -cd '\0' | wc -c
  else
    wc -l
  fi
}

# item count of a file for stats; skipped (and not forked) when stats are off
fzx::_cb_lines() {
  local n=-
  [[ "${FZX_STATS:-1}" == 1 ]] && n="$(fzx::_cb_count < "$1")" && n="${n// /}"
  printf '%s' "$n"
}

# fzx::_cb_persistent_path <var>: persistent cache file for this module, args, cwd and mode
fzx::_cb_persistent_path() {
  local _key=""
  fzx::meta_get cache_key _key || return 1
  local _view
  fzx::data_key _view
  printf -v "$1" '%s/%s/%s/%s' "$FZX_CACHE_DIR" "$FZX_MODULE" "$_key" "$_view"
}

# fzx::_cb_persistent_load <policy> <session data path>: serve a fresh persistent entry, seeding the session cache
fzx::_cb_persistent_load() {
  local ttl file mtime age
  fzx::persist_ttl "$1" ttl || return 1
  fzx::_cb_persistent_path file || return 1
  [[ -f "$file" ]] || return 1
  mtime="$(stat -c %Y -- "$file")" || return 1
  age=$((EPOCHSECONDS - mtime))
  if ((age >= ttl)); then
    fzx::log debug "load: persistent cache expired age=${age}s ttl=${ttl}s"
    return 1
  fi
  cp -f -- "$file" "$2"
  fzx::log info "load: persistent cache hit age=${age}s ttl=${ttl}s"
  _FZX_STAT=(cache "$(fzx::_cb_lines "$2")" persistent)
  cat -- "$2"
}

# fzx::freeze_rows: the source's rows, the display field (meta/freeze) cut where FZX_FREEZE_COL[S] says into
# what stays and the rest, which goes last on the row so that no other field moves. The space at the cut goes:
# the tab between them takes its column. Colors do not count as columns.
fzx::freeze_rows() {
  local _k="" _spec
  fzx::meta_get freeze _k 2> /dev/null || :
  [[ -n "$_k" ]] || { command cat; return; }
  _spec="${FZX_FREEZE_COLS[$FZX_MODE]:-${FZX_FREEZE_COL:-gap}}"
  LC_ALL=C.UTF-8 awk -F'\t' -v OFS='\t' -v k="$_k" -v spec="$_spec" '
    # the column of the space to replace in the plain text, 0 for none
    function target(p,  tail, j) {
      # a gap: its last space, so the frozen part keeps its padding and rows stay aligned while scrolled
      if (spec == "gap") return match(p, /[^ ]  +/) ? RSTART + RLENGTH - 1 : 0
      if (spec == "gap2") {
        if (!match(p, /[^ ]  +/)) return 0
        j = RSTART + RLENGTH - 1; tail = substr(p, j + 1)
        return match(tail, /[^ ]  +/) ? j + RSTART + RLENGTH - 1 : 0
      }
      if (spec == "word") return match(p, /[^ ] /) ? RSTART + 1 : 0
      if (spec ~ /^[0-9]+$/) {
        tail = substr(p, spec + 1); j = index(tail, " ")
        return j ? spec + j : 0
      }
      return 0
    }
    # where column t of the plain text is in the raw text
    function raw(s, t,  pos, seen, gap) {
      pos = 1; seen = 0
      while (match(substr(s, pos), /\033\[[0-9;:]*[A-Za-z]/)) {
        gap = RSTART - 1
        if (seen + gap >= t) break
        seen += gap; pos += gap + RLENGTH
      }
      return pos + t - seen - 1
    }
    {
      for (i = NF + 1; i <= k; i++) $i = ""
      s = $k; p = s; gsub(/\033\[[0-9;:]*[A-Za-z]/, "", p)
      rest = ""
      if ((t = target(p))) { o = raw(s, t); $k = substr(s, 1, o - 1); rest = substr(s, o + 1) }
      print $0, rest
      fflush()
    }'
}

# fzx::_cb_source <miss|reload>: run the module source, streaming to fzf while writing the cache;
# the cache is only replaced on success
fzx::_cb_source() {
  local why="${1:-reload}" data tmp rc lines persist file view
  fzx::_cb_import source source || return
  fzx::_cb_mode
  fzx::_cb_persist persist
  fzx::session_args

  if [[ "$persist" == none ]]; then
    # output streams straight to fzf (fd 3); tee hands a copy to wc for the stats row's line count
    local count="$FZX_SESSION_DIR/count.$BASHPID"
    { "$FZX_MODULE::source" "${FZX_ARGS[@]}" 2>> "$FZX_LOG_FILE" | fzx::freeze_rows | tee /dev/fd/3 | fzx::_cb_count > "$count"; } 3>&1
    rc="${PIPESTATUS[0]}"
    lines=-
    [[ -s "$count" ]] && read -r lines < "$count"
    rm -f -- "$count"
    ((rc == 0)) || fzx::log error "source failed mode=$FZX_MODE rc=$rc"
    if ((rc == 0)); then _FZX_STAT=(source "${lines// /}" "$why"); else _FZX_STAT=(source - "fail:$rc"); fi
    return "$rc"
  fi

  fzx::data_key view
  fzx::data_path data "$view"
  tmp="$data.$BASHPID"
  "$FZX_MODULE::source" "${FZX_ARGS[@]}" 2>> "$FZX_LOG_FILE" | fzx::freeze_rows | tee -- "$tmp"
  rc="${PIPESTATUS[0]}"
  if ((rc != 0)); then
    rm -f -- "$tmp"
    fzx::log error "source failed mode=$FZX_MODE rc=$rc, cache kept"
    _FZX_STAT=(source - "fail:$rc")
    return "$rc"
  fi
  mv -f -- "$tmp" "$data"
  lines="$(fzx::_cb_count < "$data")"
  fzx::log info "source: mode=$FZX_MODE ${lines// /} lines"
  _FZX_STAT=(source "${lines// /}" "$why")

  if [[ "$persist" == cache:* ]] && fzx::_cb_persistent_path file; then
    if ! { mkdir -p -- "${file%/*}" && cp -f -- "$data" "$file.$BASHPID" && mv -f -- "$file.$BASHPID" "$file"; }; then
      fzx::log warn "could not write persistent cache $file"
    fi
  fi
  return 0
}

# fzx::_cb_trace <event>: log an fzf event with what fzf exports about it (FZX_TRACE); prints no action
fzx::_cb_trace() {
  fzx::log info "event ${1:-?} query=${FZF_QUERY@Q} pos=${FZF_POS:-} matches=${FZF_MATCH_COUNT:-}/${FZF_TOTAL_COUNT:-}" \
    "selected=${FZF_SELECT_COUNT:-} size=${FZF_COLUMNS:-}x${FZF_LINES:-} key=${FZF_KEY:-} action=${FZF_ACTION:-}"
}

# fzx::_cb_action <name> [args...]: an action row of the table (confirm first when flagged; built-ins from
# lib/builtin.sh), or a name the module's actions.sh handles without a row
fzx::_cb_action() {
  local name="${1:-}" flags="" desc=""
  fzx::require components
  fzx::comp_load_session
  if fzx::comp_field action "$name" flags flags; then
    if [[ ",$flags," == *,confirm,* ]]; then
      fzx::require builtin
      fzx::comp_field action "$name" description desc
      [[ "$desc" == - ]] && desc=""
      # a mode-scoped description asks with the current mode's part
      local mode="" modes=() row
      fzx::state_get mode mode 2> /dev/null || mode=""
      while IFS=$'\t' read -r _ row _; do modes+=("$row"); done < <(fzx::comp_rows mode)
      ((${#modes[@]})) && fzx::mode_desc "$desc" "$mode" desc "${modes[@]}"
      # the selection only: module args before a "--" are not what is acted on
      local shown=("${@:2}") i
      for ((i = ${#shown[@]} - 1; i >= 0; i--)); do
        [[ "${shown[i]}" == -- ]] && { shown=("${shown[@]:i+1}"); break; }
      done
      if ! fzx::confirm "${desc:-$name}" "${shown[@]}"; then
        fzx::log info "action $name: not confirmed"
        return 0
      fi
    fi
    if [[ ",$flags," == *,builtin,* ]]; then
      fzx::require builtin
      fzx::_cb_mode
      export FZX_MODULE FZX_MODULE_DIR
      fzx::builtin "$@"
      return
    fi
  elif [[ "$name" == copy || "$name" == copy-line ]]; then
    # the menus switch the rows off and keep the keys (lib/opts.sh)
    fzx::require builtin
    fzx::_cb_mode
    export FZX_MODULE FZX_MODULE_DIR
    fzx::builtin "$@"
    return
  fi
  fzx::_cb_call actions action "$@"
}

# fzx::_cb_notify <action> [args...]: run the action (its output discarded), then show what happened in the
# footer for FZX_NOTIFY_SECONDS and put the component line back (`fzx _cb footer`, from the state then)
fzx::_cb_notify() {
  local name="${1:-}" err="$FZX_SESSION_DIR/notify.$BASHPID" line="" desc="" msg color items=("${@:2}") i act
  fzx::_cb_action "$@" > /dev/null 2> "$err"
  _FZX_NOTIFY_RC=$?
  # the selection only: module args before a "--" are not what was acted on
  for ((i = ${#items[@]} - 1; i >= 0; i--)); do
    [[ "${items[i]}" == -- ]] && { items=("${items[@]:i+1}"); break; }
  done
  fzx::require config
  [[ -n "${_FZX_CB_CONFIG:-}" ]] || fzx::config_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  if ((_FZX_NOTIFY_RC == 0)); then
    color="${FZX_COLORS[notify_ok]:-}"
    if [[ "$name" == copy || "$name" == copy-line ]]; then
      if ((${#items[@]} == 1)); then msg="copied ${items[0]}"; else msg="copied ${#items[@]} items"; fi
    else
      fzx::comp_field action "$name" description desc || desc=""
      [[ "$desc" == - ]] && desc=""
      # a mode-scoped description: the current mode's part
      local mode="" modes=() row
      fzx::state_get mode mode 2> /dev/null || mode=""
      while IFS=$'\t' read -r _ row _; do modes+=("$row"); done < <(fzx::comp_rows mode)
      ((${#modes[@]})) && { fzx::mode_desc "$desc" "$mode" desc "${modes[@]}" || :; }
      desc="${desc:-$name}"
      msg="✓ $desc"
      ((${#items[@]} > 1)) && msg+=" (${#items[@]})"
    fi
  else
    color="${FZX_COLORS[notify_fail]:-}"
    IFS= read -r line < "$err" || :
    msg="✗ $name failed${line:+: $line}"
  fi
  cat -- "$err" >> "$FZX_LOG_FILE" 2> /dev/null || :
  rm -f -- "$err"
  fzx::log info "notify $name rc=$_FZX_NOTIFY_RC: $msg"
  # one line, short enough for the footer, no characters that end the action
  msg="${msg//[$'\n\t\r']/ }"
  ((${#msg} > 120)) && msg="${msg:0:119}…"
  [[ -n "$color" && -z "${NO_COLOR+x}" ]] && msg=$'\e['"${color}m$msg"$'\e[0m'
  fzx::require opts
  fzx::action_arg change-footer "$msg" act || act="change-footer(${msg//[()]/})"
  printf '%s+bg-cancel+bg-transform-footer(sleep %s; %s)' "$act" "${FZX_NOTIFY_SECONDS:-2}" "$(fzx::cb footer)"
}

# fzx::_cb_call <script> <function> [args...]
fzx::_cb_call() {
  local script="$1" fn="$2"
  shift 2
  fzx::_cb_import "$script" "$fn" || return
  fzx::_cb_mode
  "$FZX_MODULE::$fn" "$@"
}

# fzx::_cb_import <script> <function>: source <module_dir>/<script>.sh and check <module>::<function>.
# Module code may read config (keys, colors, its own settings), so it is loaded first; this is the only
# config cost on the callback path, a few small files.
fzx::_cb_import() {
  local file="$FZX_MODULE_DIR/$1.sh"
  if [[ -z "${_FZX_CB_CONFIG:-}" ]]; then
    fzx::require config
    fzx::config_load "$FZX_MODULE_DIR" "$FZX_MODULE"
    _FZX_CB_CONFIG=1
  fi
  # shellcheck source=/dev/null
  [[ -f "$file" ]] && source "$file"
  if ! declare -F "$FZX_MODULE::$2" > /dev/null; then
    fzx::log error "$FZX_MODULE::$2 not defined (expected in $file)"
    printf 'fzx: %s::%s not defined (expected in %s)\n' "$FZX_MODULE" "$2" "$file" >&2
    return 127
  fi
}
