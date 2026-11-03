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
  local hl=$'\e['"${FZX_COLORS[github_match]:-1;38;5;195;48;5;23}m" b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
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

# github::preview_issue <list file> <index>: from the list, the state (its icon and word in its color), title,
# author, labels as chips and dates; then github::item_details
github::preview_issue() {
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' nc=false
  local g=$'\e['"${FZX_COLORS[github_open]:-38;5;114}m" red=$'\e['"${FZX_COLORS[github_closed]:-38;5;203}m"
  local m=$'\e['"${FZX_COLORS[github_merged]:-38;5;141}m" dr=$'\e['"${FZX_COLORS[github_draft]:-38;5;244}m"
  local url repo num updated i_open i_closed i_pr i_merged i_prclosed i_draft
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r="" g="" red="" m="" dr="" nc=true
  IFS=$'\t' read -r url repo num updated < <(command jq -r --argjson i "$2" '.[$i] | [.url, .repo, .number, .updatedAt] | @tsv' -- "$1")
  [[ -n "$url" ]] || return 0
  fzx::require icons
  fzx::icon issue_open i_open
  fzx::icon issue_closed i_closed
  fzx::icon pr_open i_pr
  fzx::icon pr_merged i_merged
  fzx::icon pr_closed i_prclosed
  fzx::icon pr_draft i_draft
  command jq -r --argjson i "$2" --argjson nc "$nc" --arg b "$b" --arg d "$d" --arg r "$r" --arg g "$g" --arg red "$red" \
    --arg m "$m" --arg dr "$dr" --arg i_open "$i_open" --arg i_closed "$i_closed" --arg i_pr "$i_pr" --arg i_merged "$i_merged" \
    --arg i_prclosed "$i_prclosed" --arg i_draft "$i_draft" "$GITHUB_JQ_CHIP"'
    .[$i] |
    (if (.url | test("/pull/")) then
       (if .state == "MERGED" then [$i_merged, $m, "merged"] elif .state == "CLOSED" then [$i_prclosed, $red, "closed"]
        elif .draft then [$i_draft, $dr, "draft"] else [$i_pr, $g, "open"] end)
     else (if .state == "CLOSED" then [$i_closed, $red, "closed"] else [$i_open, $g, "open"] end) end) as $s |
    "\($b)\(.repo) #\(.number)\($r)  \($s[1])\(if $s[0] != "" then $s[0] + " " else "" end)\($s[2])\($r)",
    "\($b)\(.title)\($r)", "",
    "\($d)author \($r) \(.author // "ghost")", "\($d)updated\($r) \(.updatedAt[0:16] | sub("T"; " "))",
    (if (.labels | length) > 0 then "\($d)labels \($r) \(.labels | map(chip) | join(" "))" else empty end)' -- "$1"
  github::item_details "$url" "$repo" "$num" "$updated"
}

