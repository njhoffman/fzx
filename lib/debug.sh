#!/usr/bin/env bash
# debug: inspect sessions and follow the log.

# fzx::debug <ls | tail [sid] | attach [sid] | state [sid] [limit] | send <action> [sid]>
fzx::debug() {
  local cmd="${1:-}"
  shift
  case "$cmd" in
    ls) fzx::_debug_ls ;;
    tail) fzx::_debug_tail "$@" ;;
    attach) fzx::_debug_attach "$@" ;;
    state) fzx::_debug_state "$@" ;;
    send) fzx::_debug_send "$@" ;;
    *)
      cat >&2 << 'EOF2'
usage: fzx debug ls                     sessions, their module:mode, parent and owner
       fzx debug tail [SID]             follow the log (all sessions, or one)
       fzx debug attach [SID]           interactive: inspect and drive a running fzf
       fzx debug state [SID] [LIMIT]    print the fzf state once (JSON)
       fzx debug send ACTION [SID]      send one fzf action, e.g. 'change-query(foo)'
SID defaults to the newest session whose fzf is listening (the one on screen).
EOF2
      return 2
      ;;
  esac
}

# fzx::_debug_sock <var> [sid]: socket of the given session, or of the newest session whose fzf
# answers (sessions navigated away from are no longer listening)
fzx::_debug_sock() {
  local _sid="${2:-}" _dir _best="" _best_ms=0 _ms
  command -v curl > /dev/null || fzx::die 1 "debug: curl is required to talk to fzf's --listen socket"
  if [[ -n "$_sid" ]]; then
    [[ -S "$FZX_SESSIONS_DIR/$_sid/fzf.sock" ]] || fzx::die 2 "no listening fzf for session: $_sid"
    printf -v "$1" '%s' "$FZX_SESSIONS_DIR/$_sid/fzf.sock"
    return
  fi
  for _dir in "$FZX_SESSIONS_DIR"/*/; do
    _dir="${_dir%/}"
    [[ -S "$_dir/fzf.sock" ]] || continue
    command curl -s -m 1 --unix-socket "$_dir/fzf.sock" 'http://localhost?limit=0' > /dev/null 2>&1 || continue
    _ms=0
    fzx::_kv_get "$_dir/meta/started_ms" _ms || :
    if ((_ms >= _best_ms)); then
      _best="$_dir" _best_ms="$_ms"
    fi
  done
  [[ -n "$_best" ]] || fzx::die 2 "no running fzx session is listening"
  printf -v "$1" '%s' "$_best/fzf.sock"
}

# GET the state (limit = number of matches included)
fzx::_debug_get() {
  command curl -s -m 2 --unix-socket "$1" "http://localhost?limit=${2:-10}"
}

# POST an action; fzf answers nothing on success and an error text otherwise
fzx::_debug_post() {
  local out
  out="$(command curl -s -m 2 -w '\n%{http_code}' --unix-socket "$1" -X POST http://localhost --data-binary "$2")" || {
    printf 'fzx: fzf is not answering on %s\n' "$1" >&2
    return 1
  }
  local code="${out##*$'\n'}" body="${out%$'\n'*}"
  body="${body%$'\n'}"
  if [[ "$code" != 200 ]]; then
    printf 'fzf: %s\n' "${body:-HTTP $code}" >&2
    return 1
  fi
}

# human-readable state: jq when available, raw JSON otherwise
fzx::_debug_show() {
  if command -v jq > /dev/null; then
    jq -r '"query     \(.query | @json)",
           "position  \(.position)   matches \(.matchCount)/\(.totalCount)   selected \(.selected | length)   reading \(.reading)",
           (if (.selected | length) > 0 then "selected", (.selected[] | "  \(.index)\t\(.text)") else empty end),
           "current   \(.current.text // "-")",
           (if (.matches | length) > 0 then "matches" else empty end),
           (.matches[] | "  \(.index)\t\(.text)")'
  else
    cat
    printf '\n'
  fi
}

fzx::_debug_state() {
  local sid="" limit=10 sock
  [[ "${1:-}" =~ ^[0-9]+$ ]] && limit="$1" && shift
  sid="${1:-}"
  [[ "${2:-}" =~ ^[0-9]+$ ]] && limit="$2"
  fzx::_debug_sock sock "$sid"
  fzx::_debug_get "$sock" "$limit"
  printf '\n'
}

fzx::_debug_send() {
  [[ -n "${1:-}" ]] || fzx::die 2 "usage: fzx debug send ACTION [SID]"
  local sock
  fzx::_debug_sock sock "${2:-}"
  fzx::_debug_post "$sock" "$1"
}

# interactive: built-ins below, anything else is sent to fzf as an action
fzx::_debug_attach() {
  local sock line sid label="" module="" mode="" json n
  fzx::_debug_sock sock "${1:-}"
  sid="${sock%/fzf.sock}"
  fzx::_kv_get "$sid/meta/module" module || :
  fzx::_kv_get "$sid/state/mode" mode || :
  sid="${sid##*/}"
  label="$module${mode:+:$mode}"
  printf 'attached to %s (%s); "help" for commands, ctrl-d to leave\n' "$sid" "$label"
  HISTFILE="$FZX_STATE_DIR/debug_history"
  history -r "$HISTFILE" 2> /dev/null
  while IFS= read -r -e -p "fzx[$label]> " line; do
    [[ -n "$line" ]] || continue
    history -s -- "$line"
    case "$line" in
      quit | exit | q) break ;;
      help | '?')
        cat << 'EOF2'
  state [N]     query, position, counts, current item and the first N matches (default 10)
  raw [N]       the same as JSON
  quit          leave (fzf keeps running)
  <action>      anything else is sent to fzf as an action, e.g. reload(seq 10), change-query(foo),
                down+toggle, preview(date), change-prompt(> ), accept (see fzf --man, AVAILABLE ACTIONS)
