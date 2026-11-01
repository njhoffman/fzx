#!/usr/bin/env bash
# github repo and runs modes (sourced by source.sh). repo is a repository's hub: its files, open issues, open
# pull requests and workflow runs, one row each, opening the list as a child session (enter or ctrl-o).
# runs lists the repository's workflow runs, latest first. Both take --repo OWNER/REPO, else the repository
# here (its origin remote).
# The hub's counts come from `gh repo view` ($FZX_CACHE_DIR/github/issues/repo-O__R.json), the runs from `gh
# run list` (runs-O__R.json), both kept with the issue lists for FZX_GITHUB_ISSUES_TTL (an action drops
# them). A run list is an array of
#   {id, number, title, workflow, branch, event, status, conclusion, createdAt, updatedAt, startedAt, url, attempt}

# github::scope_repo <var>: --repo, else the repository here; fails with a message when there is neither
github::scope_repo() {
  local _r="${GITHUB_REPO:-}"
  [[ -n "$_r" ]] || github::remote_repo _r || {
    printf 'github: %s needs --repo OWNER/REPO or a GitHub clone here\n' "${FZX_MODE:-repo}" >&2
    return 1
  }
  printf -v "$1" '%s' "$_r"
}

# github::fetch_json <file> <ttl> <command...>: the file, written from the command's output when it is missing
# or older than the ttl (only on success; on failure gh's message is in GITHUB_ERROR)
github::fetch_json() {
  local _file="$1" _ttl="$2" _tmp _rc
  shift 2
  declare -g GITHUB_ERROR=""
  github::fresh "$_file" "$_ttl" && return 0
  mkdir -p -- "${_file%/*}" || return
  _tmp="$_file.$BASHPID"
  "$@" > "$_tmp" 2> "$_tmp.err"
  _rc=$?
  if ((_rc != 0)) || [[ ! -s "$_tmp" ]]; then
    GITHUB_ERROR="$(tr '\n' ' ' < "$_tmp.err")"
    rm -f -- "$_tmp" "$_tmp.err"
    return 1
  fi
  rm -f -- "$_tmp.err"
  mv -f -- "$_tmp" "$_file"
}

# github::hub_info <owner/name> <var>: the hub's file: description, default branch, last push, open issue
# and pull request counts
github::hub_info() {
  local _f="$FZX_CACHE_DIR/github/issues/repo-${1/\//__}.json"
  printf -v "$2" '%s' "$_f"
  github::fetch_json "$_f" "${FZX_GITHUB_ISSUES_TTL:-2m}" command gh repo view "$1" \
    --json nameWithOwner,description,url,pushedAt,defaultBranchRef,issues,pullRequests,isArchived
}

# github::_runs <owner/name>: gh run list in the run list's fields
github::_runs() {
  command gh run list -R "$1" -L "${FZX_GITHUB_LIMIT:-100}" \
    --json databaseId,number,displayTitle,workflowName,headBranch,event,status,conclusion,createdAt,updatedAt,startedAt,url,attempt |
    command jq '[.[] | {id: .databaseId, number, title: .displayTitle, workflow: .workflowName, branch: .headBranch, event,
      status, conclusion, createdAt, updatedAt, startedAt, url, attempt}]'
  return "${PIPESTATUS[0]}"
}

# github::runs <owner/name> <var>: the run list's file
github::runs() {
  local _f="$FZX_CACHE_DIR/github/issues/runs-${1/\//__}.json"
  printf -v "$2" '%s' "$_f"
  github::fetch_json "$_f" "${FZX_GITHUB_ISSUES_TTL:-2m}" github::_runs "$1"
}

# github::run_state <status> <conclusion>: success, failure, cancelled, skipped, running or queued
github::run_state() {
  case "$1:$2" in
    completed:success) echo success ;;
    completed:failure | completed:timed_out | completed:startup_failure | completed:action_required) echo failure ;;
    completed:cancelled) echo cancelled ;;
    completed:*) echo skipped ;;
    in_progress:*) echo running ;;
    *) echo queued ;;
  esac
}

