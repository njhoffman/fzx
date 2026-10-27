#!/usr/bin/env bash
# repos source: git repositories (ghq's, plus any under FZX_REPOS_ROOTS) as "path<TAB>display", with the
# state from the last scan ($FZX_CACHE_DIR/repos/status): branch, changed files, commits ahead/behind the
# upstream, open TODO.md items and the age of the last commit. The scan runs in the background
# (repos::refresh, bound to start), so the list shows at once; a repository not scanned yet shows blank.
# Modes: all, mine (owner in FZX_REPOS_OWNERS), changed, unsynced (ahead or behind), todos (open items).
# Sort: recent (last commit, newest first) or name.

repos::cache_file() { printf '%s/repos/status' "$FZX_CACHE_DIR"; }

# repos::list: repository paths, one per line, resolved and deduplicated (~/git links into ghq collapse)
repos::list() {
  local root
  {
    command -v ghq > /dev/null && command ghq list -p 2> /dev/null
    for root in "${FZX_REPOS_ROOTS[@]}"; do
      [[ -d "$root" ]] || continue
      find -L "$root" -mindepth 2 -maxdepth "$((${FZX_REPOS_DEPTH:-3} + 1))" -name .git -prune -printf '%h\n' 2> /dev/null
    done
  } | xargs -r -d '\n' realpath -e -- 2> /dev/null | awk '!seen[$0]++'
}

# repos::scan <dir>: "dir<TAB>branch<TAB>changed<TAB>ahead<TAB>behind<TAB>last commit epoch<TAB>open todos"
repos::scan() {
  local dir="$1" status last todos=""
  status="$(timeout "${FZX_REPOS_TIMEOUT:-10}" git -C "$dir" status --porcelain=v2 --branch 2> /dev/null)"
  last="$(git -C "$dir" log -1 --format=%ct 2> /dev/null)"
  [[ -f "$dir/TODO.md" ]] && todos="$(grep -c '^- \[ \]' "$dir/TODO.md")"
  awk -v dir="$dir" -v last="$last" -v todos="$todos" '
    /^# branch\.head / { branch = $3 }
    /^# branch\.ab / { ahead = substr($3, 2); behind = substr($4, 2) }
    /^[^#]/ { changed++ }
    END { printf "%s\t%s\t%d\t%s\t%s\t%s\t%s\n", dir, branch, changed, ahead, behind, last, todos }' <<< "$status"
}

# repos::scan_all [dir...]: scan the given repositories (default: all) in parallel, FZX_REPOS_JOBS at a time
repos::scan_all() {
  local self
  self="$(readlink -f "${BASH_SOURCE[0]}")"
  if (($#)); then printf '%s\n' "$@"; else repos::list; fi |
    xargs -r -d '\n' -P "${FZX_REPOS_JOBS:-8}" -n 1 nice "$self" --scan
}

# repos::owners: FZX_REPOS_OWNERS, else the GitHub user from local configuration (no network)
repos::owners() {
  local user
  if ((${#FZX_REPOS_OWNERS[@]})); then
    printf '%s' "${FZX_REPOS_OWNERS[*]}"
    return
  fi
  user="$(git config --global github.user 2> /dev/null || git config --global ghq.user 2> /dev/null)" ||
    user="$(awk '$1 == "user:" { print $2; exit }' "${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml" 2> /dev/null)"
  printf '%s' "${user:-$(id -un)}"
}

repos::source() {
  local cache owners=""
  cache="$(repos::cache_file)"
  [[ -f "$cache" ]] || cache=/dev/null
  [[ "${FZX_MODE:-all}" == mine ]] && owners="$(repos::owners)"
  repos::list | awk -F'\t' -v OFS='\t' -v cache="$cache" -v mode="${FZX_MODE:-all}" -v sort="${FZX_SORT:-recent}" \
    -v owners=" $owners " -v ghq="${FZX_REPOS_GHQ_ROOT:-$(command ghq root 2> /dev/null)}/" -v home="$HOME/" \
    -v now="$(date +%s)" -v c_name=$'\e['"${FZX_COLORS[repos_name]:-1;38;5;111}m" \
    -v c_dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" -v c_branch=$'\e['"${FZX_COLORS[repos_branch]:-38;5;81}m" \
    -v c_changed=$'\e['"${FZX_COLORS[repos_changed]:-38;5;255}m" -v c_ahead=$'\e['"${FZX_COLORS[repos_ahead]:-38;5;114}m" \
    -v c_behind=$'\e['"${FZX_COLORS[repos_behind]:-38;5;203}m" -v c_todo=$'\e['"${FZX_COLORS[repos_todo]:-38;5;117}m" \
    -v rst=$'\e[0m' '
    function age(t,   s) {
      if (t == "") return ""
      s = now - t
      if (s < 3600) return int(s / 60) "m"
      if (s < 86400) return int(s / 3600) "h"
      if (s < 86400 * 14) return int(s / 86400) "d"
      if (s < 86400 * 60) return int(s / 604800) "w"
      if (s < 86400 * 365) return int(s / 2592000) "mo"
      return int(s / 31536000) "y"
    }
    # the cache (it may be empty, so not NR == FNR), then the repository list on stdin
    FILENAME == cache { state[$1] = $0; next }
    {
      dir = $0; split(state[dir], f, "\t")
      branch = f[2]; changed = f[3] + 0; ahead = f[4] + 0; behind = f[5] + 0; last = f[6]; todos = f[7] + 0
      # owner/name under ghq (host shown when it is not github.com), else the path under ~
      if (index(dir, ghq) == 1) {
        rel = substr(dir, length(ghq) + 1); n = split(rel, p, "/")
        owner = p[n - 1]; name = p[n]; prefix = (p[1] == "github.com" ? "" : p[1] "/") owner "/"
      } else {
        rel = (index(dir, home) == 1) ? "~/" substr(dir, length(home) + 1) : dir
        n = split(rel, p, "/"); owner = ""; name = p[n]; prefix = substr(rel, 1, length(rel) - length(name))
      }
      if (mode == "mine" && index(owners, " " owner " ") == 0) next
      if (mode == "changed" && changed == 0) next
      if (mode == "unsynced" && ahead == 0 && behind == 0) next
      if (mode == "todos" && todos == 0) next
      flags = (changed ? c_changed "●" changed rst " " : "") (ahead ? c_ahead "↑" ahead rst " " : "") \
        (behind ? c_behind "↓" behind rst " " : "") (todos ? c_todo "☐" todos rst " " : "")
      shown = prefix name; pad = 44 - length(shown); if (pad < 1) pad = 1
      bpad = 20 - length(branch); if (bpad < 1) bpad = 1
      line = dir "\t" c_dim prefix rst c_name name rst sprintf("%" pad "s", "") c_branch branch rst \
        sprintf("%" bpad "s", "") c_dim sprintf("%4s", age(last)) rst "  " flags
      key = (sort == "name") ? tolower(prefix name) : sprintf("%012d", 999999999999 - (last == "" ? 0 : last))
      print key "\t" line
    }' "$cache" - | sort -t $'\t' -k1,1 | cut -f2-
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  if [[ "${1:-}" == --scan ]]; then
    repos::scan "$2"
    exit
  fi
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" repos
  repos::source "$@"
}
