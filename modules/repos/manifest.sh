#!/usr/bin/env bash
# repos menu entries

repos::manifest() {
  fzx::entry repos "Git repositories"
  fzx::entry repos:changed "Repositories with uncommitted changes"
}

repos::applicable() { command -v ghq > /dev/null || ((${#FZX_REPOS_ROOTS[@]})); }

# from the last scan; the module refreshes it
repos::summary() {
  local cache="${FZX_CACHE_DIR}/repos/status"
  [[ -f "$cache" ]] || return 0
  case "$1" in
    repos) awk -F'\t' "$FZX_AWK_PLURAL"'{ n++; if ($3 > 0) c++; if ($4 > 0 || $5 > 0) u++ } END { printf "%s, %d changed, %d unsynced\n", plural(n, "repository", "repositories"), c, u }' "$cache" ;;
    repos:changed) awk -F'\t' '$3 > 0 { c++ } END { printf "%d changed\n", c }' "$cache" ;;
  esac
}
