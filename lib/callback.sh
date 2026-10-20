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

# serve cached data for the current mode when present, otherwise run the source
fzx::_cb_load() {
  local data
  fzx::_cb_mode
  fzx::data_path data "$FZX_MODE"
  if [[ -f "$data" ]]; then
    fzx::log debug "load: cache hit $data"
    cat -- "$data"
    return
  fi
  fzx::_cb_source
}

# run the module source, streaming to fzf while writing the cache; the cache is only replaced on success
fzx::_cb_source() {
  local data tmp rc lines
  fzx::_cb_import source source || return
  fzx::_cb_mode
  fzx::data_path data "$FZX_MODE"
  tmp="$data.$BASHPID"
  fzx::session_args

  "$FZX_MODULE::source" "${FZX_ARGS[@]}" 2>> "$FZX_LOG_FILE" | tee -- "$tmp"
  rc="${PIPESTATUS[0]}"
  if ((rc == 0)); then
    mv -f -- "$tmp" "$data"
    lines="$(wc -l < "$data")"
    fzx::log info "source: mode=$FZX_MODE ${lines// /} lines"
  else
    rm -f -- "$tmp"
    fzx::log error "source failed mode=$FZX_MODE rc=$rc, cache kept"
  fi
  return "$rc"
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
