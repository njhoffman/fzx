#!/usr/bin/env bash
# ps source: one line per process, header first. PID is left-aligned so {1} works with any --delimiter.
# Mode from $FZX_MODE: user (default, own processes by cpu), all (every process by cpu), tree (forest).

# ps::source [--ppid PID]   only the direct children of PID
ps::source() {
  local mode="${FZX_MODE:-user}" scope sort=(--sort=-%cpu) ppid=""
  while (($#)); do
    case "$1" in
      --ppid)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || {
          printf 'ps: --ppid needs a pid, got: %s\n' "${2:-}" >&2
          return 2
        }
        ppid="$2"
        shift
        ;;
      *)
        printf 'ps: unknown argument: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done

  case "$mode" in
    user) scope=(--user="${USER:-$(id -un)}") ;;
    all) scope=(-e) ;;
    tree) scope=(-e) sort=(--forest) ;;
    *)
      printf 'ps: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
  [[ -n "$ppid" ]] && scope=(--ppid "$ppid")

  # ps exits 1 both on errors and when nothing matches; only a match-less run still prints the header
  local out rc
  out="$(command ps "${scope[@]}" -o pid,ppid,user,%cpu,%mem,rss,etime,stat,tty,args "${sort[@]}")"
  rc=$?
  if ((rc != 0)) && [[ "$out" != *PID* ]]; then
    return "$rc"
  fi
  printf '%s\n' "$out" |
    awk '{ match($0, /^ *[^ ]+/); w = RLENGTH; f = substr($0, 1, w); gsub(/ /, "", f)
           printf "%-" w "s%s\n", f, substr($0, w + 1) }'
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && ps::source "$@"
