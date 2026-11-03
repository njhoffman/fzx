#!/usr/bin/env bash
# browser actions: open URLs in the browser and profile they came from (detached, so they outlive fzx),
# open them with xdg-open, copy the titles

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# browser::_firefox_cmd <profile directory name>: BROWSER_CMD, the Firefox that owns the profile:
# FZX_BROWSER_FIREFOX_CMD when set, Developer Edition's for dev-edition-* profiles, else firefox
browser::_firefox_cmd() {
  local c
  BROWSER_CMD=""
  if [[ -n "${FZX_BROWSER_FIREFOX_CMD:-}" ]]; then
    BROWSER_CMD="$FZX_BROWSER_FIREFOX_CMD"
    return 0
  fi
  if [[ "$1" == *dev-edition* ]]; then
    for c in firefox-devedition firefox-developer-edition /usr/lib/firefox-devedition/firefox \
      /opt/firefox-developer-edition/firefox; do
      if [[ "$c" == /* && -x "$c" ]] || { [[ "$c" != /* ]] && command -v "$c" > /dev/null; }; then
        BROWSER_CMD="$c"
        return 0
      fi
    done
  fi
  command -v firefox > /dev/null && BROWSER_CMD=firefox
  return 0
}

# browser::_spawn <command> <args...>: run detached from fzx and its terminal
browser::_spawn() {
  command setsid -f "$@" > /dev/null 2>&1 < /dev/null
}

# browser::open <src<TAB>url...>: each profile's URLs in one call to its browser
browser::open() {
  local item src url name prof rc=0 cmd
  local -A urls=()
  local -a order=()
  for item; do
    [[ "$item" == *$'\t'* ]] || continue
    src="${item%%$'\t'*}" url="${item#*$'\t'}"
    [[ -n "$url" ]] || continue
    [[ -n "${urls[$src]+x}" ]] || order+=("$src")
    urls[$src]+="$url"$'\n'
  done
  for src in "${order[@]}"; do
    name="${src%%:*}" prof="${src#*:}"
    mapfile -t list <<< "${urls[$src]%$'\n'}"
    if [[ "$name" == firefox ]]; then
      browser::_firefox_cmd "$prof"
      if [[ -z "$BROWSER_CMD" ]]; then
        printf 'browser: no firefox to open %s with\n' "$prof" >&2
        rc=1
        continue
      fi
      browser::_spawn "$BROWSER_CMD" --profile "${FZX_BROWSER_FIREFOX_DIR:-$HOME/.mozilla/firefox}/$prof" "${list[@]}" || rc=1
    else
      cmd="${FZX_BROWSER_CHROMIUM_CMDS[$name]:-}"
      if [[ -z "$cmd" ]] || ! command -v "$cmd" > /dev/null; then
        printf 'browser: %s not found (FZX_BROWSER_CHROMIUM_CMDS[%s])\n' "${cmd:-a command}" "$name" >&2
        rc=1
        continue
      fi
      browser::_spawn "$cmd" "--profile-directory=$prof" "${list[@]}" || rc=1
    fi
  done
  return "$rc"
}

# browser::action <action> <args...>
browser::action() {
  local action="${1:-}" a rc=0 out=()
  shift
  case "$action" in
    open | open-stay) browser::open "$@" ;;
    xdg)
      for a; do [[ -n "$a" ]] && { browser::_spawn xdg-open "$a" || rc=1; }; done
      return "$rc"
      ;;
    copy-title)
      fzx::require builtin
      for a; do [[ -n "$a" ]] && out+=("$a"); done
      ((${#out[@]})) || return 0
      printf '%s\n' "${out[@]}" | fzx::clip
      ;;
    *)
      printf 'browser: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" browser
  browser::action "$@"
}
