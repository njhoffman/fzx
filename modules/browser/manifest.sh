#!/usr/bin/env bash
# browser menu entries, where a Chromium-family or Firefox profile exists

browser::manifest() {
  fzx::entry browser "Browser history (Chrome, Firefox)"
  fzx::entry browser:bookmarks "Browser bookmarks"
}

# browser::_dirs: the profile parents that exist (Chromium-family config directories, Firefox's)
browser::_dirs() {
  local d
  for d in "${FZX_BROWSER_CHROMIUM_DIRS[@]}" "${FZX_BROWSER_FIREFOX_DIR:-$HOME/.mozilla/firefox}"; do
    [[ -d "$d" ]] && printf '%s\n' "$d"
  done
  return 0
}

browser::applicable() {
  [[ -n "$(browser::_dirs)" ]]
}

# browser::summary <target>: the browsers found (bookmark and history counts would need the databases read)
browser::summary() {
  local d names=()
  while IFS= read -r d; do
    case "$d" in
      */google-chrome) names+=(chrome) ;;
      */firefox) names+=(firefox) ;;
      *) names+=("${d##*/}") ;;
    esac
  done < <(browser::_dirs)
  local IFS=,
  printf '%s\n' "${names[*]}" | sed 's/,/, /g'
}
