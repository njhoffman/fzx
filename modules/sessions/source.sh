#!/usr/bin/env bash
# sessions source: every fzx session tree but the one this list runs in, newest first, each root followed by
# its screens depth first. Lines are "sid<TAB>sid<TAB>display". A tree is kept (--keep: it survives its
# owner, enter resumes it), live (its owner runs, in another terminal: enter opens a copy) or dead (gc has
# not swept it yet: a copy too).

# sessions::_state <root dir> <var>: kept, live or dead
sessions::_state() {
  local _keep=""
  fzx::_kv_get "$1/meta/keep" _keep || :
  if fzx::owner_alive "$1"; then printf -v "$2" live
  elif [[ "$_keep" == 1 ]]; then printf -v "$2" kept
  else printf -v "$2" dead; fi
}

# sessions::_ago <ms> <now ms> <var>: "12s", "5m", "3h", "2d"
sessions::_ago() {
  local _s=$((($2 - $1) / 1000)) _o
  if ((_s < 60)); then _o="${_s}s"
  elif ((_s < 3600)); then _o="$((_s / 60))m"
  elif ((_s < 86400)); then _o="$((_s / 3600))h"
  else _o="$((_s / 86400))d"; fi
  printf -v "$3" '%s' "$_o"
}

# sessions::_tree: "sid<TAB>depth" for every session: the roots newest first, each followed by its
# screens depth first (children by start)
sessions::_tree() {
  local dir sid root parent started
  declare -A start=() par=() rt=()
  for dir in "$FZX_SESSIONS_DIR"/*/; do
    dir="${dir%/}"
    [[ -d "$dir/meta" ]] || continue
    sid="${dir##*/}"
    root="$sid" parent="" started=0
    fzx::_kv_get "$dir/meta/root" root || :
    fzx::_kv_get "$dir/meta/parent" parent || :
    fzx::_kv_get "$dir/meta/started_ms" started || :
    start[$sid]="$started" par[$sid]="$parent" rt[$sid]="$root"
  done
  # depth first: a parent's line, then its children by start
  local -A kids=()
  for sid in "${!par[@]}"; do
    [[ -n "${par[$sid]}" ]] && kids[${par[$sid]}]+="${start[$sid]} $sid"$'\n'
  done
  sessions::_walk() {
    local s="$1" d="$2" k
    printf '%s\t%s\n' "$s" "$d"
    while read -r _ k; do
      [[ -n "$k" ]] && sessions::_walk "$k" $((d + 1))
    done < <(printf '%s' "${kids[$s]:-}" | sort -n)
  }
  for sid in "${!par[@]}"; do
    [[ -z "${par[$sid]}" && "${rt[$sid]}" == "$sid" ]] && printf '%s %s\n' "${start[$sid]}" "$sid"
  done | sort -rn | while read -r _ sid; do sessions::_walk "$sid" 0; done
}

sessions::source() {
  local own="" sid depth dir root rstate=dead mode module query cwd label args now current started
  local k=$'\e['"${FZX_COLORS[sessions_kept]:-38;5;114}m" l=$'\e['"${FZX_COLORS[sessions_live]:-38;5;75}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" b=$'\e[1m' r=$'\e[0m' c
  [[ -n "${NO_COLOR:+x}" ]] && k="" l="" d="" b="" r=""
  fzx::require session
  # this list's own tree is left out: resuming it would be the screen already on
  if [[ -n "${FZX_SESSION:-}" && -d "$FZX_SESSIONS_DIR/$FZX_SESSION/meta" ]]; then
    own="$FZX_SESSION"
    fzx::_kv_get "$FZX_SESSIONS_DIR/$FZX_SESSION/meta/root" own || :
  fi
  fzx::now_ms now
  while IFS=$'\t' read -r sid depth; do
    dir="$FZX_SESSIONS_DIR/$sid"
    root="$sid"
    fzx::_kv_get "$dir/meta/root" root || :
    [[ -n "$own" && "$root" == "$own" ]] && continue
    if ((depth == 0)); then sessions::_state "$dir" rstate; fi
    module="" mode="" query="" cwd="" started=0 current=""
    fzx::_kv_get "$dir/meta/module" module || :
    fzx::_kv_get "$dir/state/mode" mode || :
    fzx::_kv_get "$dir/state/query" query || :
    fzx::_kv_get "$dir/meta/cwd" cwd || :
    fzx::_kv_get "$dir/meta/started_ms" started || :
    fzx::_kv_get "$FZX_SESSIONS_DIR/$root/state/current" current || :
    args=()
    [[ -s "$dir/meta/args" ]] && mapfile -d '' -t args < "$dir/meta/args"
    sessions::_ago "${started:-0}" "$now" label
    case "$rstate" in kept) c="$k" ;; live) c="$l" ;; *) c="$d" ;; esac
    printf '%s\t%s\t' "$sid" "$sid"
    if ((depth == 0)); then
      printf '%s%-4s%s  ' "$c" "$rstate" "$r"
    else
      printf '%*s%s└%s ' $((4 + 2 * (depth - 1))) "" "$d" "$r"
    fi
    printf '%s%-22s%s' "$([[ "$current" == "$sid" ]] && printf '%s' "$b")" "$module${mode:+:$mode}" "$r"
    printf '  %s%4s%s' "$d" "$label" "$r"
    printf '  %-24s' "${cwd/#$HOME/\~}"
    ((${#args[@]})) && printf '  %s' "${args[*]}"
    [[ -n "$query" ]] && printf '  %sq:%s %s' "$d" "$r" "$query"
    printf '\n'
  done < <(sessions::_tree)
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" sessions
  sessions::source "$@"
}
