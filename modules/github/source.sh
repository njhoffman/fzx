#!/usr/bin/env bash
# github source, through gh. repos and code search GitHub for $FZF_QUERY (on enter, github::transform; not
# as you type), or list the mode's recent searches when the query is empty; tree lists a repository's files.
# Lines are 6 tab-separated fields, the last one displayed; the first is a github.com URL wherever there is
# one, so the actions take any row:
#   repo:    url    repo    owner/name  search file  index  display
#   code:    url    code    owner/name  search file  index  display
#   blob:    url    blob    owner/name  sha:size     path   display   (tree: a file)
#   tree:    url    tree    owner/name  -            path   display   (tree: a directory)
#   recent:  query  search  mode        -            -      display   (enter searches it again)
#   error:   text   error   -           -            -      display   (the search failed)
# Searches are kept as gh's JSON in $FZX_CACHE_DIR/github/search/<mode> for FZX_GITHUB_CACHE_TTL; trees and
# file contents by their sha. Under fzx the query each mode's list shows is in state/github_query_<mode>.
# Mode from $FZX_MODE: repos, code, tree (`--repo OWNER/REPO [--ref REF]`).

GITHUB_REPO_FIELDS="fullName,url,description,language,stargazersCount,forksCount,openIssuesCount,watchersCount"
GITHUB_REPO_FIELDS+=",pushedAt,createdAt,isArchived,isFork,license,homepage,defaultBranch,visibility,size"
GITHUB_CODE_FIELDS="path,repository,sha,textMatches,url"