# github::item_details <url> <owner/name> <number> <updated>: a pull request's branches, size, review and
# checks, then the body and its reactions and the timeline as markdown: the comments and, for a pull request,
# the reviews (those with a verdict or a text), oldest first, each under a heading with its author, the
# author's association with the repository, the verdict and the date, and its reactions below. Cached by the
# last update, so a new comment fetches them again; the markdown also by the icon style
github::item_details() {
  local url="$1" repo="$2" num="$3" updated="$4" kind fields view md tmp
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' y=$'\e[38;5;180m'
  local g=$'\e['"${FZX_COLORS[github_open]:-38;5;114}m" red=$'\e['"${FZX_COLORS[github_closed]:-38;5;203}m"
  local i_ok i_failed i_review n
  local -A re=()
  [[ -n "${NO_COLOR+x}" ]] && d="" r="" y="" g="" red=""
  kind=issue fields=body,comments,reactionGroups
  if [[ "$url" == */pull/* ]]; then
    kind=pr fields+=,reviews,headRefName,baseRefName,changedFiles,additions,deletions,reviewDecision,statusCheckRollup
  fi
  # -2: the format with reactions and reviews (older files lack their fields)
  view="$FZX_CACHE_DIR/github/view/${repo/\//__}-$num@${updated//[^0-9]/}-2.json"
  if ! github::cached "$view" command gh "$kind" view "$url" --json "$fields" > /dev/null 2>&1; then
    printf '\n%scannot read %s%s\n' "$d" "$url" "$r"
    return 0
  fi
  fzx::require icons
  fzx::icon ok i_ok
  fzx::icon failed i_failed
  fzx::icon review i_review
  for n in thumbs_up thumbs_down laugh hooray confused heart rocket eyes; do
    fzx::icon "reaction_$n" "re[$n]"
  done
  if [[ "$kind" == pr ]]; then
    command jq -r --arg d "$d" --arg r "$r" --arg g "$g" --arg red "$red" --arg y "$y" \
      --arg i_ok "$i_ok" --arg i_failed "$i_failed" --arg i_review "$i_review" '
      def icon($i): if $i == "" then "" else $i + " " end;
      "\($d)branch \($r) \(.headRefName) -> \(.baseRefName)",
      "\($d)changes\($r) \(.changedFiles) files, \($g)+\(.additions)\($r) \($red)-\(.deletions)\($r)",
      ((.reviewDecision // "") as $v | if $v == "" then empty else
        (if $v == "APPROVED" then $g + icon($i_ok) elif $v == "CHANGES_REQUESTED" then $red + icon($i_failed)
         elif $v == "REVIEW_REQUIRED" then $y + icon($i_review) else "" end) as $c |
        "\($d)review \($r) \($c)\($v | ascii_downcase | gsub("_"; " "))\($r)" end),
      (if (.statusCheckRollup | length) > 0 then "", "\($d)checks\($r)",
        (.statusCheckRollup[] | (.conclusion // .state // .status // "") as $c |
          (if $c == "SUCCESS" then $g elif ($c | test("FAILURE|ERROR|TIMED_OUT|CANCELLED|ACTION_REQUIRED")) then $red else $y end) as $col |
          "  \($col)\($c | ascii_downcase | if . == "" then "pending" else . end)\($r)  \(.name // .context)")
       else empty end)' -- "$view"
  fi
  # the body and the timeline, one markdown file per version and icon style
  md="${view%.json}.${FZX_ICONS:-nerd}.md"
  # the temporary name taken here: $BASHPID in a redirection would be the child's
  tmp="$md.$BASHPID"
  [[ -f "$md" ]] || {
    command jq -r --arg up "${re[thumbs_up]}" --arg down "${re[thumbs_down]}" --arg laugh "${re[laugh]}" \
      --arg hooray "${re[hooray]}" --arg confused "${re[confused]}" --arg heart "${re[heart]}" --arg rocket "${re[rocket]}" \
      --arg eyes "${re[eyes]}" '
      {THUMBS_UP: $up, THUMBS_DOWN: $down, LAUGH: $laugh, HOORAY: $hooray, CONFUSED: $confused, HEART: $heart,
       ROCKET: $rocket, EYES: $eyes} as $icons |
      # the reactions given, "<icon> N" each (FZX_ICONS=none: +1, -1 or the name)
      def reactions: [(.reactionGroups // [])[] | select((.users.totalCount // 0) > 0) |
        (if ($icons[.content] // "") != "" then $icons[.content]
         else ({THUMBS_UP: "+1", THUMBS_DOWN: "-1"}[.content] // (.content | ascii_downcase)) end) + " \(.users.totalCount)"] |
        join("  ");
      def assoc: (.authorAssociation // "NONE") | if . == "NONE" or . == "" then "" else " (\(ascii_downcase | gsub("_"; " ")))" end;
      ((.body // "") | if . == "" then "*no description*" else . end),
      (reactions | select(. != "") | "\n" + .),
      ([(.comments[]? | {who: .author.login, assoc: assoc, at: .createdAt, what: "", body, reactions: reactions}),
        (.reviews[]? | select(.state != "PENDING" and (.state != "COMMENTED" or (.body // "") != "")) |
          {who: .author.login, assoc: assoc, at: .submittedAt,
           what: (if .state == "COMMENTED" then "reviewed" else .state | ascii_downcase | gsub("_"; " ") end),
           body, reactions: reactions})] |
        sort_by(.at)[] |
        "\n---\n\n### \(.who // "ghost")\(.assoc)\(if .what != "" then " · " + .what else "" end) · \(.at[0:10])",
        (if (.body // "") != "" then "\n" + .body else empty end),
        (if .reactions != "" then "\n" + .reactions else empty end))' -- "$view" > "$tmp" &&
      mv -f -- "$tmp" "$md"
  }
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

# github::preview_hub <owner/name> <target>: files: the repository's description, branch and README; issues
# and prs: the first open ones; runs: the latest runs (the lists the rows open, cached for them)
github::preview_hub() {
  local repo="$1" b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' info file pushed readme
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  info="$FZX_CACHE_DIR/github/issues/repo-${repo/\//__}.json"
  case "$2" in
    tree)
      [[ -f "$info" ]] || return 0
      command jq -r --arg b "$b" --arg d "$d" --arg r "$r" '
        "\($b)\(.nameWithOwner)\($r)\(if .isArchived then "  \($d)archived\($r)" else "" end)", (.description // ""), "",
        "\($d)branch\($r)  \(.defaultBranchRef.name // "")", "\($d)pushed\($r)  \(.pushedAt[0:10])", "\($d)url   \($r)  \(.url)"' -- "$info"
      pushed="$(command jq -r '.pushedAt // ""' -- "$info")"
      readme="$FZX_CACHE_DIR/github/readme/${repo/\//__}@${pushed//[^0-9]/}"
      if github::cached "$readme" github::api "repos/$repo/readme" > /dev/null 2>&1; then
        printf '\n'
        github::markdown "$readme"
      else
        printf '\n%sno README%s\n' "$d" "$r"
      fi
      ;;
    issues | prs)
      if ! FZX_TOGGLES="" github::issues "$2" "$repo" file; then
        printf '%scannot list them: %s%s\n' "$d" "$GITHUB_ERROR" "$r"
        return 0
      fi
      printf '%s%s open %s%s\n\n' "$b" "$(command jq length -- "$file")" "$([[ "$2" == prs ]] && echo "pull requests" || echo issues)" "$r"
      github::issue_rows "$file" "$repo" | head -n "${FZF_PREVIEW_LINES:-30}" | cut -f6
      ;;
    runs)
      if ! github::runs "$repo" file; then
        printf '%scannot list them: %s%s\n' "$d" "$GITHUB_ERROR" "$r"
        return 0
      fi
      printf '%slatest workflow runs%s\n\n' "$b" "$r"
      github::run_rows "$file" "$repo" | head -n "${FZF_PREVIEW_LINES:-30}" | cut -f6
      ;;
  esac
}

# github::preview_run <list file> <index>: the run from the list, then its jobs (cached by the run's last
# update) with the failed steps of failed jobs
github::preview_run() {
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  local g=$'\e['"${FZX_COLORS[github_open]:-38;5;114}m" red=$'\e['"${FZX_COLORS[github_closed]:-38;5;203}m"
  local y=$'\e['"${FZX_COLORS[github_running]:-38;5;180}m" id repo updated view
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r="" g="" red="" y=""
  IFS='|' read -r id repo updated < <(command jq -r --argjson i "$2" '.[$i] |
    [.id, (.url | capture("github.com/(?<r>[^/]+/[^/]+)/").r), .updatedAt] | map(tostring) | join("|")' -- "$1")
  [[ -n "$id" ]] || return 0
  command jq -r --argjson i "$2" --arg b "$b" --arg d "$d" --arg r "$r" --arg g "$g" --arg red "$red" --arg y "$y" '.[$i] |
    (if .status != "completed" then $y + (.status | gsub("_"; " "))
     elif .conclusion == "success" then $g + "success"
     elif (.conclusion | test("^(failure|timed_out|startup_failure|action_required)$")) then $red + (.conclusion | gsub("_"; " "))
     else $d + .conclusion end) as $s |
    "\($b)\(.workflow) #\(.number)\($r)  \($s)\($r)\(if .attempt > 1 then "  \($d)attempt \(.attempt)\($r)" else "" end)",
    "\($b)\(.title)\($r)", "",
    "\($d)branch \($r) \(.branch)", "\($d)event  \($r) \(.event)",
    "\($d)started\($r) \((.startedAt // .createdAt)[0:16] | sub("T"; " "))", "\($d)url    \($r) \(.url)"' -- "$1"
  view="$FZX_CACHE_DIR/github/view/run-${repo/\//__}-$id@${updated//[^0-9]/}.json"
  if ! github::cached "$view" command gh run view "$id" -R "$repo" --json jobs > /dev/null 2>&1; then
    printf '\n%scannot read the jobs%s\n' "$d" "$r"
    return 0
  fi
  printf '\n%sjobs%s\n' "$d" "$r"
  command jq -r --arg d "$d" --arg r "$r" --arg g "$g" --arg red "$red" --arg y "$y" '
    def col: if . == "success" then $g elif (. // "" | test("^(failure|timed_out|startup_failure)$")) then $red
      elif . == null or . == "" then $y else $d end;
    def took: if (.startedAt // "") == "" or (.completedAt // "") == "" or (.completedAt | startswith("0001")) then ""
      else ((.completedAt | fromdateiso8601) - (.startedAt | fromdateiso8601)) |
        if . < 60 then "  \($d)\(.)s\($r)" else "  \($d)\(. / 60 | floor)m\(. % 60)s\($r)" end end;
    .jobs[] | (.conclusion // "") as $c |
    "  \($c | col)\(if $c == "" then (.status | gsub("_"; " ")) else $c end)\($r)  \(.name)\(took)",
    (if ($c | test("^(failure|timed_out)$")) then
      (.steps[]? | select(.conclusion == "failure") | "      \($red)failed\($r) step \(.number): \(.name)") else empty end)' -- "$view"
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
    hub) github::preview_hub "$3" "$4" ;;
    run) github::preview_run "$4" "$5" ;;
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
