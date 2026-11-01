#!/usr/bin/env bash
# github preview, by the row's kind (see source.sh): a repository's details and README, a code hit's matching
# fragments and then the whole file with the matching lines marked, a tree file's contents or a tree
# directory's entries, and for a recent search what enter does and the search rate limits left.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# shellcheck source=../../lib/render.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/render.sh"

# github::show <file> <path> [--mark N]...: a file's contents, highlighted for its name, line numbers on
github::show() { fzx::render_text --name "$2" --style numbers "${@:3}" -- "$1"; }

# github::markdown <file>: a README, issue or pull request body, rendered (lib/render.sh)
github::markdown() { fzx::render_markdown -- "$1"; }

# github::limits: the search rate limits left (the rate_limit endpoint itself is free)
github::limits() {
  command gh api rate_limit --jq '.resources |
    "searches left: \(.search.remaining)/\(.search.limit), code \(.code_search.remaining)/\(.code_search.limit) (per minute)"' 2> /dev/null
}

# github::preview_repo <search file> <index>
github::preview_repo() {
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' repo pushed readme emojis
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  github::emojis emojis
  command jq -r --argjson i "$2" --arg b "$b" --arg d "$d" --arg r "$r" --argjson e "$emojis" '.[$i] |
    def row(k; v): if (v // "") == "" then empty else "\($d)\(k)\($r)  \(v)" end;
    "\($b)\(.fullName)\($r)\(if .isArchived then "  \($d)archived\($r)" else "" end)\(if .isFork then "  \($d)fork\($r)" else "" end)",
    ((.description // "") | gsub(":(?<n>[a-z0-9_+-]+):"; $e[.n] // ":\(.n):")), "",
    row("language  "; .language),
    row("stars     "; .stargazersCount), row("forks     "; .forksCount), row("issues    "; .openIssuesCount),
    row("visibility"; .visibility), row("license   "; .license.name), row("homepage  "; .homepage), row("branch    "; .defaultBranch),
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
  for n in "${lines[@]}"; do marks+=(--mark "$n"); done
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

# github::preview_issue <list file> <index>: from the list, the state, title, author, labels and dates; then
# github::item_details
github::preview_issue() {
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  local g=$'\e['"${FZX_COLORS[github_open]:-38;5;114}m" red=$'\e['"${FZX_COLORS[github_closed]:-38;5;203}m"
  local m=$'\e['"${FZX_COLORS[github_merged]:-38;5;141}m"
  local url repo num updated
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r="" g="" red="" m=""
  IFS=$'\t' read -r url repo num updated < <(command jq -r --argjson i "$2" '.[$i] | [.url, .repo, .number, .updatedAt] | @tsv' -- "$1")
  [[ -n "$url" ]] || return 0
  command jq -r --argjson i "$2" --arg b "$b" --arg d "$d" --arg r "$r" --arg g "$g" --arg red "$red" --arg m "$m" '.[$i] |
    (if .state == "MERGED" then $m + "merged" elif .state == "CLOSED" then $red + "closed" elif .draft then $d + "draft"
     else $g + "open" end) as $s |
    "\($b)\(.repo) #\(.number)\($r)  \($s)\($r)", "\($b)\(.title)\($r)", "",
    "\($d)author \($r) \(.author // "ghost")", "\($d)updated\($r) \(.updatedAt[0:16] | sub("T"; " "))",
    (if (.labels | length) > 0 then "\($d)labels \($r) \(.labels | map(.name) | join(", "))" else empty end)' -- "$1"
  github::item_details "$url" "$repo" "$num" "$updated"
}

# github::item_details <url> <owner/name> <number> <updated>: a pull request's branches, size, review and
# checks, then the body and comments as markdown. Cached by the last update, so a new comment fetches them
# again
github::item_details() {
  local url="$1" repo="$2" num="$3" updated="$4" kind fields view md tmp
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' y=$'\e[33m'
  local g=$'\e['"${FZX_COLORS[github_open]:-38;5;114}m" red=$'\e['"${FZX_COLORS[github_closed]:-38;5;203}m"
  [[ -n "${NO_COLOR+x}" ]] && d="" r="" y="" g="" red=""
  kind=issue fields=body,comments
  if [[ "$url" == */pull/* ]]; then
    kind=pr fields+=,headRefName,baseRefName,changedFiles,additions,deletions,reviewDecision,statusCheckRollup
  fi
  view="$FZX_CACHE_DIR/github/view/${repo/\//__}-$num@${updated//[^0-9]/}.json"
  if ! github::cached "$view" command gh "$kind" view "$url" --json "$fields" > /dev/null 2>&1; then
    printf '\n%scannot read %s%s\n' "$d" "$url" "$r"
    return 0
  fi
  if [[ "$kind" == pr ]]; then
    command jq -r --arg d "$d" --arg r "$r" --arg g "$g" --arg red "$red" --arg y "$y" '
      "\($d)branch \($r) \(.headRefName) -> \(.baseRefName)",
      "\($d)changes\($r) \(.changedFiles) files, \($g)+\(.additions)\($r) \($red)-\(.deletions)\($r)",
      (if (.reviewDecision // "") != "" then "\($d)review \($r) \(.reviewDecision | ascii_downcase | gsub("_"; " "))" else empty end),
      (if (.statusCheckRollup | length) > 0 then "", "\($d)checks\($r)",
        (.statusCheckRollup[] | (.conclusion // .state // .status // "") as $c |
          (if $c == "SUCCESS" then $g elif ($c | test("FAILURE|ERROR|TIMED_OUT|CANCELLED|ACTION_REQUIRED")) then $red else $y end) as $col |
          "  \($col)\($c | ascii_downcase | if . == "" then "pending" else . end)\($r)  \(.name // .context)")
       else empty end)' -- "$view"
  fi
  # the body and the comments, one markdown file per version
  md="${view%.json}.md"
  # the temporary name taken here: $BASHPID in a redirection would be the child's
  tmp="$md.$BASHPID"
  [[ -f "$md" ]] || { command jq -r '((.body // "") | if . == "" then "*no description*" else . end),
    (.comments[]? | "\n---\n\n**\(.author.login // "ghost")** \(.createdAt[0:10])\n\n\(.body)")' -- "$view" > "$tmp" &&
    mv -f -- "$tmp" "$md"; }
  printf '\n'
  github::markdown "$md"
}

# github::preview_notification <list file> <index>: the repository, the subject's type and title, why you got
# it and when; an issue's or pull request's details below (github::item_details)
github::preview_notification() {
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' u=$'\e['"${FZX_COLORS[github_unread]:-38;5;75}m"
  local url repo updated
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r="" u=""
  IFS=$'\t' read -r url repo updated < <(command jq -r --argjson i "$2" '.[$i] | [.url, .repo, .updatedAt] | @tsv' -- "$1")
  [[ -n "$url" ]] || return 0
  command jq -r --argjson i "$2" --arg b "$b" --arg d "$d" --arg r "$r" --arg u "$u" '.[$i] |
    "\($b)\(.repo)\($r)  \(.type | gsub("(?<c>[a-z])(?<C>[A-Z])"; "\(.c) \(.C)") | ascii_downcase)\(if .unread then "  \($u)unread\($r)" else "" end)",
    "\($b)\(.title)\($r)", "",
    "\($d)reason \($r) \(.reason | gsub("_"; " "))", "\($d)updated\($r) \(.updatedAt[0:16] | sub("T"; " "))",
    "\($d)url    \($r) \(.url)"' -- "$1"
  [[ "$url" =~ /(issues|pull)/([0-9]+)$ ]] && github::item_details "$url" "$repo" "${BASH_REMATCH[2]}" "$updated"
  return 0
}

# github::debug: the f2 view's module section: every API rate limit (rate_limit itself is free)
github::debug() {
  command gh api rate_limit --jq '.resources | to_entries[] |
    "\(.key)\t\(.value.used)/\(.value.limit) used\tresets \(.value.reset | strflocaltime("%H:%M:%S"))"' 2> /dev/null |
    column -t -s $'\t'
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
    issue | pr) github::preview_issue "$4" "$5" ;;
    notification) github::preview_notification "$4" "$5" ;;
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