# github::trim <text> <var>: without leading and trailing whitespace
github::trim() {
  local _t="$1"
  _t="${_t#"${_t%%[![:space:]]*}"}"
  _t="${_t%"${_t##*[![:space:]]}"}"
  printf -v "$2" '%s' "$_t"
}

# github::args [--repo OWNER/REPO] [--ref REF] [--]: GITHUB_REPO and GITHUB_REF (default HEAD, the
# default branch)
github::args() {
  declare -g GITHUB_REPO="" GITHUB_REF=HEAD
  while (($#)); do
    case "$1" in
      --repo) GITHUB_REPO="${2:-}" && shift 2 ;;
      --ref) GITHUB_REF="${2:-HEAD}" && shift 2 ;;
      --) shift; break ;;
      *) printf 'github: unknown argument: %s\n' "$1" >&2; return 2 ;;
    esac
  done
  if [[ "${FZX_MODE:-repos}" == tree && ! "$GITHUB_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    printf 'github: tree needs --repo OWNER/REPO\n' >&2
    return 2
  fi
}

# github::fresh <file> <ttl>: the file exists and is younger than the duration (90, 5m, 1h, 1d)
github::fresh() {
  local ttl mtime
  [[ -f "$1" ]] && fzx::parse_duration "$2" ttl || return 1
  mtime="$(stat -c %Y -- "$1")" || return 1
  (($(date +%s) - mtime < ttl))
}

# github::api <path> [gh api args...]: gh api with the raw media type, so contents come back as they are
github::api() {
  command gh api -H 'Accept: application/vnd.github.raw' "$@"
}

# github::cached <file> <command...>: the file, written by the command when missing (only on success)
github::cached() {
  local file="$1" tmp
  shift
  if [[ ! -f "$file" ]]; then
    mkdir -p -- "${file%/*}" || return
    tmp="$file.$BASHPID"
    if ! "$@" > "$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
    mv -f -- "$tmp" "$file"
  fi
  printf '%s' "$file"
}

# github::blob <owner/name> <sha> <var>: the file holding a blob's contents (immutable: cached by sha)
github::blob() {
  local _f
  _f="$(github::cached "$FZX_CACHE_DIR/github/blob/$2" github::api "repos/$1/git/blobs/$2")" || return
  printf -v "$3" '%s' "$_f"
}

# --- recent searches

github::history_file() { printf '%s/github/history-%s' "$FZX_STATE_DIR" "$1"; }

# github::history_add <mode> <query>: to the top of the mode's recent searches, once, at most
# FZX_GITHUB_HISTORY_MAX (the query through the environment: awk -v would expand backslashes in it)
github::history_add() {
  local file tmp
  file="$(github::history_file "$1")"
  tmp="$file.$BASHPID"
  mkdir -p -- "${file%/*}" || return
  [[ -f "$file" ]] || : > "$file"
  Q="$2" awk -v max="${FZX_GITHUB_HISTORY_MAX:-200}" 'BEGIN { q = ENVIRON["Q"]; print q; n = 1 } $0 != q && n < max { print; n++ }' \
    "$file" > "$tmp" && mv -f -- "$tmp" "$file"
}

# github::_searched <mode> <query>: under fzx, the query the mode's list now shows
github::_searched() {
  declare -F fzx::state_set > /dev/null && [[ -n "${FZX_SESSION_DIR:-}" ]] || return 0
  fzx::state_set "github_query_$1" "$2"
}

# --- searches

# github::words <query> <array var>: the query's words; a "double-quoted phrase" is one word, unquoted
github::words() {
  local _q="$1" _w="" _in=0 _c _i
  local -n _out="$2"
  _out=()
  for ((_i = 0; _i < ${#_q}; _i++)); do
    _c="${_q:_i:1}"
    if [[ "$_c" == '"' ]]; then
      _in=$((!_in))
    elif [[ "$_c" == [[:space:]] ]] && ((!_in)); then
      [[ -n "$_w" ]] && _out+=("$_w")
      _w=""
    else
      _w+="$_c"
    fi
  done
  [[ -n "$_w" ]] && _out+=("$_w")
  return 0
}

# github::search_file <mode> <query> <var>
github::search_file() {
  local _key
  _key="$(printf '%s\n%s' "${FZX_GITHUB_LIMIT:-100}" "$2" | md5sum)"
  printf -v "$3" '%s/github/search/%s/%s.json' "$FZX_CACHE_DIR" "$1" "${_key%% *}"
}

# github::search <mode> <query> <var>: the search's JSON file, from the cache while it is fresh, else from gh
# (written only on success); on failure gh's message is in GITHUB_ERROR
github::search() {
  local _file _tmp _limit="${FZX_GITHUB_LIMIT:-100}" _kind=repos _fields="$GITHUB_REPO_FIELDS"
  declare -g GITHUB_ERROR=""
  github::search_file "$1" "$2" _file
  printf -v "$3" '%s' "$_file"
  github::fresh "$_file" "${FZX_GITHUB_CACHE_TTL:-1h}" && return 0
  [[ "$1" == code ]] && _kind=code _fields="$GITHUB_CODE_FIELDS" && ((_limit > 100)) && _limit=100
  mkdir -p -- "${_file%/*}" || return
  _tmp="$_file.$BASHPID"
  # one argument per word: gh quotes an argument holding spaces, which would make the qualifiers
  # (language:go stars:>100) plain text; "quoted phrases" stay one argument
  local _words=()
  github::words "$2" _words
  if ! command gh search "$_kind" --limit "$_limit" --json "$_fields" -- "${_words[@]}" > "$_tmp" 2> "$_tmp.err"; then
    GITHUB_ERROR="$(tr '\n' ' ' < "$_tmp.err")"
    rm -f -- "$_tmp" "$_tmp.err"
    return 1
  fi
  rm -f -- "$_tmp.err"
  mv -f -- "$_tmp" "$_file"
}

# github::language_icons: awk -v options with a Nerd Font icon per language (nerd style only)
github::language_icons() {
  [[ "${FZX_ICONS:-nerd}" == nerd ]] || return 0
  printf -- '-v\nlangs=%s\n' 'Lua= Go= Python= Rust= Shell= JavaScript= TypeScript= C= C++= Ruby= Vim_Script= Java= HTML= CSS= Nix= Elixir= Haskell= Swift= Kotlin= PHP= Markdown= Dockerfile='
}

# github::repo_rows <file>: a repository search's rows
github::repo_rows() {
  local o=$'\e['"${FZX_COLORS[github_owner]:-38;5;244}m" n=$'\e['"${FZX_COLORS[github_name]:-1;38;5;75}m"
  local s=$'\e['"${FZX_COLORS[github_star]:-38;5;220}m" c=$'\e['"${FZX_COLORS[github_count]:-38;5;250}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m' langs=()
  [[ -n "${NO_COLOR+x}" ]] && o="" n="" s="" c="" d="" r=""
  fzx::require icons
  fzx::icon_vars star fork issue archived repo
  mapfile -t langs < <(github::language_icons)
  command jq -r --arg file "$1" 'to_entries[] | .key as $i | .value |
    [.url, "repo", .fullName, $file, $i, .language // "", .stargazersCount, .forksCount, .openIssuesCount,
     (now - ((.pushedAt // .createdAt) | fromdateiso8601) | floor), .isArchived, (.description // "")]
    | map(tostring | gsub("[\t\r\n]+"; " ")) | join("\t")' -- "$1" |
    awk -F'\t' -v OFS='\t' "${FZX_ICON_VARS[@]}" "${langs[@]}" -v o="$o" -v n="$n" -v s="$s" -v c="$c" -v d="$d" -v r="$r" '
      BEGIN { k = split(langs, l, " "); for (i = 1; i <= k; i++) { split(l[i], kv, "="); gsub(/_/, " ", kv[1]); icon[kv[1]] = kv[2] } }
      function short(x) { x += 0; if (x >= 1e6) return sprintf("%.1fm", x / 1e6); if (x >= 1e3) return sprintf("%.1fk", x / 1e3); return x }
      function age(x) {
        if (x < 3600) return int(x / 60) "m"; if (x < 86400) return int(x / 3600) "h"
        if (x < 86400 * 60) return int(x / 86400) "d"; if (x < 86400 * 730) return int(x / 2592000) "mo"
        return int(x / 31536000) "y" }
      { split($3, on, "/"); width = length($3)
        lang = ($6 in icon) ? icon[$6] : icon_repo
        name = o on[1] "/" r n on[2] r
        if ($11 == "true") { name = name " " d icon_archived r; width += 2 }
        pad = 40 - width; if (pad < 1) pad = 1
        print $1, $2, $3, $4, $5, sprintf("%s%s%*s%s%s %6s%s  %s%s %5s  %s %4s%s  %4s  %s%s%s", (lang != "" ? lang " " : ""), name, pad, "",
          s, icon_star, short($7), r, c, icon_fork, short($8), icon_issue, short($9), r, age($10), d, $12, r) }'
}

# github::code_rows <file>: a code search's rows: the repository, the path and how many matches
github::code_rows() {
  local o=$'\e['"${FZX_COLORS[github_owner]:-38;5;244}m" n=$'\e['"${FZX_COLORS[github_name]:-1;38;5;75}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" b=$'\e[1m' r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && o="" n="" d="" b="" r=""
  command jq -r --arg file "$1" 'to_entries[] | .key as $i | .value |
    [.url, "code", .repository.nameWithOwner, $file, $i, .path, ([.textMatches[]?.matches[]?] | length)]
    | map(tostring | gsub("[\t\r\n]+"; " ")) | join("\t")' -- "$1" |
    awk -F'\t' -v OFS='\t' -v o="$o" -v n="$n" -v d="$d" -v b="$b" -v r="$r" '
      { split($3, on, "/"); pad = 32 - length($3); if (pad < 1) pad = 1
        dir = $6; base = $6; if (sub(/[^\/]*$/, "", dir)) base = substr($6, length(dir) + 1)
        print $1, $2, $3, $4, $5, sprintf("%s%s/%s%s%s%s%*s%s%s%s%s%s  %s%s%s", o, on[1], r, n, on[2], r, pad, "",
          d, dir, r, b, base, r, d, ($7 == 1 ? "1 match" : $7 " matches"), r) }'
}

# --- the tree mode

# github::resolve <owner/name> <ref> <var>: the commit sha a ref (branch, tag, sha, HEAD) points at
github::resolve() {
  local _sha
  [[ "$2" =~ ^[0-9a-f]{40}$ ]] && { printf -v "$3" '%s' "$2"; return 0; }
  _sha="$(command gh api "repos/$1/commits/$2" --jq .sha)" && [[ -n "$_sha" ]] || return 1
  printf -v "$3" '%s' "$_sha"
}

# github::tree_file <owner/name> <commit sha> <var>: the recursive tree of a commit, cached by its sha
github::tree_file() {
  local _f
  _f="$(github::cached "$FZX_CACHE_DIR/github/tree/${1/\//__}@$2.json" command gh api "repos/$1/git/trees/$2?recursive=1")" || return
  printf -v "$3" '%s' "$_f"
}

# github::tree_rows: the files and directories of GITHUB_REPO at GITHUB_REF (submodules left out); a tree
# GitHub truncated (over 100k entries) is logged
github::tree_rows() {
  local sha file d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && d="" r=""
  github::resolve "$GITHUB_REPO" "$GITHUB_REF" sha || { printf 'github: cannot resolve %s@%s\n' "$GITHUB_REPO" "$GITHUB_REF" >&2; return 1; }
  github::tree_file "$GITHUB_REPO" "$sha" file || { printf 'github: cannot list %s@%s\n' "$GITHUB_REPO" "$sha" >&2; return 1; }
  [[ "$(command jq -r .truncated -- "$file")" == true ]] && printf 'github: the tree of %s is truncated\n' "$GITHUB_REPO" >&2
  local rows
  rows="$(command jq -r --arg repo "$GITHUB_REPO" --arg sha "$sha" '.tree[] | select(.type != "commit") |
    [("https://github.com/" + $repo + "/" + (if .type == "tree" then "tree" else "blob" end) + "/" + $sha + "/" + .path),
     .type, $repo, (if .type == "blob" then "\(.sha):\(.size)" else "-" end), .path] | join("\t")' -- "$file")"
  [[ -n "$rows" ]] || return 0
  fzx::require pretty
  if fzx::pretty_on; then
    # prettypath decorates the paths (directories marked by a trailing "/"); joined back by path
    awk -F'\t' -v OFS='\t' 'NR == FNR { shown[$1] = $2; next }
      { key = $5 ($2 == "tree" ? "/" : ""); print $1, $2, $3, $4, $5, (key in shown ? shown[key] : "  " key) }' \
      <(awk -F'\t' '{ print $5 ($2 == "tree" ? "/" : "") }' <<< "$rows" | fzx::pretty) - <<< "$rows"
  else
    awk -F'\t' -v OFS='\t' -v d="$d" -v r="$r" '
      { dir = $5; base = $5; if (sub(/[^\/]*$/, "", dir)) base = substr($5, length(dir) + 1)
        print $1, $2, $3, $4, $5, d dir r base ($2 == "tree" ? "/" : "") }' <<< "$rows"
  fi
}

# --- URLs

# shellcheck disable=SC2034  # GH_*: read by the callers (actions.sh)
# github::parse_url <url>: GH_REPO (owner/name), GH_KIND (repo, blob or tree) and GH_REST (ref/path) from
# https://github.com/O/R[/blob|tree/REF/PATH], raw.githubusercontent.com/O/R/REF/PATH or O/R
github::parse_url() {
  # owners (users and organizations) hold letters, digits and dashes only, so "example.com/x" is no repository
  local u="$1" re='^([A-Za-z0-9-]+)/([A-Za-z0-9_.-]+)(/(blob|tree)/(.+))?$'
  declare -g GH_REPO="" GH_KIND=repo GH_REST=""
  u="${u%%[?#]*}"
  u="${u#http://}" u="${u#https://}" u="${u#www.}"
  if [[ "$u" == raw.githubusercontent.com/* ]]; then
    u="${u#raw.githubusercontent.com/}"
    [[ "$u" =~ ^([A-Za-z0-9-]+/[A-Za-z0-9_.-]+)/(.+)$ ]] || return 1
    GH_REPO="${BASH_REMATCH[1]}" GH_KIND=blob GH_REST="${BASH_REMATCH[2]}"
    return 0
  fi
  u="${u#github.com/}"
  u="${u%/}"
  [[ "$u" =~ $re ]] || return 1
  GH_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
  [[ -n "${BASH_REMATCH[3]}" ]] && GH_KIND="${BASH_REMATCH[4]}" GH_REST="${BASH_REMATCH[5]}"
  return 0
}

# shellcheck disable=SC2034  # GH_REF, GH_PATH: read by the callers
# github::split_ref <owner/name> <ref/path>: GH_REF and GH_PATH. A branch may hold slashes, so the shortest
# leading part that names a commit is the ref (a 40-hex sha or a single part needs no request)
github::split_ref() {
  local repo="$1" rest="$2" ref="" i parts=()
  IFS=/ read -ra parts <<< "$rest"
  declare -g GH_REF="${parts[0]}" GH_PATH=""
  if [[ ! "${parts[0]}" =~ ^[0-9a-f]{40}$ ]] && ((${#parts[@]} > 1)); then
    for ((i = 0; i < ${#parts[@]} - 1 && i < 4; i++)); do
      ref+="${ref:+/}${parts[i]}"
      if command gh api "repos/$repo/commits/$ref" --silent 2> /dev/null; then
        GH_REF="$ref"
        GH_PATH="${rest#"$ref"}" GH_PATH="${GH_PATH#/}"
        return 0
      fi
    done
  fi
  GH_PATH="${rest#"${parts[0]}"}" GH_PATH="${GH_PATH#/}"
}

# --- the list

# github::recent <mode>: the mode's recent searches
github::recent() {
  local file d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && d="" r=""
  file="$(github::history_file "$1")"
  [[ -f "$file" ]] || return 0
  awk -v mode="$1" -v d="$d" -v r="$r" '{ printf "%s\tsearch\t%s\t-\t-\t%s  recent%s  %s\n", $0, mode, d, r, $0 }' "$file"
}

# github::source [--repo OWNER/REPO] [--ref REF] [--]
github::source() {
  local mode="${FZX_MODE:-repos}" query file red=$'\e[31m' r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && red="" r=""
  case "$mode" in
    tree)
      github::args "$@" || return
      github::tree_rows
      return
      ;;
    repos | code) ;;
    *)
      printf 'github: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
  github::trim "${FZF_QUERY:-}" query
  if [[ -z "$query" ]]; then
    github::recent "$mode"
    github::_searched "$mode" ""
    return 0
  fi
  if ! github::search "$mode" "$query" file; then
    printf 'github: search failed: %s: %s\n' "$query" "$GITHUB_ERROR" >&2
    printf '%s\terror\t-\t-\t-\t%ssearch failed:%s %s\n' "$GITHUB_ERROR" "$red" "$r" "${GITHUB_ERROR:-$query}"
    github::_searched "$mode" "$query"
    return 1
  fi
  if [[ "$mode" == code ]]; then github::code_rows "$file"; else github::repo_rows "$file"; fi
  github::history_add "$mode" "$query"
  github::_searched "$mode" "$query"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" github
  github::source "$@"
}
