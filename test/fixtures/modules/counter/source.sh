#!/usr/bin/env bash
# counter source: increments $COUNTER_FILE on each run so tests can tell cache hits from source runs.
# Lines are prefixed with $FZX_MODE. COUNTER_FAIL=1 prints a partial line and exits 3.

counter::source() {
  local n=0
  [[ -f "$COUNTER_FILE" ]] && n="$(< "$COUNTER_FILE")"
  n=$((n + 1))
  printf '%s' "$n" > "$COUNTER_FILE"
  printf 'counter stderr run %s\n' "$n" >&2
  if [[ -n "${COUNTER_FAIL:-}" ]]; then
    printf 'partial-%s\n' "$n"
    return 3
  fi
  printf '%s:item-%s-a\n%s:item-%s-b\n' "${FZX_MODE:-}" "$n" "${FZX_MODE:-}" "$n"
  (($#)) && printf 'args:%s\n' "$*"
  return 0
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && counter::source "$@"