# github::run_rows <file>: "url  run  owner/name  file  index  display" per run: the state's icon in its color,
# the workflow, the title, the branch and event, the run's age and how long it took (or has been running)
github::run_rows() {
  local repo="$2" r=$'\e[0m'
  local c_ok=$'\e['"${FZX_COLORS[github_open]:-38;5;114}m" c_fail=$'\e['"${FZX_COLORS[github_closed]:-38;5;203}m"
  local c_run=$'\e['"${FZX_COLORS[github_running]:-38;5;180}m" c_dim=$'\e['"${FZX_COLORS[github_draft]:-38;5;244}m"
  local n=$'\e['"${FZX_COLORS[github_name]:-1;38;5;75}m" d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m"
  [[ -n "${NO_COLOR+x}" ]] && r="" c_ok="" c_fail="" c_run="" c_dim="" n="" d=""
  local i_ok i_failed i_running i_stopped i_paused
  fzx::require icons
  fzx::icon ok i_ok
  fzx::icon failed i_failed
  fzx::icon running i_running
  fzx::icon stopped i_stopped
  fzx::icon paused i_paused
  command jq -r --arg file "$1" --arg repo "$repo" --arg r "$r" --arg n "$n" --arg d "$d" \
    --arg c_ok "$c_ok" --arg c_fail "$c_fail" --arg c_run "$c_run" --arg c_dim "$c_dim" \
    --arg i_ok "${i_ok:-S}" --arg i_failed "${i_failed:-F}" --arg i_running "${i_running:-R}" \
    --arg i_stopped "${i_stopped:-C}" --arg i_paused "${i_paused:-Q}" '
    def spaces($k): [range(0; $k)] | map(" ") | join("");
    def pad($w): if length > $w then .[0:$w - 1] + "…" else . + spaces($w - length) end;
    def span: floor | if . < 60 then "\(.)s" elif . < 3600 then "\(. / 60 | floor)m\(. % 60)s"
      else "\(. / 3600 | floor)h\(. % 3600 / 60 | floor)m" end;
    def age: (now - fromdateiso8601) | floor |
      if . < 3600 then "\(. / 60 | floor)m" elif . < 86400 then "\(. / 3600 | floor)h"
      elif . < 86400 * 60 then "\(. / 86400 | floor)d" elif . < 86400 * 730 then "\(. / 2592000 | floor)mo"
      else "\(. / 31536000 | floor)y" end;
    ([.[].workflow | length] | (max // 0) | [., 24] | min) as $w |
    to_entries[] | .key as $i | .value |
    (if .status == "completed" then
       (if .conclusion == "success" then [$i_ok, $c_ok]
        elif (.conclusion | test("^(failure|timed_out|startup_failure|action_required)$")) then [$i_failed, $c_fail]
        elif .conclusion == "cancelled" then [$i_stopped, $c_dim] else ["-", $c_dim] end)
     elif .status == "in_progress" then [$i_running, $c_run] else [$i_paused, $c_run] end) as $s |
    ((.startedAt // .createdAt) | fromdateiso8601) as $start |
    (if .status == "completed" then (.updatedAt | fromdateiso8601) - $start else now - $start end) as $took |
    ([$s[1] + $s[0] + $r,
      $n + (.workflow | pad($w)) + $r,
      (.title | gsub("[\t\r\n]+"; " ")),
      $d + "\(.branch) \(.event) \(.createdAt | age)" + $r,
      $s[1] + ($took | if . < 0 then 0 else . end | span) + $r] | join(" ")) as $display |
    [.url, "run", $repo, $file, ($i | tostring), $display] | join("\t")' -- "$1"
}

# github::runs_source: the runs mode's rows, or a row with gh's message when listing fails
github::runs_source() {
  local repo file red=$'\e[31m' r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && red="" r=""
  github::scope_repo repo || return
  if ! github::runs "$repo" file; then
    printf 'github: cannot list the runs of %s: %s\n' "$repo" "$GITHUB_ERROR" >&2
    printf '%s\terror\t-\t-\t-\t%scannot list workflow runs:%s %s\n' "$GITHUB_ERROR" "$red" "$r" "$GITHUB_ERROR"
    return 1
  fi
  [[ -s "$file" && "$(command jq length -- "$file")" != 0 ]] || {
    printf -- '-\terror\t-\t-\t-\t  %s has no workflow runs\n' "$repo"
    return 0
  }
  github::run_rows "$file" "$repo"
}

# github::hub_source: the repo mode's rows, "url  hub  owner/name  target  -  display": files (tree), issues,
# prs and runs, each with its count or the last run's state. The run list is fetched alongside the counts
github::hub_source() {
  local repo info runs="" red=$'\e[31m' r=$'\e[0m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" b=$'\e[1m'
  [[ -n "${NO_COLOR+x}" ]] && red="" r="" d="" b=""
  github::scope_repo repo || return
  # the runs in the background: a failure only leaves the row without its state
  (github::runs "$repo" runs > /dev/null 2>&1) &
  if ! github::hub_info "$repo" info; then
    wait
    printf 'github: cannot read %s: %s\n' "$repo" "$GITHUB_ERROR" >&2
    printf '%s\terror\t-\t-\t-\t%scannot read %s:%s %s\n' "$GITHUB_ERROR" "$red" "$repo" "$r" "$GITHUB_ERROR"
    return 1
  fi
  wait
  runs="$FZX_CACHE_DIR/github/issues/runs-${repo/\//__}.json"
  local i_tree i_issue i_pr i_checks last="" state=""
  fzx::require icons
  fzx::icon folder i_tree
  fzx::icon issue_open i_issue
  fzx::icon pr_open i_pr
  fzx::icon checks i_checks
  if [[ -s "$runs" ]]; then
    # "|"-joined: tabs would run together where the conclusion is empty
    local st cl
    IFS='|' read -r st cl last < <(command jq -r '.[0] // empty | [.status, .conclusion // "", .workflow] | join("|")' -- "$runs")
    [[ -n "$st" ]] && state="$(github::run_state "$st" "$cl")"
  fi
  local u="https://github.com/$repo"
  command jq -r --arg u "$u" --arg repo "$repo" --arg b "$b" --arg d "$d" --arg r "$r" \
    --arg i_tree "${i_tree:+$i_tree }" --arg i_issue "${i_issue:+$i_issue }" --arg i_pr "${i_pr:+$i_pr }" \
    --arg i_checks "${i_checks:+$i_checks }" --arg state "$state" --arg last "$last" '
    [[$u, "tree", "\($i_tree)\($b)files\($r)        \($d)\(.defaultBranchRef.name // "")\($r)"],
     [$u + "/issues", "issues", "\($i_issue)\($b)issues\($r)       \(.issues.totalCount) open"],
     [$u + "/pulls", "prs", "\($i_pr)\($b)pull requests\($r) \(.pullRequests.totalCount) open"],
     [$u + "/actions", "runs", "\($i_checks)\($b)workflow runs\($r) \(if $state == "" then "\($d)none\($r)" else "last: \($state) \($d)\($last)\($r)" end)"]][] |
    [.[0], "hub", $repo, .[1], "-", .[2]] | join("\t")' -- "$info"
}

# github::hub_header <var>: the repo mode's header
github::hub_header() {
  local _repo
  github::scope_repo _repo 2> /dev/null || _repo="no repository"
  printf -v "$1" '%s' "$_repo: enter or ${FZX_KEYS[github.into]:-ctrl-o} opens the list"
}
