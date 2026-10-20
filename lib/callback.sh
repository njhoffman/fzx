#!/usr/bin/env bash
# callback: handlers behind `fzx _cb <verb>`, invoked by fzf binds. Keep the load path minimal:
# preview runs on every focus change, so it loads only log and session.

# fzx::callback <load|source|preview|action|mode|nav> [args...]
fzx::callback() {
  local verb="${1:-}" start end rc
  shift
  fzx::require log session
  fzx::session_attach || fzx::die 2 "callback '$verb' outside a session (FZX_SESSION=${FZX_SESSION:-})"
  fzx::meta_get module FZX_MODULE
  fzx::meta_get module_dir FZX_MODULE_DIR
  fzx::now_ms start

  case "$verb" in
    load) fzx::_cb_load ;;
    source) fzx::_cb_source ;;
    preview) fzx::_cb_call preview preview "$@" ;;
    action) fzx::_cb_call actions action "$@" 2>> "$FZX_LOG_FILE" ;;
    mode)
      fzx::require nav
      fzx::nav_mode "$@"
      ;;
    nav)
      fzx::require nav
      fzx::nav "$@"
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
  [[ "$verb" == preview ]] && level=debug
  ((rc == 0)) || level=error
  fzx::log "$level" "cb $verb${*:+ $*} rc=$rc $((end - start))ms"
  return "$rc"
}

# current mode into FZX_MODE (exported, so the source sees it)
fzx::_cb_mode() {
  fzx::session_modes
  fzx::session_mode FZX_MODE
  export FZX_MODE
}

# serve cached data for the current mode when present (session cache, then the persistent cache for
# cache:<ttl> modules), otherwise run the source. persist=none always runs the source.
fzx::_cb_load() {
  local data persist
  fzx::_cb_mode
  fzx::meta_get persist persist || persist=session
  fzx::data_path data "$FZX_MODE"
  if [[ "$persist" != none && -f "$data" ]]; then
    fzx::log debug "load: cache hit $data"
    cat -- "$data"
    return
  fi
  if [[ "$persist" == cache:* ]] && fzx::_cb_persistent_load "$persist" "$data"; then
    return
  fi
  fzx::_cb_source
}

# fzx::_cb_persistent_path <var>: persistent cache file for this module, args, cwd and mode
fzx::_cb_persistent_path() {
  local _key=""
  fzx::meta_get cache_key _key || return 1
  printf -v "$1" '%s/%s/%s/%s' "$FZX_CACHE_DIR" "$FZX_MODULE" "$_key" "$FZX_MODE"
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
  cat -- "$2"
}

# run the module source, streaming to fzf while writing the cache; the cache is only replaced on success
fzx::_cb_source() {
  local data tmp rc lines persist file
  fzx::_cb_import source source || return
  fzx::_cb_mode
  fzx::meta_get persist persist || persist=session
  fzx::session_args

  if [[ "$persist" == none ]]; then
    "$FZX_MODULE::source" "${FZX_ARGS[@]}" 2>> "$FZX_LOG_FILE"
    rc=$?
    ((rc == 0)) || fzx::log error "source failed mode=$FZX_MODE rc=$rc"
    return "$rc"
  fi

  fzx::data_path data "$FZX_MODE"
  tmp="$data.$BASHPID"
  "$FZX_MODULE::source" "${FZX_ARGS[@]}" 2>> "$FZX_LOG_FILE" | tee -- "$tmp"
  rc="${PIPESTATUS[0]}"
  if ((rc != 0)); then
    rm -f -- "$tmp"
    fzx::log error "source failed mode=$FZX_MODE rc=$rc, cache kept"
    return "$rc"
  fi
  mv -f -- "$tmp" "$data"
  lines="$(wc -l < "$data")"
  fzx::log info "source: mode=$FZX_MODE ${lines// /} lines"

  if [[ "$persist" == cache:* ]] && fzx::_cb_persistent_path file; then
    mkdir -p -- "${file%/*}" && cp -f -- "$data" "$file.$BASHPID" && mv -f -- "$file.$BASHPID" "$file" ||
      fzx::log warn "could not write persistent cache $file"
  fi
  return 0
}

# fzx::_cb_call <script> <function> [args...]
fzx::_cb_call() {
  local script="$1" fn="$2"
  shift 2
  fzx::_cb_import "$script" "$fn" || return
  fzx::_cb_mode
  "$FZX_MODULE::$fn" "$@"
}

# fzx::_cb_import <script> <function>: source <module_dir>/<script>.sh and check <module>::<function>
fzx::_cb_import() {
  local file="$FZX_MODULE_DIR/$1.sh"
  # shellcheck source=/dev/null
  [[ -f "$file" ]] && source "$file"
  if ! declare -F "$FZX_MODULE::$2" > /dev/null; then
    fzx::log error "$FZX_MODULE::$2 not defined (expected in $file)"
    printf 'fzx: %s::%s not defined (expected in %s)\n' "$FZX_MODULE" "$2" "$file" >&2
    return 127
  fi
}
