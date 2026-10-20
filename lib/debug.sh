#!/usr/bin/env bash
# debug: inspect sessions and follow the log.

# fzx::debug <ls|tail [sid]>
fzx::debug() {
  local cmd="${1:-}"
  shift
  case "$cmd" in
    ls) fzx::_debug_ls ;;
    tail) fzx::_debug_tail "$@" ;;
    *)
      printf 'usage: fzx debug ls\n       fzx debug tail [sid]\n' >&2
      return 2
      ;;
  esac
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
