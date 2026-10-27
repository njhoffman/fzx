#!/usr/bin/env bash
# github preview, by the row's kind (see source.sh): a repository's details and README, a code hit's matching
# fragments and then the whole file with the matching lines marked, a tree file's contents or a tree
# directory's entries, and for a recent search what enter does and the search rate limits left.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# github::show <file> <path>: a file's contents, highlighted for its name (bat), within the preview width
github::show() {
  if command -v bat > /dev/null; then
    command bat --color=always --style=numbers --paging=never --terminal-width="${FZF_PREVIEW_COLUMNS:-80}" \
      --file-name="$2" "${@:3}" -- "$1"
  else
    command cat -- "$1"
  fi
}

# github::markdown <file>: a README, rendered (FZX_GITHUB_MARKDOWN: auto, glow, bat or cat)
github::markdown() {
  local how="${FZX_GITHUB_MARKDOWN:-auto}"
  [[ "$how" == auto ]] && { command -v glow > /dev/null && how=glow || how=bat; }
  case "$how" in
    glow) command glow -s dark -w "${FZF_PREVIEW_COLUMNS:-80}" -- "$1" ;;
    bat) github::show "$1" README.md ;;
    *) command cat -- "$1" ;;
  esac
}

# github::limits: the search rate limits left (the rate_limit endpoint itself is free)
github::limits() {
  command gh api rate_limit --jq '.resources |
    "searches left: \(.search.remaining)/\(.search.limit), code \(.code_search.remaining)/\(.code_search.limit) (per minute)"' 2> /dev/null
}

# github::preview_repo <search file> <index>
github::preview_repo() {
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' repo pushed readme
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  command jq -r --argjson i "$2" --arg b "$b" --arg d "$d" --arg r "$r" '.[$i] |
    def row(k; v): if (v // "") == "" then empty else "\($d)\(k)\($r)  \(v)" end;
    "\($b)\(.fullName)\($r)\(if .isArchived then "  \($d)archived\($r)" else "" end)\(if .isFork then "  \($d)fork\($r)" else "" end)",
    (.description // ""), "",
    row("language  "; .language),
    row("stars     "; .stargazersCount), row("forks     "; .forksCount), row("issues    "; .openIssuesCount),
    row("license   "; .license.name), row("homepage  "; .homepage), row("branch    "; .defaultBranch),
    row("created   "; .createdAt[0:10]), row("pushed    "; .pushedAt[0:10]), row("url       "; .url)' -- "$1"
  IFS=$'\t' read -r repo pushed < <(command jq -r --argjson i "$2" '.[$i] | [.fullName, .pushedAt] | join("\t")' -- "$1")
  # the README of that push: a newer push gets a new copy
  readme="$FZX_CACHE_DIR/github/readme/${repo/\//__}@${pushed//[^0-9]/}"
  if github::cached "$readme" github::api "repos/$repo/readme" > /dev/null 2>&1; then
    printf '\n'
    github::markdown "$readme"
  else
    printf '\n%sno README%s\n' "$d" "$r"
  fi
}

# github::preview_code <search file> <index>: the fragments GitHub matched, the matches highlighted, then the
# file itself with every line holding a match marked
github::preview_code() {
  local hl=$'\e['"${FZX_COLORS[github_match]:-1;38;5;16;48;5;220}m" b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  local repo path sha blob lines=() n
  [[ -n "${NO_COLOR+x}" ]] && hl="" b="" d="" r=""
  IFS=$'\t' read -r repo path sha < <(command jq -r --argjson i "$2" '.[$i] | [.repository.nameWithOwner, .path, .sha] | join("\t")' -- "$1")
  printf '%s%s%s  %s\n' "$b" "$repo" "$r" "$path"
  # jq slices strings by code point, as GitHub's match indices count
  command jq -r --argjson i "$2" --arg hl "$hl" --arg r "$r" --arg d "$d" '.[$i].textMatches[]? |
    (.matches | sort_by(.indices[0]) | reverse) as $m |
    reduce $m[] as $x (.fragment; .[0:$x.indices[0]] + $hl + .[$x.indices[0]:$x.indices[1]] + $r + .[$x.indices[1]:]) |
    "\($d)────\($r)", .' -- "$1"
  github::blob "$repo" "$sha" blob 2> /dev/null || return 0
  # the matching lines, by the matched texts (at most 50 marks)
  mapfile -t lines < <(command jq -r --argjson i "$2" '[.[$i].textMatches[]?.matches[]?.text] | unique | .[]' -- "$1" |
    grep -v '^$' | grep -n -F -f - -- "$blob" | cut -d: -f1 | head -50)
  printf '\n%s──── %s%s\n' "$d" "$path" "$r"
  local marks=()
  for n in "${lines[@]}"; do marks+=(--highlight-line "$n"); done
  github::show "$blob" "$path" "${marks[@]}"
}

# github::preview_blob <owner/name> <sha:size> <path>
github::preview_blob() {
  local sha="${2%%:*}" size="${2#*:}" blob d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && d="" r=""
  if [[ "$size" =~ ^[0-9]+$ ]] && ((size > ${FZX_GITHUB_PREVIEW_MAX:-1000000})); then
    printf '%s%s: %s bytes, not previewed (FZX_GITHUB_PREVIEW_MAX)%s\n' "$d" "$3" "$size" "$r"
    return 0
  fi
  github::blob "$1" "$sha" blob || { printf 'github: cannot read %s\n' "$3"; return 0; }
  if grep -qI . -- "$blob" || [[ ! -s "$blob" ]]; then
    github::show "$blob" "$3"
  else
    printf '%s%s: binary, %s bytes%s\n' "$d" "$3" "$(stat -c %s -- "$blob")" "$r"
  fi
}

# github::preview_tree <url> <owner/name> <path>: the directory's entries, from the cached tree
github::preview_tree() {
  local sha file d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && d="" r=""
  sha="${1#*/tree/}" sha="${sha%%/*}"
  file="$FZX_CACHE_DIR/github/tree/${2/\//__}@$sha.json"
  [[ -f "$file" ]] || return 0
  printf '%s/\n\n' "$3"
  command jq -r --arg p "$3/" --arg d "$d" --arg r "$r" '.tree[] | select((.path | startswith($p)) and (.path[($p | length):] | contains("/") | not)) |
    if .type == "tree" then "\(.path[($p | length):])/" else "\(.path[($p | length):])  \($d)\(.size) bytes\($r)" end' -- "$file"
}

# github::preview <url|query|text> <kind> [repo] [field 4] [field 5]
github::preview() {
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' file
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  case "${2:-}" in
    repo) github::preview_repo "$4" "$5" ;;
    code) github::preview_code "$4" "$5" ;;
    blob) github::preview_blob "$3" "$4" "$5" ;;
    tree) github::preview_tree "$1" "$3" "$5" ;;
    search)
      printf '%senter%s searches %s again for %s%s%s\n' "$b" "$r" "$3" "$b" "$1" "$r"
      github::search_file "$3" "$1" file
      [[ -f "$file" ]] && printf '%s%s cached results%s\n' "$d" "$(command jq length -- "$file")" "$r"
      printf '\n%s%s%s\n' "$d" "$(github::limits)" "$r"
      ;;
    error) printf '%s\n\n%s%s%s\n' "$1" "$d" "$(github::limits)" "$r" ;;
    *) return 0 ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" github
  github::preview "$@"
}
