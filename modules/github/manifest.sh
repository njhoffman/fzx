#!/usr/bin/env bash
# github menu entries, where gh is installed and logged in (checked without a request)

github::manifest() {
  fzx::entry github "Search GitHub repositories"
  fzx::entry github:code "Search code on GitHub"
}

github::applicable() {
  command -v gh > /dev/null && command -v jq > /dev/null && command gh auth token > /dev/null 2>&1
}

# the searches left this minute (the rate_limit endpoint does not count against them)
github::summary() {
  local key=search
  [[ "$1" == github:code ]] && key=code_search
  command gh api rate_limit --jq ".resources.$key | \"\(.remaining)/\(.limit) searches left this minute\""
}
