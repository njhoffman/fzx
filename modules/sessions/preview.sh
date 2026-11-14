#!/usr/bin/env bash
# sessions preview: the session's path from its root, what enter does with it, its module, mode, arguments,
# query, toggles and sort, directory, age, owner and placement, and the views it has cached

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# sessions::preview <sid>
sessions::preview() {
  local sid="${1:-}" dir root rstate label v now started=0 f n
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && b="" d="" r=""
  [[ -n "$sid" ]] || return 0
  fzx::require session
  dir="$FZX_SESSIONS_DIR/$sid"
  [[ -d "$dir/meta" ]] || { printf 'session %s is gone\n' "$sid"; return 0; }
  root="$sid"
  fzx::_kv_get "$dir/meta/root" root || :
  sessions::_state "$FZX_SESSIONS_DIR/$root" rstate
  (fzx::session_attach "$sid" && fzx::session_label label && printf '%s%s%s\n' "$b" "$label" "$r")
  case "$rstate" in
    kept) printf '%skept, its owner gone: enter resumes it here%s\n' "$d" "$r" ;;
    live) printf '%slive in another terminal: enter opens a copy%s\n' "$d" "$r" ;;
    *) printf '%sits owner is gone and it was not kept: enter opens a copy (gc removes it)%s\n' "$d" "$r" ;;
  esac
  echo
  row() { [[ -n "$2" ]] && printf '%s%-10s%s %s\n' "$d" "$1" "$r" "$2"; }
  v=""; fzx::_kv_get "$dir/meta/module" v || :; row module "$v"
  v=""; fzx::_kv_get "$dir/state/mode" v || :; row mode "$v"
  if [[ -s "$dir/meta/args" ]]; then
    local a=()
    mapfile -d '' -t a < "$dir/meta/args"
    row args "${a[*]}"
  fi
  v=""; fzx::_kv_get "$dir/state/query" v || :; row query "$v"
  v=""; fzx::_kv_get "$dir/state/toggles" v || :; row toggles "$v"
  v=""; fzx::_kv_get "$dir/state/sort" v || :; row sort "$v"
  v=""; fzx::_kv_get "$dir/meta/cwd" v || :; row directory "${v/#$HOME/\~}"
  fzx::_kv_get "$dir/meta/started_ms" started || :
  fzx::now_ms now
  sessions::_ago "$started" "$now" v
  row started "$v ago"
  v=""; fzx::_kv_get "$FZX_SESSIONS_DIR/$root/meta/owner_pid" v || :; row owner "$v ($rstate)"
  v=""; fzx::_kv_get "$FZX_SESSIONS_DIR/$root/state/placement" v || v=inline; row placement "$v"
  row session "$sid"
  [[ "$root" != "$sid" ]] && row root "$root"
  if compgen -G "$dir/data/*" > /dev/null; then
    printf '\n%scached views%s\n' "$d" "$r"
    for f in "$dir"/data/*; do
      n="$(wc -l < "$f")"
      printf '  %-24s %s lines\n' "${f##*/}" "$n"
    done
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" sessions
  sessions::preview "$@"
}
