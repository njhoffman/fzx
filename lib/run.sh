#!/usr/bin/env bash
# run: launch a module in a new session, resume an existing session, or run a module standalone.

# fzx::run_new <module[:mode]> <dry_run> <keep> [module args...]; the calling process becomes the owner
fzx::run_new() {
  local target="$1" dry_run="$2" keep="$3" module mode="" dir
  shift 3
  module="${target%%:*}"
  [[ "$target" == *:* ]] && mode="${target#*:}"
  dir="$(fzx::module_find "$module")" || fzx::die 2 "module not found: $module (FZX_MODULE_PATH=$FZX_MODULE_PATH)"
  fzx::session_create "$module" "$dir" "$@" || fzx::die 1 "cannot create session in $FZX_SESSIONS_DIR"
  ((keep)) || trap 'fzx::session_destroy' EXIT
  _FZX_OWNER=1
  fzx::_launch "$dry_run" "$mode"
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

  if ((dry_run)); then
    printf '# module  %s:%s (%s)\n# session %s (%s)\n' \
      "$FZX_MODULE" "$FZX_MODE" "$FZX_MODULE_DIR" "$FZX_SESSION" "$FZX_SESSION_DIR"
    fzx::opts_print
    return 0
  fi
  fzx::_fzf
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
