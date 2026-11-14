#!/usr/bin/env bash
# github notifications mode (sourced by source.sh): your notifications, the latest 50, unread ones only;
# read ones too with the read toggle. Kept with the issue lists ($FZX_CACHE_DIR/github/issues, so every
# issue and notification action drops them) for FZX_GITHUB_ISSUES_TTL, as an array of
#   {id, unread, reason, updatedAt, repo, type, title, url}
# url is the subject's page on github.com: an issue's or pull request's (so their actions and preview work
# on it), a commit's, else the repository's releases, discussions or actions page.

# github::notifications <var>: the list's file, from the cache while it is younger than
# FZX_GITHUB_ISSUES_TTL, else from gh (written only on success; on failure gh's message is in GITHUB_ERROR)
github::notifications() {
  local _file _tmp _all=false _rc
  declare -g GITHUB_ERROR=""
  [[ " ${FZX_TOGGLES:-} " == *" read "* ]] && _all=true
  _file="$FZX_CACHE_DIR/github/issues/notifications-$([[ "$_all" == true ]] && echo all || echo unread).json"
  printf -v "$1" '%s' "$_file"
  github::fresh "$_file" "${FZX_GITHUB_ISSUES_TTL:-2m}" && return 0
  mkdir -p -- "${_file%/*}" || return
  _tmp="$_file.$BASHPID"
  # one page of 50 (the most the API gives): all=true would otherwise page through years of them
  command gh api "notifications?all=$_all&per_page=50" 2> "$_tmp.err" | command jq '[.[] |
    .repository.full_name as $repo | .subject.type as $type |
    {id, unread, reason, updatedAt: .updated_at, repo: $repo, type: $type, title: .subject.title,
     url: (.subject.url // "" |
       if . == "" then "https://github.com/\($repo)" +
         ({Discussion: "/discussions", CheckSuite: "/actions", Release: "/releases"}[$type] // "")
       else sub("^https://api\\.github\\.com/repos/"; "https://github.com/") | sub("/pulls/(?<n>[0-9]+)$"; "/pull/\(.n)") |
         sub("/commits/"; "/commit/") | sub("/releases/[0-9]+$"; "/releases") end)}]' > "$_tmp"
  _rc=${PIPESTATUS[0]}
  if ((_rc != 0)) || [[ ! -s "$_tmp" ]]; then
    GITHUB_ERROR="$(tr '\n' ' ' < "$_tmp.err")"
    rm -f -- "$_tmp" "$_tmp.err"
    return 1
  fi
  rm -f -- "$_tmp.err"
  mv -f -- "$_tmp" "$_file"
}

# github::notification_rows <file>: "url  notification  owner/name  file  index  display" per notification:
# an unread mark, the subject's type icon, the repository, the title, why you got it and its age
github::notification_rows() {
  local r=$'\e[0m' u=$'\e['"${FZX_COLORS[github_unread]:-38;5;75}m" t=$'\e['"${FZX_COLORS[github_type]:-38;5;110}m"
  local o=$'\e['"${FZX_COLORS[github_owner]:-38;5;244}m" n=$'\e['"${FZX_COLORS[github_name]:-1;38;5;75}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" i_issue i_pr i_release i_discussion i_commit i_check
  [[ -n "${NO_COLOR:+x}" ]] && r="" u="" t="" o="" n="" d=""
  fzx::require icons
  fzx::icon issue_open i_issue
  fzx::icon pr_open i_pr
  fzx::icon release i_release
  fzx::icon discussion i_discussion
  fzx::icon commit i_commit
  fzx::icon checks i_check
  # FZX_ICONS=none: a letter for the type
  command jq -r --arg file "$1" --arg r "$r" --arg u "$u" --arg t "$t" --arg o "$o" --arg n "$n" --arg d "$d" \
    --arg i_issue "${i_issue:-I}" --arg i_pr "${i_pr:-P}" --arg i_release "${i_release:-R}" \
    --arg i_discussion "${i_discussion:-D}" --arg i_commit "${i_commit:-C}" --arg i_check "${i_check:-A}" '
    def spaces($k): [range(0; $k)] | map(" ") | join("");
    def age: (now - fromdateiso8601) | floor |
      if . < 3600 then "\(. / 60 | floor)m" elif . < 86400 then "\(. / 3600 | floor)h"
      elif . < 86400 * 60 then "\(. / 86400 | floor)d" elif . < 86400 * 730 then "\(. / 2592000 | floor)mo"
      else "\(. / 31536000 | floor)y" end;
    ([.[].repo | length] | (max // 0) | [., 32] | min) as $w |
    to_entries[] | .key as $i | .value |
    (if (.repo | length) > $w then .repo[0:$w - 1] + "…" else .repo end) as $shown |
    ($shown | split("/")) as $on |
    ({Issue: $i_issue, PullRequest: $i_pr, Release: $i_release, Discussion: $i_discussion, Commit: $i_commit,
      CheckSuite: $i_check}[.type] // "?") as $icon |
    ([(if .unread then $u + "●" + $r else " " end),
      $t + $icon + $r,
      (if ($on | length) > 1 then $o + $on[0] + "/" + $r + $n + $on[1] + $r else $n + $on[0] + $r end) + spaces($w - ($shown | length)),
      (.title | gsub("[\t\r\n]+"; " ")),
      $d + "\(.reason | gsub("_"; " ")) \(.updatedAt | age)" + $r] | join(" ")) as $display |
    [.url, "notification", .repo, $file, ($i | tostring), $display] | join("\t")' -- "$1"
}

# github::notification_source: the mode's rows, or a row with gh's message when listing fails
github::notification_source() {
  local file red=$'\e[31m' r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && red="" r=""
  if ! github::notifications file; then
    printf 'github: cannot list notifications: %s\n' "$GITHUB_ERROR" >&2
    printf '%s\terror\t-\t-\t-\t%scannot list notifications:%s %s\n' "$GITHUB_ERROR" "$red" "$r" "$GITHUB_ERROR"
    return 1
  fi
  github::notification_rows "$file"
}

# github::notification_ids <url...>: the thread ids of the cached notifications about those pages
github::notification_ids() {
  local f
  for f in "$FZX_CACHE_DIR"/github/issues/notifications-*.json; do
    [[ -f "$f" ]] || continue
    # (--args: the words after the program are arguments, not files, so the list comes on stdin)
    command jq -r --args '$ARGS.positional as $u | .[] | select(.url as $x | any($u[]; . == $x)) | .id' "$@" < "$f"
  done | awk '!seen[$0]++'
}
