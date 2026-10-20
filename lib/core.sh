#!/usr/bin/env bash
# core: paths, lazy library loading and small helpers. Safe to source more than once.

[[ -n "${_FZX_CORE_LOADED:-}" ]] && return 0
_FZX_CORE_LOADED=1

FZX_ROOT="${FZX_ROOT:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)}"
# shellcheck disable=SC2034  # used by opts.sh and nav.sh to build callback commands
FZX_BIN="$FZX_ROOT/bin/fzx"
FZX_RUNTIME_DIR="${FZX_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}/fzx-$UID}/fzx}"
FZX_STATE_DIR="${FZX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/fzx}"
FZX_CONFIG_DIR="${FZX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/fzx}"
FZX_CACHE_DIR="${FZX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fzx}"
FZX_MODULE_PATH="${FZX_MODULE_PATH:-$FZX_CONFIG_DIR/modules:$FZX_ROOT/modules}"
export FZX_ROOT FZX_RUNTIME_DIR FZX_STATE_DIR FZX_CONFIG_DIR FZX_CACHE_DIR FZX_MODULE_PATH

declare -gA _FZX_LOADED=()

# source libraries from lib/ once each: fzx::require log session
fzx::require() {
  local lib
  for lib in "$@"; do
    [[ -n "${_FZX_LOADED[$lib]:-}" ]] && continue
    # shellcheck source=/dev/null
    source "$FZX_ROOT/lib/$lib.sh" || return 1
    _FZX_LOADED[$lib]=1
  done
}

# milliseconds since epoch into the named variable (no subshell)
fzx::now_ms() {
  local _us="${EPOCHREALTIME//[.,]/}"
  printf -v "$1" '%s' "$((_us / 1000))"
}

# fzx::parse_duration <90|90s|5m|2h|1d> <var>: seconds into var; fails on anything else or zero
fzx::parse_duration() {
  [[ "$1" =~ ^([0-9]+)([smhd]?)$ ]] || return 1
  local _n="${BASH_REMATCH[1]}"
  case "${BASH_REMATCH[2]}" in
    m) _n=$((_n * 60)) ;;
    h) _n=$((_n * 3600)) ;;
    d) _n=$((_n * 86400)) ;;
  esac
  ((_n > 0)) || return 1
  printf -v "$2" '%s' "$_n"
}

# print an error, log it when logging is loaded, and exit: fzx::die <code> <message>
fzx::die() {
  local code="$1"
  shift
  declare -F fzx::log > /dev/null && fzx::log error "$*"
  printf 'fzx: %s\n' "$*" >&2
  exit "$code"
}

# print the directory of a module found in FZX_MODULE_PATH
fzx::module_find() {
  local name="$1" dir
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  local IFS=:
  for dir in $FZX_MODULE_PATH; do
    if [[ -f "$dir/$name/module.sh" ]]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
  done
  return 1
}

# true when running under fzx (with a session), false when a module runs standalone
fzx::in_session() { [[ -z "${FZX_STANDALONE:-}" ]]; }

# called at the end of every module.sh; runs the module standalone when module.sh is executed directly
fzx::module_main() {
  [[ "${BASH_SOURCE[1]}" == "$0" ]] || return 0
  fzx::require log config opts run
  fzx::run_standalone "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)" "$@"
}
