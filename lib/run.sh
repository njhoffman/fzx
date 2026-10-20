#!/usr/bin/env bash
# run: launch a module in a new session, resume an existing session, or run a module standalone.

# fzx::run_new <module[:mode]> <dry_run> <keep> <popup> [module args...]; the calling process becomes the owner.
# <popup> is "" (inline), "default" (FZX_POPUP_OPTS) or fzf --popup options.
fzx::run_new() {
  local target="$1" dry_run="$2" keep="$3" popup="$4" module mode="" dir
  shift 4
  module="${target%%:*}"
  [[ "$target" == *:* ]] && mode="${target#*:}"
  dir="$(fzx::module_find "$module")" || fzx::die 2 "module not found: $module (FZX_MODULE_PATH=$FZX_MODULE_PATH)"

  fzx::require gc
  fzx::gc --quiet

  fzx::session_create "$module" "$dir" "$@" || fzx::die 1 "cannot create session in $FZX_SESSIONS_DIR"
  _FZX_OWNER=1
  _FZX_ROOT_SESSION="$FZX_SESSION"
  if ((keep)); then
    fzx::meta_set keep 1
  else
    trap 'fzx::_owner_cleanup' EXIT
  fi
  [[ -n "$popup" ]] && fzx::state_set popup "$popup"
  local rc
  fzx::_launch "$dry_run" "$mode"
  rc=$?
  ((dry_run)) || fzx::_stat_exit "$rc"
  return "$rc"
}

# exit row: duration of the whole run, attributed to the session the user was in when it ended
fzx::_stat_exit() {
  local rc="$1" started now current kind
  fzx::require stats
  fzx::session_attach "$_FZX_ROOT_SESSION" || return 0
  fzx::meta_get started_ms started || started=0
  fzx::now_ms now
  fzx::state_get current current && fzx::session_attach "$current" || current="$_FZX_ROOT_SESSION"
  fzx::meta_get module FZX_MODULE
  fzx::state_get mode FZX_MODE || FZX_MODE=-
  case "$rc" in
    0) kind=accept ;;
    1) kind=nomatch ;;
    2) kind=error ;;
    130) kind=abort ;;
    *) kind=rc ;;
  esac
  fzx::stat exit "$((now - started))" - "rc:$rc $kind"
  fzx::session_attach "$_FZX_ROOT_SESSION"
}

fzx::_owner_cleanup() {
  fzx::session_attach "$_FZX_ROOT_SESSION" && fzx::session_destroy
}

# fzx::run_resume <sid> <dry_run> [mode]; never cleans up, the owner does
fzx::run_resume() {
  local sid="$1" dry_run="$2" mode="${3:-}"
  fzx::session_attach "$sid" || fzx::die 2 "no such session: ${sid:-<FZX_SESSION unset>}"
  fzx::log info "session resumed${mode:+ mode=$mode}"
  fzx::_launch "$dry_run" "$mode"
}

# fzx::run_standalone <module_dir> [module args...]; no session, cache or navigation.
# The mode comes from $FZX_MODE (default: the first mode).
fzx::run_standalone() {
  FZX_STANDALONE=1
  FZX_MODULE_DIR="$1"
  FZX_MODULE="${1##*/}"
  shift
  FZX_ARGS=("$@")
  fzx::config_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  fzx::_module_modes
  local mode="${FZX_MODE:-${FZX_MODES[0]}}"
  fzx::_mode_valid "$mode" || fzx::die 2 "unknown mode for $FZX_MODULE: $mode (modes: ${FZX_MODES[*]})"
  export FZX_MODE="$mode"
  fzx::opts_build "$FZX_MODULE" || fzx::die 1 "$FZX_MODULE::opts failed"
  fzx::_fzf
}

