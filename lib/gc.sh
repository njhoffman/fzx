#!/usr/bin/env bash
# gc: remove session trees whose owner died (crash, killed terminal), orphaned children, and stale
# persistent cache entries. Runs quietly on every new session and as `fzx gc`.

# fzx::gc [--all] [--quiet]   --all also removes trees kept with --keep
fzx::gc() {
  local all=0 quiet=0 dir sid root keep trees=0 orphans=0 files=0
  while (($#)); do
    case "$1" in
      --all) all=1 ;;
      --quiet) quiet=1 ;;
      *)
        printf 'usage: fzx gc [--all]\n' >&2
        return 2
        ;;
    esac
    shift
  done
  fzx::require config
  fzx::config_load

  for dir in "$FZX_SESSIONS_DIR"/*/; do
    dir="${dir%/}"
    [[ -d "$dir/meta" ]] || continue
    sid="${dir##*/}"
    root="$sid"
    fzx::_kv_get "$dir/meta/root" root || :
    if [[ "$root" == "$sid" ]]; then
      fzx::owner_alive "$dir" && continue
      keep=""
      fzx::_kv_get "$dir/meta/keep" keep || :
      [[ "$keep" == 1 ]] && ((!all)) && continue
      # destroy in a subshell: attaching changes FZX_SESSION, which the caller may still need
      (fzx::session_attach "$sid" && fzx::session_destroy) && trees=$((trees + 1))
    elif [[ ! -d "$FZX_SESSIONS_DIR/$root/meta" ]]; then
      rm -rf -- "$dir"
      orphans=$((orphans + 1))
    fi
  done

  if [[ -d "$FZX_CACHE_DIR" ]]; then
    files="$(find "$FZX_CACHE_DIR" -type f -mtime "+$((FZX_CACHE_MAX_AGE_DAYS - 1))" -print -delete 2> /dev/null | wc -l)"
    find "$FZX_CACHE_DIR" -mindepth 1 -type d -empty -delete 2> /dev/null
  fi

  ((trees + orphans + files)) && fzx::log info "gc: removed $trees trees, $orphans orphans, $files cache files"
  ((quiet)) || printf 'removed %s session trees, %s orphaned sessions, %s cache files\n' "$trees" "$orphans" "$files"
  return 0
}
