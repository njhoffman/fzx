#!/usr/bin/env bash
# github menu entries, where gh is installed and logged in (checked without a request)

github::manifest() {
  fzx::entry github "Search GitHub repositories"
  fzx::entry github:code "Search code on GitHub"
  fzx::entry github:mine "Your GitHub repositories"
  fzx::entry github:starred "GitHub repositories you starred"
}

# once per menu listing, not once per entry: the token comes from the keyring (about 100ms)
github::applicable() {
  if [[ -z "${_GITHUB_OK:-}" ]]; then
    command -v gh > /dev/null && command -v jq > /dev/null && command gh auth token > /dev/null 2>&1
    _GITHUB_OK=$?
  fi
  return "$_GITHUB_OK"
}

# github::summary <target>: repos: GitHub's status when it is not fine, this repository's open PRs and
# issues (in a GitHub repository), unread notifications and the searches left; code: the code searches
# left; mine and starred: how many. The repos parts are asked in parallel, each in its own file.
github::summary() {
  local tmp n
  case "$1" in
    github)
      tmp="$(mktemp -d)" || return
      command curl -fsS -m 2 https://www.githubstatus.com/api/v2/status.json 2> /dev/null |
        command jq -r 'select(.status.indicator != "none") | "GitHub: \(.status.description)"' > "$tmp/1" &
      command gh repo view --json pullRequests,issues \
        --jq '"here: \(.pullRequests.totalCount) PRs, \(.issues.totalCount) issues"' > "$tmp/2" 2> /dev/null &
      command gh api 'notifications?per_page=50' --jq 'length | if . == 50 then "50+ unread" elif . > 0 then "\(.) unread" else empty end' \
        > "$tmp/3" 2> /dev/null &
      command gh api rate_limit --jq '.resources.search | "\(.remaining)/\(.limit) searches"' > "$tmp/4" 2> /dev/null &
      wait
      cat -- "$tmp"/[1-4] | paste -sd '|' | sed 's/|/ · /g'
      rm -rf -- "$tmp"
      ;;
    github:code)
      command gh api rate_limit --jq '.resources.code_search | "\(.remaining)/\(.limit) code searches left this minute"'
      ;;
    github:mine)
      # the last list when there is one: /user counts private repositories only for tokens with that scope
      if [[ -f "$FZX_CACHE_DIR/github/list/mine.json" ]]; then
        command jq -r '"\(length) repositories, \([.[] | select(.isPrivate)] | length) private"' -- "$FZX_CACHE_DIR/github/list/mine.json"
      else
        command gh api user --jq '"\(.public_repos) public repositories"'
      fi
      ;;
    github:starred)
      # one star per page: the last page's number is the count
      n="$(command gh api -i 'user/starred?per_page=1' 2> /dev/null | sed -n 's/^[Ll]ink:.*[?&]page=\([0-9]*\)>; rel="last".*/\1/p')"
      printf '%s stars\n' "${n:-0}"
      ;;
  esac
}
