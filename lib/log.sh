#!/usr/bin/env bash
# log: append-only log shared by all sessions; each line is tagged with session id and pid.

declare -gA _FZX_LOG_LEVELS=([debug]=0 [info]=1 [warn]=2 [error]=3)
FZX_LOG_LEVEL="${FZX_LOG_LEVEL:-info}"
FZX_LOG_FILE="${FZX_LOG_FILE:-$FZX_STATE_DIR/fzx.log}"
export FZX_LOG_LEVEL FZX_LOG_FILE

[[ -d "${FZX_LOG_FILE%/*}" ]] || mkdir -p "${FZX_LOG_FILE%/*}" 2> /dev/null

# fzx::log <debug|info|warn|error> <message...>
fzx::log() {
  local level="$1"
  shift
  ((${_FZX_LOG_LEVELS[$level]:-1} >= ${_FZX_LOG_LEVELS[$FZX_LOG_LEVEL]:-1})) || return 0
  local us="${EPOCHREALTIME#*[.,]}"
  printf '%(%F %T)T.%s %-16s %-7s %-5s %s\n' -1 "${us:0:3}" "${FZX_SESSION:--}" "$BASHPID" "$level" "$*" \
    >> "$FZX_LOG_FILE" 2> /dev/null
  return 0
}