EOF2
        ;;
      state | 'state '*)
        n="${line#state}"
        json="$(fzx::_debug_get "$sock" "${n// /}")" || { printf 'fzf is not answering\n'; continue; }
        printf '%s' "$json" | fzx::_debug_show
        ;;
      raw | 'raw '*)
        n="${line#raw}"
        fzx::_debug_get "$sock" "${n// /}"
        printf '\n'
        ;;
      *) fzx::_debug_post "$sock" "$line" && printf 'ok\n' ;;
    esac
  done
  history -w "$HISTFILE" 2> /dev/null
  return 0
}

fzx::_debug_ls() {
  local dir sid module mode parent owner cwd status
  printf '%-28s %-16s %-28s %-8s %-6s %s\n' SESSION MODULE PARENT OWNER STATUS CWD
  for dir in "$FZX_SESSIONS_DIR"/*/; do
    [[ -d "$dir/meta" ]] || continue
    sid="${dir%/}"
    sid="${sid##*/}"
    module="" mode="" parent="" owner="" cwd=""
    fzx::_kv_get "$dir/meta/module" module
    fzx::_kv_get "$dir/state/mode" mode
    fzx::_kv_get "$dir/meta/parent" parent
    fzx::_kv_get "$dir/meta/owner_pid" owner
    fzx::_kv_get "$dir/meta/cwd" cwd
    status=dead
    fzx::owner_alive "${dir%/}" && status=alive
    printf '%-28s %-16s %-28s %-8s %-6s %s\n' "$sid" "$module${mode:+:$mode}" "${parent:--}" "$owner" "$status" "$cwd"
  done
}

fzx::_debug_tail() {
  local sid="${1:-}"
  [[ -f "$FZX_LOG_FILE" ]] || : > "$FZX_LOG_FILE"
  if [[ -n "$sid" ]]; then
    tail -n 50 -F -- "$FZX_LOG_FILE" | grep --line-buffered -F " $sid "
  else
    tail -n 50 -F -- "$FZX_LOG_FILE"
  fi
}
