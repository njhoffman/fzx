#!/usr/bin/env bash
# sessions menu entry: always listed (a kept or live tree may exist in another terminal)

sessions::manifest() {
  fzx::entry sessions "fzx sessions: resume a kept one, copy a live one"
}

# sessions::summary <target>: kept and live trees other than the menu's own
sessions::summary() {
  local dir sid root keep kept=0 live=0 own=""
  fzx::require session
  [[ -n "${FZX_SESSION:-}" ]] && { own="$FZX_SESSION"; fzx::_kv_get "$FZX_SESSIONS_DIR/$FZX_SESSION/meta/root" own || :; }
  for dir in "$FZX_SESSIONS_DIR"/*/; do
    dir="${dir%/}"
    [[ -d "$dir/meta" ]] || continue
    sid="${dir##*/}" root="$sid" keep=""
    fzx::_kv_get "$dir/meta/root" root || :
    [[ "$root" == "$sid" && "$sid" != "$own" ]] || continue
    if fzx::owner_alive "$dir"; then live=$((live + 1))
    else fzx::_kv_get "$dir/meta/keep" keep || :; [[ "$keep" == 1 ]] && kept=$((kept + 1)); fi
  done
  printf '%s kept, %s live\n' "$kept" "$live"
}
