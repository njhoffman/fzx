#!/usr/bin/env bash
# repos actions on repository paths, and the background scan (repos::transform refresh)

[[ -n "${_FZX_CORE_LOADED:-}" ]] || source "${FZX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/core.sh"
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# repos::lock / repos::unlock: one scan at a time (a lock older than 10 minutes is a dead scan's)
repos::lock() {
  local lock="${1%/*}/scan.lock"
  mkdir -p -- "${1%/*}"
  if [[ -d "$lock" ]] && (($(date +%s) - $(stat -c %Y "$lock") > 600)); then rmdir -- "$lock" 2> /dev/null; fi
  mkdir -- "$lock" 2> /dev/null
}
repos::unlock() { rmdir -- "${1%/*}/scan.lock" 2> /dev/null || :; }

# repos::refresh [force]: scan every repository into the cache unless it is younger than FZX_REPOS_TTL;
# true when the cache changed
repos::refresh() {
  local cache tmp
  cache="$(repos::cache_file)"
  if [[ "${1:-}" != force && -f "$cache" ]] && (($(date +%s) - $(stat -c %Y "$cache") < ${FZX_REPOS_TTL:-120})); then
    return 1
  fi
  repos::lock "$cache" || return 1
  tmp="$cache.$BASHPID"
  repos::scan_all | sort > "$tmp"
  repos::unlock "$cache"
  if [[ -f "$cache" ]] && cmp -s -- "$tmp" "$cache"; then
    rm -f -- "$tmp"
    touch -- "$cache"
    return 1
  fi
  mv -f -- "$tmp" "$cache"
}

# repos::rescan <dir...>: scan only these repositories and replace their rows in the cache
repos::rescan() {
  local cache tmp
  cache="$(repos::cache_file)"
  repos::lock "$cache" || return 0
  tmp="$cache.$BASHPID"
  { repos::scan_all "$@"; [[ -f "$cache" ]] && cat -- "$cache"; } |
    awk -F'\t' '!seen[$1]++' | sort > "$tmp"
  mv -f -- "$tmp" "$cache"
  repos::unlock "$cache"
}

# repos::url <dir>: the origin remote as a web address
repos::url() {
  local url
  url="$(git -C "$1" remote get-url origin 2> /dev/null)" || return 1
  url="${url%.git}"
  case "$url" in
    git@*:*)
      url="${url#git@}"
      url="https://${url/://}"
      ;;
    ssh://git@*) url="https://${url#ssh://git@}" ;;
  esac
  printf '%s\n' "$url"
}

# repos::wait: keep output on screen until a key (foreground actions return to fzf at once)
repos::wait() {
  [[ -t 1 ]] || return 0
  printf '\n\e[2m(press a key)\e[0m'
  read -rsn1 < /dev/tty || :
}

# repos::transform refresh: bound as start:+bg-transform; a reload when the scan changed the cache
repos::transform() {
  case "${1:-}" in
    refresh)
      # fzx::cb lives in lib/opts.sh, which a callback does not load by itself
      fzx::require opts
      repos::refresh && printf 'reload:%s' "$(fzx::cb source)"
      ;;
    *)
      printf 'repos: unknown transform: %s\n' "${1:-}" >&2
      return 2
      ;;
  esac
  return 0
}

# repos::action <edit|fetch|pull|browse|rescan> <dir...>
repos::action() {
  local action="${1:-}" dir failed=0 url
  shift
  for dir in "$@"; do
    [[ -d "$dir/.git" || -f "$dir/.git" ]] || { printf 'repos: not a repository: %s\n' "$dir" >&2; return 2; }
  done
  case "$action" in
    edit)
      [[ -n "${1:-}" ]] || return 0
      (cd -- "$1" && ${EDITOR:-nvim} .)
      ;;
    fetch)
      local out
      # stdout: the action's stderr goes to fzx's log
      # shellcheck disable=SC2016  # $1 is expanded by the sh -c script
      out="$(printf '%s\n' "$@" | xargs -r -d '\n' -P "${FZX_REPOS_JOBS:-8}" -I{} sh -c \
        'if git -C "$1" fetch --all --prune --quiet 2>&1; then printf "\033[32mfetched\033[0m %s\n" "$1"; else printf "\033[31mfailed\033[0m  %s\n" "$1"; fi' _ {})"
      printf '%s\n' "$out"
      [[ "$out" == *failed* ]] && failed=1
      repos::rescan "$@"
      ((failed)) && repos::wait
      return 0
      ;;
    pull)
      for dir in "$@"; do
        printf '\e[1m%s\e[0m\n' "${dir/#$HOME/\~}"
        git -C "$dir" pull --ff-only || failed=1
      done
      repos::rescan "$@"
      repos::wait
      return "$failed"
      ;;
    browse)
      for dir in "$@"; do
        url="$(repos::url "$dir")" || { printf 'repos: no origin remote: %s\n' "$dir" >&2; continue; }
        xdg-open "$url" > /dev/null 2>&1 &
      done
      ;;
    rescan)
      printf 'scanning every repository...\n'
      repos::refresh force || :
      ;;
    *)
      printf 'repos: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" repos
  repos::action "$@"
}
