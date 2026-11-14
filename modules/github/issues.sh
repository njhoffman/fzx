#!/usr/bin/env bash
# github issues and prs modes (sourced by source.sh): the issues or pull requests of the repository here
# (its origin remote, or --repo OWNER/REPO), or, with no GitHub repository here or the everywhere toggle,
# the ones involving you anywhere on GitHub. Open ones; every state with the closed toggle.
# Lists are kept in $FZX_CACHE_DIR/github/issues for FZX_GITHUB_ISSUES_TTL as an array of
#   {url, number, title, state (OPEN, CLOSED or MERGED), draft, author, labels: [{name, color}], updatedAt,
#    repo, additions, deletions, review}
# additions, deletions and review (the review decision) are a repository's pull requests' only: the search
# API has none.

# github::remote_repo <var>: owner/name of the GitHub repository the directory is a clone of (its origin
# remote), without a request; fails outside one
github::remote_repo() {
  local _u
  _u="$(command git remote get-url origin 2> /dev/null)" || return 1
  _u="${_u#ssh://}" _u="${_u#git@}" _u="${_u/github.com:/github.com/}"
  [[ "$_u" == *github.com/* ]] || return 1
  github::parse_url "${_u#*github.com/}" && [[ "$GH_KIND" == repo ]] || return 1
  printf -v "$1" '%s' "$GH_REPO"
}

# github::issues_scope <var>: the repository the issues and prs modes list (--repo, else the one here),
# empty for everything involving you (no GitHub repository here, or the everywhere toggle)
github::issues_scope() {
  local _r=""
  if [[ " ${FZX_TOGGLES:-} " != *" everywhere "* ]]; then
    _r="${GITHUB_REPO:-}"
    [[ -n "$_r" ]] || github::remote_repo _r || _r=""
  fi
  printf -v "$1" '%s' "$_r"
}

# github::issues_file <issues|prs> <scope> <var>
github::issues_file() {
  local _state=open _s="${2:-involved}"
  [[ " ${FZX_TOGGLES:-} " == *" closed "* ]] && _state=all
  printf -v "$3" '%s/github/issues/%s-%s-%s.json' "$FZX_CACHE_DIR" "$1" "${_s/\//__}" "$_state"
}

# github::issues <issues|prs> <scope> <var>: the list's file, from the cache while it is younger than
# FZX_GITHUB_ISSUES_TTL, else from gh (written only on success; on failure gh's message is in GITHUB_ERROR)
github::issues() {
  local _kind="$1" _scope="$2" _file _tmp _state=open _limit="${FZX_GITHUB_LIMIT:-100}" _q _login _rc
  declare -g GITHUB_ERROR=""
  github::issues_file "$_kind" "$_scope" _file
  printf -v "$3" '%s' "$_file"
  github::fresh "$_file" "${FZX_GITHUB_ISSUES_TTL:-2m}" && return 0
  [[ " ${FZX_TOGGLES:-} " == *" closed "* ]] && _state=all
  mkdir -p -- "${_file%/*}" || return
  _tmp="$_file.$BASHPID"
  if [[ -n "$_scope" && "$_kind" == issues ]]; then
    command gh issue list -R "$_scope" --state "$_state" -L "$_limit" --json number,title,state,author,labels,updatedAt,url \
      2> "$_tmp.err" | command jq --arg repo "$_scope" '[.[] | {url, number, title, state, draft: false, author: .author.login,
        labels: [.labels[] | {name, color}], updatedAt, repo: $repo, additions: null, deletions: null, review: null}]' > "$_tmp"
    _rc=${PIPESTATUS[0]}
  elif [[ -n "$_scope" ]]; then
    command gh pr list -R "$_scope" --state "$_state" -L "$_limit" \
      --json number,title,state,isDraft,author,labels,updatedAt,url,additions,deletions,reviewDecision 2> "$_tmp.err" |
      command jq --arg repo "$_scope" '[.[] | {url, number, title, state, draft: .isDraft, author: .author.login,
        labels: [.labels[] | {name, color}], updatedAt, repo: $repo, additions, deletions, review: (.reviewDecision // "")}]' > "$_tmp"
    _rc=${PIPESTATUS[0]}
  else
    # the search API rather than gh search: it has merged pull requests, drafts and label colors
    if ! _login="$(github::login)"; then
      GITHUB_ERROR="cannot read your GitHub login"
      return 1
    fi
    _q="involves:$_login is:${_kind%s}"
    [[ "$_state" == open ]] && _q+=" state:open"
    ((_limit > 100)) && _limit=100
    command gh api "search/issues?q=$(command jq -rn --arg q "$_q" '$q | @uri')&sort=updated&order=desc&per_page=$_limit" \
      2> "$_tmp.err" | command jq '[.items[] | {url: .html_url, number, title,
        state: (if .pull_request.merged_at then "MERGED" else (.state | ascii_upcase) end), draft: (.draft // false),
        author: .user.login, labels: [.labels[] | {name, color}], updatedAt: .updated_at,
        repo: (.repository_url | sub(".*/repos/"; "")), additions: null, deletions: null, review: null}]' > "$_tmp"
    _rc=${PIPESTATUS[0]}
  fi
  if ((_rc != 0)) || [[ ! -s "$_tmp" ]]; then
    GITHUB_ERROR="$(tr '\n' ' ' < "$_tmp.err")"
    rm -f -- "$_tmp" "$_tmp.err"
    return 1
  fi
  rm -f -- "$_tmp.err"
  mv -f -- "$_tmp" "$_file"
}

# github::issues_drop: forget every issue and pull request list (an action changed one)
github::issues_drop() { rm -rf -- "${FZX_CACHE_DIR:?}/github/issues"; }

# jq: a label as a chip, its GitHub color as the background and black or white text by its brightness;
# "[name]" with $nc (NO_COLOR) or a color that is not six hex digits. Shared by the rows and the preview.
# shellcheck disable=SC2016  # jq, not shell
GITHUB_JQ_CHIP='
  def hex: ascii_downcase | explode | map(if . >= 97 then . - 87 else . - 48 end) | .[0] * 16 + .[1];
  def chip: if $nc or ((.color // "") | test("^[0-9a-fA-F]{6}$") | not) then "[\(.name)]"
    else [.color[0:2], .color[2:4], .color[4:6] | hex] as $c |
      (if ($c[0] * 299 + $c[1] * 587 + $c[2] * 114) / 1000 > 140 then "30" else "97" end) as $fg |
      "\u001b[48;2;\($c | map(tostring) | join(";"));\($fg)m \(.name) \u001b[0m" end;'

# jq: timeline, the comments and a pull request's reviews (those with a verdict or a text; pending ones are only
# their author's) of a `gh issue|pr view` file, oldest first, as {who, assoc, what, at, body, item}: assoc the
# author's association with the repository ("" for none), what the review's verdict ("" for a comment), item
# the comment or review itself. Shared by the preview's markdown and its header lines.
# entries($th): the timeline, then a pull request's review threads ($th: the reviewThreads nodes of
# github::review_threads): a section entry {type: "section", n, resolved}, then per thread by file and line a
# {type: "thread", path, line, outdated, resolved, hunk} entry (hunk: the last FZX_GITHUB_HUNK_LINES lines of
# the diff it comments on) and, unless it is resolved, its comments as timeline entries
# shellcheck disable=SC2016,SC2034  # jq, not shell; used by preview.sh
GITHUB_JQ_TIMELINE='
  def assoc: (.authorAssociation // "NONE") | if . == "NONE" or . == "" then "" else ascii_downcase | gsub("_"; " ") end;
  def timeline: [(.comments[]? | {who: .author.login, assoc: assoc, at: .createdAt, what: "", body, item: .}),
    (.reviews[]? | select(.state != "PENDING" and (.state != "COMMENTED" or (.body // "") != "")) |
      {who: .author.login, assoc: assoc, at: .submittedAt,
       what: (if .state == "COMMENTED" then "reviewed" else .state | ascii_downcase | gsub("_"; " ") end), body, item: .})] |
    sort_by(.at)[];
  def threads($th; $hunk): if ($th | length) == 0 then empty else
    {type: "section", n: ($th | length), resolved: ([$th[] | select(.isResolved)] | length)},
    ($th | sort_by(.path, (.line // .originalLine // 0))[] |
      {type: "thread", path, line: (.line // .originalLine), outdated: .isOutdated, resolved: .isResolved,
       hunk: (if .isResolved then "" else (.comments.nodes[0].diffHunk // "") | split("\n") | .[-$hunk:] | join("\n") end)},
      (if .isResolved then empty else
        .comments.nodes[] | {who: .author.login, assoc: assoc, at: .createdAt, what: "", body, item: .} end))
  end;
  def entries($th; $hunk): timeline, threads($th; $hunk);'

# github::issue_rows <file> <scope>: "url  issue|pr  owner/name  file  index  display" per item: the state's
# icon in its color, the repository (a list that is not one repository's), #number, the title, the labels in
# their GitHub colors, the author and the last activity's age; a repository's pull requests add their
# +additions -deletions and the review decision
github::issue_rows() {
  local r=$'\e[0m' nc=false
  local c_open=$'\e['"${FZX_COLORS[github_open]:-38;5;114}m" c_closed=$'\e['"${FZX_COLORS[github_closed]:-38;5;203}m"
  local c_merged=$'\e['"${FZX_COLORS[github_merged]:-38;5;141}m" c_draft=$'\e['"${FZX_COLORS[github_draft]:-38;5;244}m"
  local o=$'\e['"${FZX_COLORS[github_owner]:-38;5;244}m" n=$'\e['"${FZX_COLORS[github_name]:-1;38;5;75}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" b=$'\e[1m'
  [[ -n "${NO_COLOR:+x}" ]] && r="" c_open="" c_closed="" c_merged="" c_draft="" o="" n="" d="" b="" nc=true
  local i_open i_closed i_pr i_merged i_prclosed i_draft i_ok i_failed
  fzx::require icons
  fzx::icon issue_open i_open
  fzx::icon issue_closed i_closed
  fzx::icon pr_open i_pr
  fzx::icon pr_merged i_merged
  fzx::icon pr_closed i_prclosed
  fzx::icon pr_draft i_draft
  fzx::icon ok i_ok
  fzx::icon failed i_failed
  # FZX_ICONS=none: a letter for the state, words for the review
  command jq -r --arg file "$1" --arg scope "$2" --argjson nc "$nc" --arg r "$r" --arg o "$o" --arg n "$n" --arg d "$d" --arg b "$b" \
    --arg c_open "$c_open" --arg c_closed "$c_closed" --arg c_merged "$c_merged" --arg c_draft "$c_draft" \
    --arg i_open "${i_open:-O}" --arg i_closed "${i_closed:-C}" --arg i_pr "${i_pr:-O}" --arg i_merged "${i_merged:-M}" \
    --arg i_prclosed "${i_prclosed:-C}" --arg i_draft "${i_draft:-D}" --arg i_ok "${i_ok:-approved}" \
    --arg i_failed "${i_failed:-changes requested}" "$GITHUB_JQ_CHIP"'
    def spaces($k): [range(0; $k)] | map(" ") | join("");
    def pad($w): . + spaces([$w - length, 1] | max);
    def age: (now - fromdateiso8601) | floor |
      if . < 3600 then "\(. / 60 | floor)m" elif . < 86400 then "\(. / 3600 | floor)h"
      elif . < 86400 * 60 then "\(. / 86400 | floor)d" elif . < 86400 * 730 then "\(. / 2592000 | floor)mo"
      else "\(. / 31536000 | floor)y" end;
    ([.[].repo | length] | (max // 0) | [., 32] | min) as $w |
    to_entries[] | .key as $i | .value |
    (if (.url | test("/pull/")) then "pr" else "issue" end) as $k |
    (if $k == "pr" then
       (if .state == "MERGED" then [$i_merged, $c_merged] elif .state == "CLOSED" then [$i_prclosed, $c_closed]
        elif .draft then [$i_draft, $c_draft] else [$i_pr, $c_open] end)
     else (if .state == "CLOSED" then [$i_closed, $c_closed] else [$i_open, $c_open] end) end) as $s |
    # the repository column: names longer than it are cut, ending in "…"
    (if (.repo | length) > $w then .repo[0:$w - 1] + "…" else .repo end) as $shown |
    ($shown | split("/")) as $on | ($shown | length) as $rl |
    ([$s[1] + $s[0] + $r,
      (if $scope == "" then (if ($on | length) > 1 then $o + $on[0] + "/" + $r + $n + $on[1] + $r else $n + $on[0] + $r end) +
         spaces($w - $rl) else empty end),
      $b + ("#\(.number)" | pad(6)) + $r + (.title | gsub("[\t\r\n]+"; " ")),
      (.labels | map(chip) | join(" ") | select(. != "")),
      $d + "\(.author // "ghost") \(.updatedAt | age)" + $r,
      (if .additions != null then $c_open + "+\(.additions)" + $r + " " + $c_closed + "-\(.deletions)" + $r else empty end),
      (if .review == "APPROVED" then $c_open + $i_ok + $r elif .review == "CHANGES_REQUESTED" then $c_closed + $i_failed + $r
       else empty end)] | join(" ")) as $display |
    [.url, $k, .repo, $file, ($i | tostring), $display] | join("\t")' -- "$1"
}

# github::issue_source <issues|prs>: the mode's rows, or a row with gh's message when listing fails
github::issue_source() {
  local scope file red=$'\e[31m' r=$'\e[0m' what="$1"
  [[ -n "${NO_COLOR:+x}" ]] && red="" r=""
  [[ "$what" == prs ]] && what="pull requests"
  github::issues_scope scope
  if ! github::issues "$1" "$scope" file; then
    printf 'github: cannot list %s: %s\n' "$what" "$GITHUB_ERROR" >&2
    printf '%s\terror\t-\t-\t-\t%scannot list %s:%s %s\n' "$GITHUB_ERROR" "$red" "$what" "$r" "$GITHUB_ERROR"
    return 1
  fi
  github::issue_rows "$file" "$scope"
}
