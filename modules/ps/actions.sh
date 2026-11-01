#!/usr/bin/env bash
# ps actions: signal processes, trace one with strace.

# ps::_signal <SIG> <pid...>: signal each pid; one that is not yours goes through `sudo -n` (a cached sudo,
# so it never prompts: term and kill do not get the terminal). A pid neither reaches fails the action with
# a message for the footer.
ps::_signal() {
  local sig="$1" pid rc=0
  shift
  for pid in "$@"; do
    kill "-$sig" -- "$pid" 2> /dev/null && continue
    if [[ -d "/proc/$pid" && ! -O "/proc/$pid" ]] && command sudo -n kill "-$sig" -- "$pid" 2> /dev/null; then
      continue
    fi
    if [[ -d "/proc/$pid" ]]; then
      printf 'ps: %s: not yours (sudo-term or sudo-kill ask for the password)\n' "$pid" >&2
    else
      printf 'ps: %s: no such process\n' "$pid" >&2
    fi
    rc=1
  done
  return "$rc"
}

# ps::_as_tracer <pid> <cmd...>: run cmd directly when ptrace allows it (root, or your own process with
# kernel.yama.ptrace_scope 0), else through sudo (in the foreground, so it can prompt)
ps::_as_tracer() {
  local pid="$1" scope=0
  shift
  [[ -r /proc/sys/kernel/yama/ptrace_scope ]] && read -r scope < /proc/sys/kernel/yama/ptrace_scope
  if [[ "$EUID" -eq 0 ]] || { [[ "$scope" == 0 && -O "/proc/$pid" ]]; }; then
    "$@"
  else
    command sudo "$@"
  fi
}

# ps::_trace <pid> [strace args...]: follow the process and its threads until ctrl-c
ps::_trace() {
  local pid="$1"
  shift
  command -v strace > /dev/null || {
    printf 'ps: strace is not installed (press a key)\n' >&2
    read -r -s -n 1 2> /dev/null || :
    return 1
  }
  trap : INT
  ps::_as_tracer "$pid" strace -f "$@" -p "$pid"
  return 0
}

# ps::action <term|kill|sudo-term|sudo-kill|trace|trace-errors> <pid...> (trace: the first pid)
ps::action() {
  local action="${1:-}" pid
  shift
  (($#)) || {
    printf 'ps: %s: no pids given\n' "$action" >&2
    return 2
  }
  for pid in "$@"; do
    [[ "$pid" =~ ^[0-9]+$ ]] || {
      printf 'ps: not a pid: %s\n' "$pid" >&2
      return 2
    }
  done

  case "$action" in
    term) ps::_signal TERM "$@" ;;
    kill) ps::_signal KILL "$@" ;;
    sudo-term) command sudo kill -TERM -- "$@" ;;
    sudo-kill) command sudo kill -KILL -- "$@" ;;
    trace) ps::_trace "$1" ;;
    trace-errors) ps::_trace "$1" -Z ;;
    *)
      printf 'ps: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && ps::action "$@"
