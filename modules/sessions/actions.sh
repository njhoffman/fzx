#!/usr/bin/env bash
# sessions actions: delete kept trees; the enter transform (resume a kept tree, copy any other)

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# sessions::_root <sid> <var>: the session's root
sessions::_root() {
  printf -v "$2" '%s' "$1"
  fzx::_kv_get "$FZX_SESSIONS_DIR/$1/meta/root" "$2" || :
}

# sessions::action delete <sid...>: delete the selected sessions' trees, kept ones whose owner is gone only
sessions::action() {
  local action="${1:-}" sid root st rc=0
  shift
  fzx::require session
  case "$action" in
    delete)
      local -A seen=()
      for sid; do
        [[ -n "$sid" && "$sid" != */* && -d "$FZX_SESSIONS_DIR/$sid/meta" ]] || continue
        sessions::_root "$sid" root
        [[ -n "${seen[$root]:-}" ]] && continue
        seen[$root]=1
        sessions::_state "$FZX_SESSIONS_DIR/$root" st
        if [[ "$st" == live ]]; then
          printf 'sessions: %s is live in another terminal: quit it there\n' "$root" >&2
          rc=1
          continue
        fi
        (fzx::session_attach "$root" && fzx::session_destroy) || rc=$?
      done
      ;;
    *)
      printf 'sessions: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  return "$rc"
}

# sessions::transform enter <sid>: a kept tree whose owner is gone resumes in this terminal (this list's
# fzf becomes it); any other opens as a copy: a screen of this list with the session's module, mode and
# arguments, its toggles, sort and query copied over
sessions::transform() {
  local name="${1:-}" sid="${2:-}" root st module mode="" args=() out child f
  [[ "$name" == enter ]] || { printf 'sessions: unknown transform: %s\n' "$name" >&2; return 2; }
  [[ -n "$sid" && "$sid" != */* && -d "$FZX_SESSIONS_DIR/$sid/meta" ]] || { printf 'bell'; return 0; }
  fzx::require session nav
  sessions::_root "$sid" root
  sessions::_state "$FZX_SESSIONS_DIR/$root" st
  if [[ "$st" == kept ]]; then
    fzx::state_set query "${FZF_QUERY:-}"
    fzx::state_set pos "${FZF_POS:-1}"
    # this list's owner adopts the tree: it relaunches the tree's screens on a placement change into or out
    # of a pane (lib/run.sh), and as the tree's owner while it runs here other terminals see it live (they
    # open a copy); once the owner exits the tree is kept again, its owner gone
    local own_root="$FZX_SESSION" f
    fzx::meta_get root own_root || :
    for f in owner_pid owner_start; do
      cp -- "$FZX_SESSIONS_DIR/$own_root/meta/$f" "$FZX_SESSIONS_DIR/$root/meta/$f" 2> /dev/null || :
    done
    fzx::_kv_set "$FZX_SESSIONS_DIR/$own_root/state/adopt" "$root"
    fzx::log info "sessions: resume $sid"
    _FZX_STAT=(nav - "resume:$sid")
    fzx::_nav_become "$sid"
    return
  fi
  fzx::_kv_get "$FZX_SESSIONS_DIR/$sid/meta/module" module || { printf 'bell'; return 0; }
  fzx::_kv_get "$FZX_SESSIONS_DIR/$sid/state/mode" mode || :
  [[ -s "$FZX_SESSIONS_DIR/$sid/meta/args" ]] && mapfile -d '' -t args < "$FZX_SESSIONS_DIR/$sid/meta/args"
  out="$(fzx::nav goto "$module${mode:+:$mode}" "${args[@]}")" || return
  child="${out##*--resume }"
  child="${child%% *}"
  if [[ -d "$FZX_SESSIONS_DIR/$child/state" ]]; then
    for f in query toggles sort; do
      if [[ -f "$FZX_SESSIONS_DIR/$sid/state/$f" ]]; then
        cp -- "$FZX_SESSIONS_DIR/$sid/state/$f" "$FZX_SESSIONS_DIR/$child/state/$f"
      else
        rm -f -- "$FZX_SESSIONS_DIR/$child/state/$f"
      fi
    done
    rm -f -- "$FZX_SESSIONS_DIR/$child/state/pos"
  fi
  fzx::log info "sessions: copy of $sid ($st) as $child"
  printf '%s' "$out"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" sessions
  sessions::action "$@"
}