# fzx::_launch <dry_run> <requested mode or "">
fzx::_launch() {
  local dry_run="$1" requested="$2" mode
  fzx::meta_get module FZX_MODULE
  fzx::meta_get module_dir FZX_MODULE_DIR
  fzx::session_args

  fzx::config_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  # shellcheck source=/dev/null
  source "$FZX_MODULE_DIR/module.sh" || fzx::die 1 "cannot load $FZX_MODULE_DIR/module.sh"

  # only validated here; the ttl itself is read again by the callbacks
  # shellcheck disable=SC2034
  local ttl
  fzx::persist_ttl "$FZX_PERSIST" ttl || fzx::die 1 "$FZX_MODULE: invalid FZX_PERSIST: '$FZX_PERSIST' (none, session or cache:<ttl>)"
  fzx::meta_set persist "$FZX_PERSIST"

  fzx::_module_modes
  printf '%s\0' "${FZX_MODES[@]}" > "$FZX_SESSION_DIR/meta/modes"
  if [[ -n "$requested" ]]; then
    fzx::_mode_valid "$requested" || fzx::die 2 "unknown mode for $FZX_MODULE: $requested (modes: ${FZX_MODES[*]})"
    mode="$requested"
  else
    fzx::session_mode mode
    if ! fzx::_mode_valid "$mode"; then
      fzx::log warn "saved mode '$mode' no longer exists, using ${FZX_MODES[0]}"
      mode="${FZX_MODES[0]}"
    fi
  fi
  fzx::state_set mode "$mode"
  export FZX_MODE="$mode"

  fzx::opts_build "$FZX_MODULE" || fzx::die 1 "$FZX_MODULE::opts failed"
  fzx::_placement

  fzx::require stats
  export FZX_STATS FZX_STATS_FILE
  if ((!dry_run)); then
    local root
    fzx::meta_get root root || root="$FZX_SESSION"
    fzx::_kv_set "$FZX_SESSIONS_DIR/$root/state/current" "$FZX_SESSION"
    if [[ -n "${_FZX_OWNER:-}" && -z "${_FZX_STARTED:-}" ]]; then
      _FZX_STARTED=1
      fzx::stat start 0 - "$FZX_MODULE${FZX_ARGS[*]:+ ${FZX_ARGS[*]}}"
    fi
  fi

  if ((dry_run)); then
    printf '# module  %s:%s (%s)\n# session %s (%s)\n' \
      "$FZX_MODULE" "$FZX_MODE" "$FZX_MODULE_DIR" "$FZX_SESSION" "$FZX_SESSION_DIR"
    fzx::opts_print
    return 0
  fi
  fzx::_fzf
}

# placement is per session tree (the root's state/popup) and applied on every launch: fzf runs become()
# from a popup in the original terminal, not inside the popup, so each launch has to ask for the popup
# again to stay in it (observed with fzf 0.74; see docs/design.md)
fzx::_placement() {
  local popup="" root
  fzx::meta_get root root || root="$FZX_SESSION"
  fzx::_kv_get "$FZX_SESSIONS_DIR/$root/state/popup" popup || return 0
  [[ -n "$popup" ]] || return 0
  if [[ -z "${TMUX:-}" && -z "${ZELLIJ:-}" ]]; then
    fzx::log warn "popup requested outside tmux/Zellij, running inline"
    return 0
  fi
  [[ "$popup" == default ]] && popup="$FZX_POPUP_OPTS"
  FZX_OPTS+=("--popup=$popup")
}

# modes declared by the module's <module>::modes hook into FZX_MODES; default is the single mode "main"
fzx::_module_modes() {
  local m
  FZX_MODES=()
  if declare -F "$FZX_MODULE::modes" > /dev/null; then
    "$FZX_MODULE::modes"
  fi
  ((${#FZX_MODES[@]})) || FZX_MODES=(main)
  for m in "${FZX_MODES[@]}"; do
    [[ "$m" =~ ^[A-Za-z0-9_-]+$ ]] || fzx::die 1 "$FZX_MODULE::modes: invalid mode name: '$m'"
  done
}

fzx::_mode_valid() {
  local m
  for m in "${FZX_MODES[@]}"; do
    [[ "$m" == "$1" ]] && return 0
  done
  return 1
}

# The owner runs fzf as a child so it can clean up when the become() chain ends. Every other launch
# (resume, mode restart, navigation) execs fzf: otherwise each become() would leave one more waiting
# bash process behind it and the process chain would grow with every navigation.
fzx::_fzf() {
  local start end rc
  if [[ -z "${_FZX_OWNER:-}" && -z "${FZX_STANDALONE:-}" ]]; then
    fzx::log info "fzf exec module=$FZX_MODULE mode=$FZX_MODE opts=${#FZX_OPTS[@]}"
    exec fzf "${FZX_OPTS[@]}" < /dev/null
  fi
  fzx::now_ms start
  fzx::log info "fzf start module=$FZX_MODULE mode=$FZX_MODE opts=${#FZX_OPTS[@]}"
  fzf "${FZX_OPTS[@]}" < /dev/null
  rc=$?
  fzx::now_ms end
  fzx::log info "fzf exit rc=$rc $((end - start))ms"
  return "$rc"
}
