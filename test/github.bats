#!/usr/bin/env bats
# the github module against a stub gh (searches, the API's trees, blobs, contents and READMEs) and ghq

load test_helper

bats_require_minimum_version 1.5.0

GH_DIR="$(readlink -f "$BATS_TEST_DIRNAME/../modules/github")"
SHA=0123456789abcdef0123456789abcdef01234567

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none FZX_REPOS_LINKS_DIR="$BATS_TEST_TMPDIR/git"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  # gh: each call's args on a line of gh.calls (searches also in gh.search, one arg per line)
  cat > "$STUBS/gh" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/gh.calls"
args=("$@")
[[ "$1" == -H ]] && args=("${@:3}")
# api: the path is the first argument that is not an option (or an option's value)
if [[ "${args[0]}" == api ]]; then
  rest=() method=GET
  for ((i = 1; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
      -H | --jq) ((i++)) ;;
      -X) method="${args[i + 1]}"; ((i++)) ;;
      -i | --paginate | --slurp) ;;
      *) rest+=("${args[i]}") ;;
    esac
  done
  args=(api "${rest[@]}")
fi
case "${args[0]} ${args[1]}" in
  "repo fork") ;;
  "issue list" | "pr list")
    [[ -n "${STUB_GH_FAIL:-}" ]] && { echo "HTTP 404: Not Found" >&2; exit 1; }
    cat "$BATS_TEST_TMPDIR/${args[0]}s.json" ;;
  "issue view" | "pr view") cat "$BATS_TEST_TMPDIR/view-${args[0]}.json" ;;
  # checkout, develop, comment, close, reopen: where they ran
  "pr checkout" | "issue develop") echo "${args[*]} in $PWD" >> "$BATS_TEST_TMPDIR/item.calls" ;;
  "issue comment" | "pr comment" | "issue close" | "pr close" | "issue reopen" | "pr reopen")
    echo "${args[*]}" >> "$BATS_TEST_TMPDIR/item.calls" ;;
  # the menu summary asks about the repository here; the hub names one
  "repo view")
    if [[ "${args[2]}" != -* ]]; then
      [[ -n "${STUB_GH_FAIL:-}" ]] && { echo "HTTP 404: Not Found" >&2; exit 1; }
      cat "$BATS_TEST_TMPDIR/repo.json"
    else
      [[ -n "${STUB_GH_HERE:-}" ]] && echo "here: 2 PRs, 5 issues" || exit 1
    fi
    ;;
  "run list")
    [[ -n "${STUB_GH_RUNS_FAIL:-}" ]] && { echo "HTTP 403: Forbidden" >&2; exit 1; }
    cat "$BATS_TEST_TMPDIR/runs.json" ;;
  "run view")
    if [[ " ${args[*]} " == *" --json jobs "* ]]; then cat "$BATS_TEST_TMPDIR/jobs.json"
    elif [[ " ${args[*]} " == *" --json status,conclusion "* ]]; then
      # run 2 is still going, run 1 failed, the others succeeded
      case "${args[2]}" in 2) echo "in_progress " ;; 1) echo "completed failure" ;; *) echo "completed success" ;; esac
    else echo "log of ${args[*]:2}"; fi
    ;;
  "run rerun" | "run cancel" | "run watch") echo "${args[*]}" >> "$BATS_TEST_TMPDIR/run.calls" ;;
  "auth token") echo tok ;;
  "search repos" | "search code")
    printf '%s\n' "${args[@]}" > "$BATS_TEST_TMPDIR/gh.search"
    [[ -n "${STUB_GH_FAIL:-}" ]] && { echo "API rate limit exceeded" >&2; exit 1; }
    if [[ "${args[1]}" == repos ]]; then cat "$BATS_TEST_TMPDIR/repos.json"; else cat "$BATS_TEST_TMPDIR/code.json"; fi
    ;;
  "api rate_limit") echo "searches left: 29/30, code 9/10 (per minute)" ;;
  "api user") echo me ;;
  "api emojis") printf '{"cherry_blossom":"https://x/emoji/unicode/1f338.png?v8","atom":"https://x/emoji/atom.png?v8"}\n' ;;
  "api notifications?per_page=50") [[ " $* " == *" --jq "* ]] && echo "3 unread" ;;
  "api user/starred?per_page=1")
    printf 'HTTP/2.0 200 OK\nLink: <https://api.github.com/user/starred?per_page=1&page=2>; rel="next", <https://api.github.com/user/starred?per_page=1&page=14>; rel="last"\n\n[]\n' ;;
  "api user/repos?"* | "api users/"* | "api user/starred?per_page=100")
    [[ -n "${STUB_GH_FAIL:-}" ]] && { echo "HTTP 401: Bad credentials" >&2; exit 1; }
    cat "$BATS_TEST_TMPDIR/rest.json" ;;
  "api user/starred/"*) echo "$method ${args[1]}" >> "$BATS_TEST_TMPDIR/star.calls" ;;
  "api "*)
    path="${args[1]}"
    case "$path" in
      search/issues\?*) printf '%s\n' "$path" > "$BATS_TEST_TMPDIR/gh.issuesearch"; cat "$BATS_TEST_TMPDIR/search.json" ;;
      notifications\?all=*) cat "$BATS_TEST_TMPDIR/notifications.json" ;;
      notifications/threads/*) echo "$method $path" >> "$BATS_TEST_TMPDIR/read.calls" ;;
      repos/*/commits/*)
        ref="${path#*/commits/}"
        case "$ref" in
          main | HEAD | feat/x | "$SHA") ;;
          *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
        esac
        [[ " ${args[*]} " == *" --silent "* ]] || echo "0123456789abcdef0123456789abcdef01234567"
        ;;
      repos/*/git/trees/*) cat "$BATS_TEST_TMPDIR/tree.json" ;;
      repos/*/git/blobs/*) printf 'line one\nblob %s\n' "${path##*/}" ;;
      repos/*/readme) [[ "$path" == repos/o/noreadme/readme ]] && exit 1; printf '# The readme\n' ;;
      repos/*/contents/*)
        [[ "$path" == *missing* ]] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
        printf 'contents of %s\n' "${path#*/contents/}"
        ;;
    esac
    ;;
esac
STUB
  # ghq: list -p -e REPO prints where it is, plain list the repositories in $STUB_GHQ_HAVE; get makes it
  cat > "$STUBS/ghq" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/ghq.calls"
if [[ "$1" == list ]]; then
  if [[ " $* " == *" -e "* ]]; then echo "$BATS_TEST_TMPDIR/ghq/${*: -1}"; else printf '%s\n' ${STUB_GHQ_HAVE:-}; fi
fi
[[ "$1" == get ]] && mkdir -p "$BATS_TEST_TMPDIR/ghq/${*: -1}"
exit 0
STUB
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >> "$BATS_TEST_TMPDIR/open.calls"\n' > "$STUBS/xdg-open"
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
  cat > "$BATS_TEST_TMPDIR/repos.json" << 'JSON'
[{"fullName":"junegunn/fzf","url":"https://github.com/junegunn/fzf","description":"A command-line\tfuzzy finder","language":"Go",
  "stargazersCount":83816,"forksCount":4712,"openIssuesCount":334,"watchersCount":1,"pushedAt":"2026-10-25T10:00:00Z",
  "createdAt":"2013-10-23T00:00:00Z","isArchived":false,"isFork":false,"license":{"name":"MIT License"},"homepage":"",
  "defaultBranch":"master","visibility":"public","size":1},
 {"fullName":"o/noreadme","url":"https://github.com/o/noreadme","description":null,"language":null,"stargazersCount":5,
  "forksCount":0,"openIssuesCount":0,"watchersCount":0,"pushedAt":"2020-01-01T00:00:00Z","createdAt":"2020-01-01T00:00:00Z",
  "isArchived":true,"isFork":false,"license":null,"homepage":null,"defaultBranch":"main","visibility":"public","size":1}]
JSON
  cat > "$BATS_TEST_TMPDIR/code.json" << 'JSON'
[{"path":"lib/opts.sh","sha":"aaaa","url":"https://github.com/o/r/blob/0123456789abcdef0123456789abcdef01234567/lib/opts.sh",
  "repository":{"nameWithOwner":"o/r"},
  "textMatches":[{"fragment":"# fzx::bind adds a key\nfzx::bind() {","matches":[{"indices":[2,11],"text":"fzx::bind"},{"indices":[23,32],"text":"fzx::bind"}]}]},
 {"path":"README.md","sha":"bbbb","url":"https://github.com/o/r/blob/0123456789abcdef0123456789abcdef01234567/README.md",
  "repository":{"nameWithOwner":"o/r"},"textMatches":[{"fragment":"one","matches":[{"indices":[0,3],"text":"one"}]}]}]
JSON
  # gh api --paginate --slurp: an array of pages
  cat > "$BATS_TEST_TMPDIR/rest.json" << 'JSON'
[[{"full_name":"me/priv","html_url":"https://github.com/me/priv","description":"mine :cherry_blossom: and :atom:","language":"Shell",
   "stargazers_count":1,"forks_count":0,"open_issues_count":2,"watchers_count":1,"pushed_at":"2026-10-01T00:00:00Z",
   "created_at":"2020-01-01T00:00:00Z","archived":false,"fork":false,"private":true,"license":null,"homepage":null,
   "default_branch":"main","visibility":"private"}],
 [{"full_name":"me/forked","html_url":"https://github.com/me/forked","description":null,"language":null,
   "stargazers_count":0,"forks_count":0,"open_issues_count":0,"watchers_count":0,"pushed_at":"2026-09-01T00:00:00Z",
   "created_at":"2020-01-01T00:00:00Z","archived":false,"fork":true,"private":false,"license":{"name":"MIT License"},
   "homepage":"","default_branch":"master","visibility":"public"}]]
JSON
  # gh issue list, gh pr list, the search API, gh issue/pr view
  cat > "$BATS_TEST_TMPDIR/issues.json" << 'JSON'
[{"number":12,"title":"Crash\ton start","state":"OPEN","author":{"login":"alice"},"updatedAt":"2026-01-01T00:00:00Z",
  "labels":[{"name":"bug","color":"d73a4a"},{"name":"docs","color":"0075ca"}],"url":"https://github.com/o/r/issues/12"},
 {"number":3,"title":"Old","state":"CLOSED","author":null,"labels":[],"updatedAt":"2020-01-01T00:00:00Z",
  "url":"https://github.com/o/r/issues/3"}]
JSON
  cat > "$BATS_TEST_TMPDIR/prs.json" << 'JSON'
[{"number":40,"title":"Add x","state":"OPEN","isDraft":false,"author":{"login":"bob"},"labels":[],"updatedAt":"2026-01-01T00:00:00Z",
  "url":"https://github.com/o/r/pull/40","additions":10,"deletions":2,"reviewDecision":"APPROVED"},
 {"number":41,"title":"WIP","state":"OPEN","isDraft":true,"author":{"login":"bob"},"labels":[],"updatedAt":"2026-01-01T00:00:00Z",
  "url":"https://github.com/o/r/pull/41","additions":1,"deletions":0,"reviewDecision":"CHANGES_REQUESTED"},
 {"number":39,"title":"Done","state":"MERGED","isDraft":false,"author":{"login":"bob"},"labels":[],"updatedAt":"2026-01-01T00:00:00Z",
  "url":"https://github.com/o/r/pull/39","additions":5,"deletions":5,"reviewDecision":""}]
JSON
  cat > "$BATS_TEST_TMPDIR/search.json" << 'JSON'
{"total_count":2,"items":[
 {"html_url":"https://github.com/p/q/pull/7","number":7,"title":"Merged one","state":"closed","draft":false,
  "pull_request":{"merged_at":"2026-01-02T00:00:00Z"},"user":{"login":"me"},"labels":[{"name":"x","color":"zzz"}],
  "updated_at":"2026-01-02T00:00:00Z","repository_url":"https://api.github.com/repos/p/q"},
 {"html_url":"https://github.com/longowner/repository/issues/1","number":1,"title":"Asked","state":"open",
  "user":{"login":"carol"},"labels":[],"updated_at":"2026-01-01T00:00:00Z","repository_url":"https://api.github.com/repos/longowner/repository"},
 {"html_url":"https://github.com/someorganization/a-repository-with-a-long-name/issues/2","number":2,"title":"Long","state":"open",
  "user":{"login":"dan"},"labels":[],"updated_at":"2026-01-01T00:00:00Z",
  "repository_url":"https://api.github.com/repos/someorganization/a-repository-with-a-long-name"}]}
JSON
  # one notification per subject type; the API's urls, null for check suites and discussions
  cat > "$BATS_TEST_TMPDIR/notifications.json" << 'JSON'
[{"id":"101","unread":true,"reason":"review_requested","updated_at":"2026-01-01T00:00:00Z","repository":{"full_name":"o/r"},
  "subject":{"type":"PullRequest","title":"Add x","url":"https://api.github.com/repos/o/r/pulls/40"}},
 {"id":"102","unread":false,"reason":"mention","updated_at":"2026-01-01T00:00:00Z","repository":{"full_name":"p/q"},
  "subject":{"type":"Issue","title":"Bug\there","url":"https://api.github.com/repos/p/q/issues/5"}},
 {"id":"103","unread":true,"reason":"ci_activity","updated_at":"2026-01-01T00:00:00Z","repository":{"full_name":"o/r"},
  "subject":{"type":"CheckSuite","title":"CI failed","url":null}},
 {"id":"104","unread":true,"reason":"subscribed","updated_at":"2026-01-01T00:00:00Z","repository":{"full_name":"o/r"},
  "subject":{"type":"Release","title":"v1","url":"https://api.github.com/repos/o/r/releases/123"}},
 {"id":"105","unread":true,"reason":"author","updated_at":"2026-01-01T00:00:00Z","repository":{"full_name":"o/r"},
  "subject":{"type":"Commit","title":"Fix","url":"https://api.github.com/repos/o/r/commits/abc"}},
 {"id":"106","unread":true,"reason":"subscribed","updated_at":"2026-01-01T00:00:00Z","repository":{"full_name":"o/r"},
  "subject":{"type":"Discussion","title":"Ideas","url":null}}]
JSON
  cat > "$BATS_TEST_TMPDIR/view-issue.json" << 'JSON'
{"body":"The body","comments":[{"author":{"login":"carol"},"createdAt":"2026-01-01T10:00:00Z","body":"a comment"}]}
JSON
  cat > "$BATS_TEST_TMPDIR/view-pr.json" << 'JSON'
{"body":"","comments":[],"headRefName":"feat/x","baseRefName":"main","changedFiles":3,"additions":10,"deletions":2,
 "reviewDecision":"APPROVED","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","conclusion":"FAILURE","status":"COMPLETED"},
 {"__typename":"StatusContext","context":"lint","state":"PENDING"}]}
JSON
  # gh repo view O/R (the hub), gh run list, gh run view --json jobs
  cat > "$BATS_TEST_TMPDIR/repo.json" << 'JSON'
{"nameWithOwner":"o/r","description":"The r","url":"https://github.com/o/r","pushedAt":"2026-01-01T00:00:00Z",
 "defaultBranchRef":{"name":"main"},"issues":{"totalCount":5},"pullRequests":{"totalCount":2},"isArchived":false}
JSON
  cat > "$BATS_TEST_TMPDIR/runs.json" << 'JSON'
[{"databaseId":1,"number":30,"displayTitle":"Fix\tit","workflowName":"CI","headBranch":"main","event":"push","status":"completed",
  "conclusion":"failure","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:02:05Z","startedAt":"2026-01-01T00:00:00Z",
  "url":"https://github.com/o/r/actions/runs/1","attempt":1},
 {"databaseId":2,"number":31,"displayTitle":"Next","workflowName":"Release","headBranch":"v1","event":"workflow_dispatch",
  "status":"in_progress","conclusion":"","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z",
  "startedAt":"2026-01-01T00:00:00Z","url":"https://github.com/o/r/actions/runs/2","attempt":2},
 {"databaseId":3,"number":29,"displayTitle":"Old","workflowName":"CI","headBranch":"main","event":"push","status":"completed",
  "conclusion":"success","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:09Z","startedAt":"2026-01-01T00:00:00Z",
  "url":"https://github.com/o/r/actions/runs/3","attempt":1}]
JSON
  cat > "$BATS_TEST_TMPDIR/jobs.json" << 'JSON'
{"jobs":[{"name":"build","status":"completed","conclusion":"failure","startedAt":"2026-01-01T00:00:00Z","completedAt":"2026-01-01T00:01:30Z",
  "steps":[{"number":1,"name":"checkout","conclusion":"success"},{"number":2,"name":"test","conclusion":"failure"}]},
 {"name":"lint","status":"completed","conclusion":"success","startedAt":"2026-01-01T00:00:00Z","completedAt":"2026-01-01T00:00:07Z","steps":[]}]}
JSON
  cat > "$BATS_TEST_TMPDIR/tree.json" << 'JSON'
{"sha":"t","truncated":false,"tree":[
  {"path":"README.md","type":"blob","sha":"b1","size":10},
  {"path":"lib","type":"tree","sha":"t1"},
  {"path":"lib/a.sh","type":"blob","sha":"b2","size":20},
  {"path":"lib/sub","type":"tree","sha":"t2"},
  {"path":"lib/sub/b.sh","type":"blob","sha":"b3","size":5000000},
  {"path":"vendor/mod","type":"commit","sha":"c1"}]}
JSON
}

# source output without colors; keeps the source's exit status
src() {
  local rc
  FZX_MODE="$1" FZF_QUERY="$2" "$GH_DIR/source.sh" "${@:3}" > "$BATS_TEST_TMPDIR/src.out"
  rc=$?
  sed 's/\x1b\[[0-9;:]*m//g' "$BATS_TEST_TMPDIR/src.out"
  return "$rc"
}

searches() { grep -c '^search ' "$BATS_TEST_TMPDIR/gh.calls" 2> /dev/null || echo 0; }

@test "words: qualifiers stay separate arguments, a quoted phrase is one" {
  # || : the standalone guard, false when sourced, would stop the test
  source "$GH_DIR/source.sh" || :
  local w=()
  github::words '  fzf  language:go "vim plugin" stars:>100 ' w
  [ "${#w[@]}" -eq 4 ]
  [ "${w[0]}" = fzf ] && [ "${w[1]}" = language:go ] && [ "${w[2]}" = "vim plugin" ] && [ "${w[3]}" = "stars:>100" ]
  run src repos 'fzf language:go "vim plugin"'
  # gh would quote one argument holding spaces, which turns the qualifiers into text
  [ "$(tail -3 "$BATS_TEST_TMPDIR/gh.search" | tr '\n' '|')" = 'fzf|language:go|vim plugin|' ]
  grep -qx -- -- "$BATS_TEST_TMPDIR/gh.search"
}

@test "repos: one row per result, url first; cached per query; recent searches newest first" {
  run src repos "fzf"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "https://github.com/junegunn/fzf"$'\t'repo$'\t'junegunn/fzf$'\t'*$'\t'0$'\t'* ]]
  [[ "${lines[0]}" == *"junegunn/fzf "*"83.8k"*"4.7k"*"334"*"A command-line fuzzy finder" ]]
  [[ "${lines[1]}" == *$'\t'"  o/noreadme "* ]]
  run src repos "fzf"
  [ "$(searches)" -eq 1 ]
  FZX_GITHUB_CACHE_TTL=0 run src repos "other"
  run src repos ""
  [ "${lines[0]}" = "other"$'\t'search$'\t'repos$'\t'-$'\t'-$'\t'"  recent  other" ]
  [[ "${lines[1]}" == fzf$'\t'search* ]]
  # each mode keeps its own
  run src code ""
  [ -z "$output" ]
}

@test "code: repository, path and match count; a failed search shows gh's message and is not kept" {
  run src code "fzx::bind"
  [[ "${lines[0]}" == "https://github.com/o/r/blob/$SHA/lib/opts.sh"$'\t'code$'\t'o/r$'\t'* ]]
  [[ "${lines[0]}" == *"o/r "*"lib/opts.sh  2 matches" ]]
  [[ "${lines[1]}" == *"README.md  1 match" ]]
  STUB_GH_FAIL=1 run src code "broken"
  [ "$status" -eq 1 ]
  [[ "$output" == *$'\t'error$'\t'*"search failed: API rate limit exceeded"* ]]
  run src code ""
  [[ "$output" != *broken* ]]
}

@test "tree: files and directories at the resolved commit, sizes kept, submodules left out" {
  run src tree "" --repo o/r --
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  [ "${lines[0]}" = "https://github.com/o/r/blob/$SHA/README.md"$'\t'blob$'\t'o/r$'\t'b1:10$'\t'README.md$'\t'README.md ]
  [ "${lines[1]}" = "https://github.com/o/r/tree/$SHA/lib"$'\t'tree$'\t'o/r$'\t'-$'\t'lib$'\t'lib/ ]
  [[ "$output" != *vendor* ]]
  # the tree is cached by the commit: listing again only resolves the ref
  run src tree "" --repo o/r --
  [ "$(grep -c 'git/trees' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
  run src tree "" --repo nope
  [ "$status" -eq 2 ]
}

@test "urls: github.com, blob and tree paths, raw files; a branch with a slash" {
  # || : the standalone guard, false when sourced, would stop the test
  source "$GH_DIR/source.sh" || :
  github::parse_url https://github.com/o/r.git && [ "$GH_REPO" = o/r ] && [ "$GH_KIND" = repo ]
  github::parse_url o/r && [ "$GH_REPO" = o/r ]
  github::parse_url "https://github.com/o/r/blob/main/a/b.sh?plain=1#L3"
  [ "$GH_KIND" = blob ] && [ "$GH_REST" = main/a/b.sh ]
  github::parse_url https://raw.githubusercontent.com/o/r/main/x.md && [ "$GH_KIND" = blob ] && [ "$GH_REST" = main/x.md ]
  ! github::parse_url https://example.com/x
  github::split_ref o/r feat/x/lib/a.sh
  [ "$GH_REF" = feat/x ] && [ "$GH_PATH" = lib/a.sh ]
  github::split_ref o/r "$SHA/lib/a.sh"
  [ "$GH_REF" = "$SHA" ] && [ "$GH_PATH" = lib/a.sh ]
}

@test "preview: a repository's details and README, or none" {
  src repos fzx > /dev/null
  local file
  file="$(cut -f4 "$BATS_TEST_TMPDIR/src.out" | head -1)"
  FZX_PREVIEW_VIEWERS=markdown=cat run "$GH_DIR/preview.sh" https://github.com/junegunn/fzf repo junegunn/fzf "$file" 0
  [ "${lines[0]}" = junegunn/fzf ]
  [[ "$output" == *"license     MIT License"* && "$output" == *"# The readme"* ]]
  FZX_PREVIEW_VIEWERS=markdown=cat run "$GH_DIR/preview.sh" https://github.com/o/noreadme repo o/noreadme "$file" 1
  [[ "${lines[0]}" == "o/noreadme  archived" && "$output" == *"no README"* ]]
}

@test "preview: a code hit's fragments, then the file; a tree file, a large one, a directory" {
  src code x > /dev/null
  local file
  file="$(cut -f4 "$BATS_TEST_TMPDIR/src.out" | head -1)"
  run --separate-stderr bash -c '"$0" "$@" | sed "s/\x1b\[[0-9;:]*m//g"' "$GH_DIR/preview.sh" "https://github.com/o/r/blob/$SHA/lib/opts.sh" code o/r "$file" 0
  [ "${lines[0]}" = "o/r  lib/opts.sh" ]
  [[ "$output" == *"# fzx::bind adds a key"$'\n'"fzx::bind() {"* ]]
  [[ "$output" == *"blob aaaa"* ]]
  run bash -c '"$0" "$@" | sed "s/\x1b\[[0-9;:]*m//g"' "$GH_DIR/preview.sh" "https://github.com/o/r/blob/$SHA/lib/a.sh" blob o/r b2:20 lib/a.sh
  [[ "$output" == *"blob b2"* ]]
  run "$GH_DIR/preview.sh" "https://github.com/o/r/blob/$SHA/lib/sub/b.sh" blob o/r b3:5000000 lib/sub/b.sh
  [[ "$output" == *"5000000 bytes, not previewed"* ]]
  src tree "" --repo o/r -- > /dev/null
  run "$GH_DIR/preview.sh" "https://github.com/o/r/tree/$SHA/lib" tree o/r - lib
  [ "${lines[0]}" = lib/ ]
  [[ "$output" == *"a.sh  20 bytes"* && "$output" == *"sub/"* && "$output" != *b.sh* ]]
}

@test "fetch: a file, a directory under its name, existing files kept, a repository cloned, logged" {
  cd "$BATS_TEST_TMPDIR"
  run "$GH_DIR/actions.sh" fetch --dest out https://github.com/o/r/blob/main/lib/a.sh "https://github.com/o/r/tree/$SHA/lib"
  [ "$status" -eq 0 ]
  [ "$(cat out/a.sh)" = "contents of lib/a.sh?ref=main" ]
  [ "$(cat out/lib/sub/b.sh)" = $'line one\nblob b3' ]
  [ -f out/lib/a.sh ]
  run "$GH_DIR/actions.sh" fetch --dest out https://github.com/o/r/blob/main/lib/a.sh
  [[ "$output" == "exists, kept: $BATS_TEST_TMPDIR/out/a.sh" ]]
  [ "$(wc -l < "$FZX_STATE_DIR/github/fetched")" -eq 2 ]
  run "$GH_DIR/actions.sh" fetch https://github.com/o/r
  [ "$(head -1 "$BATS_TEST_TMPDIR/ghq.calls")" = "get -- github.com/o/r" ]
  [ "$(readlink "$FZX_REPOS_LINKS_DIR/r")" = "$BATS_TEST_TMPDIR/ghq/github.com/o/r" ]
  run "$GH_DIR/actions.sh" fetch --dest out https://github.com/o/r/blob/main/missing.sh https://example.com/x
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot fetch"* && "$output" == *"not a GitHub URL"* ]]
}

@test "actions: rows without a URL are skipped; the browser opens urls; web opens the search" {
  load_libs log
  source "$GH_DIR/actions.sh" || :
  github::action browser --repo o/r -- recentquery https://github.com/o/r
  [ "$(cat "$BATS_TEST_TMPDIR/open.calls")" = https://github.com/o/r ]
  FZX_MODE=code FZF_QUERY='a b' github::action web --
  [ "$(tail -1 "$BATS_TEST_TMPDIR/open.calls")" = "https://github.com/search?type=code&q=a%20b" ]
}

@test "under fzx: enter searches a new query, reruns a recent one, lists recents again, accepts a row" {
  load_libs log session
  fzx::session_create github "$GH_DIR"
  fzx::state_set mode repos
  fzx::state_set github_query_repos ""
  FZF_QUERY="fzf" run "$FZX" _cb transform enter -- https://github.com/o/r repo o/r
  [[ "$output" == *"reload("*"_cb source)" ]]
  FZF_QUERY="fzf" run "$FZX" _cb source
  [ "$(cat "$FZX_SESSION_DIR/state/github_query_repos")" = fzf ]
  FZF_QUERY="fzf" run "$FZX" _cb transform enter -- https://github.com/o/r repo o/r
  [ "$output" = accept ]
  FZF_QUERY="" run "$FZX" _cb transform enter -- https://github.com/o/r repo o/r
  [[ "$output" == *"reload("* ]]
  FZF_QUERY="" run "$FZX" _cb source
  FZF_QUERY="" run "$FZX" _cb transform enter -- "vim plugin" search repos
  [[ "$output" == "change-query(vim plugin)+"*"reload("* ]]
}

@test "under fzx: ctrl-o opens a repository's files, a code hit's at its commit" {
  load_libs log session
  fzx::session_create github "$GH_DIR"
  run "$FZX" _cb transform into -- https://github.com/o/r repo o/r
  [[ "$output" == "become:"* ]]
  local child="${output##*--resume }" args=()
  child="${child%% *}"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${args[*]}" = "--repo o/r" ]
  run "$FZX" _cb transform into -- "https://github.com/o/r/blob/$SHA/lib/a.sh" code o/r
  child="${output##*--resume }" child="${child%% *}"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${args[*]}" = "--repo o/r --ref $SHA" ]
  run "$FZX" _cb transform into -- recent search repos
  [ -z "$output" ]
}

@test "options: searches do not filter and enter is the transform; tree filters; standalone waits for a pause" {
  stub_fzf
  run "$FZX" -m github
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --disabled "* ]]
  [[ "$(fzf_bind enter)" == "enter:transform:$FZX _cb transform enter -- {1} {2} {3} {4}" ]]
  [[ "$(fzf_bind ctrl-o)" == *"_cb transform into -- {1} {2} {3} {4}" ]]
  [[ "$(fzf_bind alt-d)" == *"_cb action fetch -- {+1}"* ]]
  run "$FZX" -m github:tree --repo o/r
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --disabled "* && " ${FZF_ARGS[*]} " == *" --header=o/r "* ]]
  run "$GH_DIR/module.sh"
  [[ "$(fzf_bind change)" == "change:reload:sleep 1; $GH_DIR/source.sh" ]]
}

@test "menu: applicable with gh logged in; the summary is the searches left" {
  load_libs log config menu
  fzx::menu_entries github "$GH_DIR"
  github::applicable github
  run github::summary github
  [ "$status" -eq 0 ]
}

@test "zsh: ghs and ghsc open the modes with the words as the query; ghfetch fetches; FZX_ZSH_NO_GITHUB" {
  command -v zsh > /dev/null || skip "zsh not installed"
  local zint
  zint="$(readlink -f "$BATS_TEST_DIRNAME/../shell/fzx.zsh")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$BATS_TEST_TMPDIR/fzx.args"\n' > "$STUBS/fzx-stub"
  chmod +x "$STUBS/fzx-stub"
  FZX_ZSH_BIN=fzx-stub FZX_ZSH_NO_BIND=1 zsh -f -c "source '$zint'; ghs fzf language:go"
  [ "$(cat "$BATS_TEST_TMPDIR/fzx.args" | tr '\n' '|')" = "-m|github|--query|fzf language:go|" ]
  FZX_ZSH_BIN=fzx-stub FZX_ZSH_NO_BIND=1 zsh -f -c "source '$zint'; ghsc"
  [ "$(cat "$BATS_TEST_TMPDIR/fzx.args" | tr '\n' '|')" = "-m|github:code|" ]
  cd "$BATS_TEST_TMPDIR"
  FZX_ZSH_NO_BIND=1 zsh -f -c "source '$zint'; ghfetch https://github.com/o/r/blob/main/x.sh"
  [ "$(cat x.sh)" = "contents of x.sh?ref=main" ]
  run zsh -f -c "FZX_ZSH_NO_GITHUB=1 FZX_ZSH_NO_BIND=1; source '$zint'; whence ghs"
  [ "$status" -ne 0 ]
}

@test "mine and starred: every page, in a search's fields; --owner; cached; a failure is shown" {
  run src mine ""
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == https://github.com/me/priv$'\t'repo$'\t'me/priv$'\t'*/github/list/mine.json$'\t'0$'\t'* ]]
  [[ "${lines[1]}" == *$'\t'1$'\t'*"me/forked "* ]]
  grep -q 'user/repos?per_page=100&affiliation=owner&sort=pushed' "$BATS_TEST_TMPDIR/gh.calls"
  [ "$(command jq -r '.[0].isPrivate, .[1].isFork, .[1].license.name' "$FZX_CACHE_DIR/github/list/mine.json" | tr '\n' ' ')" = "true true MIT License " ]
  run src mine ""
  [ "$(grep -c 'user/repos' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
  run src mine "" --owner someone
  grep -q 'users/someone/repos?per_page=100&sort=pushed' "$BATS_TEST_TMPDIR/gh.calls"
  [ -f "$FZX_CACHE_DIR/github/list/mine-someone.json" ]
  run src starred ""
  [ "${#lines[@]}" -eq 2 ]
  # sorts: as listed (mine: last push, its age underlined), most stars, or by name (colors on for these)
  unset NO_COLOR
  FZX_SORT=listed run src mine ""
  [[ "${lines[0]}" == *me/priv* ]] && grep -q $'\e\[4m[0-9]*[a-z]*\e\[0m' "$BATS_TEST_TMPDIR/src.out"
  FZX_SORT=name run src mine ""
  [[ "${lines[0]}" == *me/forked* && "${lines[1]}" == *me/priv* ]] && grep -q $'\e\[4mforked' "$BATS_TEST_TMPDIR/src.out"
  FZX_SORT=stars run src mine ""
  [[ "${lines[0]}" == *me/priv* ]] && grep -q $'\e\[4m1\e\[0m' "$BATS_TEST_TMPDIR/src.out"
  STUB_GH_FAIL=1 FZX_GITHUB_CACHE_TTL=0 run src starred ""
  [ "$status" -eq 1 ]
  [[ "$output" == *$'\t'error$'\t'*"cannot list starred: HTTP 401: Bad credentials"* ]]
}

@test "toggles: private or public only, sources or forks only; both of a pair, everything" {
  local t
  run src mine ""
  for t in "private:me/priv" "public:me/forked" "sources:me/priv" "forks:me/forked"; do
    FZX_TOGGLES="${t%%:*}" run src mine ""
    [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == "https://github.com/${t#*:}"$'\t'* ]]
  done
  FZX_TOGGLES="private public forks sources" run src mine ""
  [ "${#lines[@]}" -eq 2 ]
  FZX_TOGGLES="private forks" run src mine ""
  [ -z "$output" ]
}

@test "emoji: GitHub's shortcodes as their characters, in rows and the preview; its own ones kept" {
  run src mine ""
  [[ "${lines[0]}" == *"mine 🌸 and :atom:" ]]
  FZX_PREVIEW_VIEWERS=markdown=cat run "$GH_DIR/preview.sh" https://github.com/me/priv repo me/priv "$FZX_CACHE_DIR/github/list/mine.json" 0
  [[ "$output" == *"mine 🌸 and :atom:"* && "$output" == *"visibility  private"* ]]
  [ "$(grep -c '^api emojis' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
}

@test "code: qualifiers alone ask for words and spend no search; fzx::bind is a word" {
  run src code "repo:o/r "
  [[ "$output" == *$'\t'error$'\t'*"type the words to look for with repo:o/r, enter searches" ]]
  [ "$(searches)" -eq 0 ]
  run src code "repo:o/r fzx::bind"
  [ "$(searches)" -eq 1 ]
}

@test "search: an empty answer is shown but asked again next time" {
  printf '[]\n' > "$BATS_TEST_TMPDIR/repos.json"
  run src repos "nothing"
  [ -z "$output" ]
  run src repos "nothing"
  [ "$(searches)" -eq 2 ]
}

@test "actions: star, unstar in starred (the stars list fetched again), fork, settings" {
  load_libs log
  source "$GH_DIR/actions.sh" || :
  src starred "" > /dev/null
  FZX_MODE=repos github::action star -- https://github.com/o/r "https://github.com/o/r/blob/$SHA/x" https://github.com/p/q
  [ "$(cat "$BATS_TEST_TMPDIR/star.calls" | tr '\n' '|')" = "PUT user/starred/o/r|PUT user/starred/p/q|" ]
  [ ! -f "$FZX_CACHE_DIR/github/list/starred.json" ]
  FZX_MODE=starred github::action star -- https://github.com/o/r
  [ "$(tail -1 "$BATS_TEST_TMPDIR/star.calls")" = "DELETE user/starred/o/r" ]
  github::action fork -- https://github.com/o/r
  grep -qx 'repo fork o/r --clone=false' "$BATS_TEST_TMPDIR/gh.calls"
  github::action settings -- "https://github.com/o/r/tree/$SHA/lib"
  [ "$(tail -1 "$BATS_TEST_TMPDIR/open.calls")" = https://github.com/o/r/settings ]
}

@test "under fzx: mine accepts on enter; ctrl-t filters and back; enter while filtering" {
  load_libs log session
  fzx::session_create github "$GH_DIR"
  fzx::state_set mode mine
  FZF_QUERY="x" run "$FZX" _cb transform enter -- https://github.com/me/priv repo me/priv
  [ "$output" = accept ]
  run "$FZX" _cb transform filter -- https://github.com/me/priv repo me/priv
  [ -z "$output" ]
  fzx::state_set mode code
  fzx::state_set github_query_code "needle"
  run "$FZX" _cb transform filter -- u code o/r
  # (the header holds parentheses: another delimiter pair)
  [[ "$output" == "enable-search+change-query()+change-header[filtering the results of: needle (ctrl-t searches again)]" ]]
  [ "$(cat "$FZX_SESSION_DIR/state/github_filter_code")" = 1 ]
  FZF_QUERY="lib" run "$FZX" _cb transform enter -- u code o/r
  [ "$output" = accept ]
  FZF_QUERY="old" run "$FZX" _cb transform enter -- "old query" search code
  [[ "$output" == "disable-search+change-query(old query)+change-header["*"]+"*"reload("*"_cb source)" ]]
  [ -z "$(cat "$FZX_SESSION_DIR/state/github_filter_code")" ]
  run "$FZX" _cb transform filter -- u code o/r
  run "$FZX" _cb transform filter -- u code o/r
  [[ "$output" == "disable-search+change-query(needle)+change-header["*"reload("*"_cb load)" ]]
}

@test "under fzx: alt-p narrows a code search to the repository, or opens code mode on it" {
  load_libs log session
  fzx::session_create github "$GH_DIR"
  fzx::state_set mode code
  FZF_QUERY="needle repo:x/y  lang:sh" run "$FZX" _cb transform narrow -- u code o/r
  [[ "$output" == "disable-search+change-query(needle lang:sh repo:o/r)+change-header["*"reload("* ]]
  fzx::state_set mode repos
  # no modes recorded (a launch records them): nothing to switch to, the query stays
  FZF_QUERY="fzf" run "$FZX" _cb transform narrow -- https://github.com/o/r repo o/r
  [ -z "$output" ]
  printf '%s\0' repos code mine starred > "$FZX_SESSION_DIR/meta/modes"
  FZF_QUERY="fzf" run "$FZX" _cb transform narrow -- https://github.com/o/r repo o/r
  [[ "$output" == "change-query(repo:o/r )+change-border-label("*"reload("* ]]
  [ "$(cat "$FZX_SESSION_DIR/state/mode")" = code ]
  run "$FZX" _cb transform narrow -- recent search repos
  [ -z "$output" ]
}

@test "f2: the module's debug section lists every rate limit; modules without one get none" {
  load_libs log session
  fzx::session_create github "$GH_DIR"
  run bash -c '"$0" _cb debug | sed "s/\x1b\[[0-9;:]*m//g"' "$FZX"
  [[ "$output" == *"github (github::debug)"$'\n'"  searches left: 29/30"* ]]
  fzx::session_create ps "$FZX_REPO/modules/ps"
  run bash -c '"$0" _cb debug | sed "s/\x1b\[[0-9;:]*m//g"' "$FZX"
  [[ "$output" == *"state/"* && "$output" != *"::debug)"* ]]
  ! grep -q "not defined" "$LOG"
}

@test "menu: seven entries; summaries for repos (parts in parallel), code, mine (from its list) and starred" {
  load_libs log config menu
  cat > "$STUBS/curl" << 'STUB'
#!/usr/bin/env bash
echo '{"status":{"indicator":"minor","description":"Partial outage"}}'
STUB
  chmod +x "$STUBS/curl"
  fzx::menu_entries github "$GH_DIR"
  [ "${FZX_ENTRY_TARGETS[*]}" = "github github:code github:mine github:starred github:issues github:prs github:notifications" ]
  STUB_GH_HERE=1 run github::summary github
  [ "$output" = "GitHub: Partial outage · here: 2 PRs, 5 issues · 3 unread · searches left: 29/30, code 9/10 (per minute)" ]
  run github::summary github:starred
  [ "$output" = "14 stars" ]
  src mine "" > /dev/null
  run github::summary github:mine
  [ "$output" = "2 repositories, 1 private" ]
}

@test "repository rows: cloned ones marked; the missing toggle keeps the others" {
  STUB_GHQ_HAVE="github.com/Me/Priv" run src mine ""
  [[ "${lines[0]}" == *$'\t'"+ me/priv "* && "${lines[1]}" == *$'\t'"  me/forked "* ]]
  STUB_GHQ_HAVE="github.com/me/priv" FZX_TOGGLES=missing run src mine ""
  [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == https://github.com/me/forked$'\t'* ]]
}

@test "clone: yours over ssh, others over https (FZX_GITHUB_CLONE_SSH), each linked; other hosts as given" {
  cd "$BATS_TEST_TMPDIR"
  run "$GH_DIR/actions.sh" clone me/mine https://github.com/o/theirs
  [ "$status" -eq 0 ]
  grep -qx 'get -p -- github.com/me/mine' ghq.calls
  grep -qx 'get -- github.com/o/theirs' ghq.calls
  [ -L git/mine ] && [ -L git/theirs ]
  FZX_GITHUB_CLONE_SSH=always run "$GH_DIR/actions.sh" clone o/again
  grep -qx 'get -p -- github.com/o/again' ghq.calls
  run "$GH_DIR/actions.sh" clone
  [ "$status" -eq 2 ]
}

@test "clone-missing: your repositories not cloned yet, a dry run first" {
  STUB_GHQ_HAVE="github.com/me/priv" run "$GH_DIR/actions.sh" clone-missing --dry-run
  [ "${lines[0]}" = "would clone me/forked" ]
  [ "${lines[-1]}" = "dry run: 1 of your repositories to clone" ]
  ! grep -q '^get' "$BATS_TEST_TMPDIR/ghq.calls"
  STUB_GHQ_HAVE="github.com/me/priv" run "$GH_DIR/actions.sh" clone-missing
  grep -qx 'get -p -- github.com/me/forked' "$BATS_TEST_TMPDIR/ghq.calls"
  [ "${lines[-1]}" = "1 of your repositories cloned" ]
}

# a clone of o/r (its origin over ssh) to run the issues and prs modes in
clone_here() {
  HERE="$BATS_TEST_TMPDIR/here"
  mkdir -p "$HERE"
  git -C "$HERE" init -q
  git -C "$HERE" remote add origin "${1:-git@github.com:o/r.git}"
  cd "$HERE"
}

@test "issues: the repository here (origin over ssh or https), --repo; the closed toggle; cached" {
  clone_here
  run src issues ""
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  IFS=$'\t' read -r url kind repo file index display <<< "${lines[0]}"
  [ "$url $kind $repo $index" = "https://github.com/o/r/issues/12 issue o/r 0" ]
  [ "$file" = "$FZX_CACHE_DIR/github/issues/issues-o__r-open.json" ]
  # no repository column for one repository's list; tabs in titles become spaces; no author: ghost
  [[ "$display" == "O #12   Crash on start [bug] [docs] alice "*[0-9]* ]]
  [[ "${lines[1]}" == *$'\t'"C #3    Old ghost "*y ]]
  grep -qx 'issue list -R o/r --state open -L 100 --json number,title,state,author,labels,updatedAt,url' "$BATS_TEST_TMPDIR/gh.calls"
  src issues "" > /dev/null
  [ "$(grep -c '^issue list' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
  FZX_TOGGLES=closed src issues "" > /dev/null
  grep -q '^issue list -R o/r --state all ' "$BATS_TEST_TMPDIR/gh.calls"
  git remote set-url origin https://github.com/o/other.git
  src issues "" > /dev/null
  grep -q '^issue list -R o/other ' "$BATS_TEST_TMPDIR/gh.calls"
  src issues "" --repo x/y > /dev/null
  grep -q '^issue list -R x/y ' "$BATS_TEST_TMPDIR/gh.calls"
  STUB_GH_FAIL=1 run src issues "" --repo x/z
  [ "$status" -eq 1 ]
  [[ "$output" == *"HTTP 404: Not Found "$'\t'"error"$'\t'*"cannot list issues: HTTP 404: Not Found"* ]]
}

@test "prs: draft, merged, the size and the review decision" {
  clone_here
  run src prs ""
  [[ "${lines[0]}" == *$'\t'"O #40   Add x bob "*" +10 -2 approved" ]]
  [[ "${lines[1]}" == *$'\t'"D #41   WIP bob "*" +1 -0 changes requested" ]]
  [[ "${lines[2]}" == "https://github.com/o/r/pull/39"$'\t'"pr"*$'\t'"M #39   Done bob "*" +5 -5" ]]
  grep -q '^pr list -R o/r --state open -L 100 --json number,title,state,isDraft,author,labels,updatedAt,url,additions,deletions,reviewDecision$' \
    "$BATS_TEST_TMPDIR/gh.calls"
}

@test "issues and prs involving you: outside a GitHub repository or with everywhere; merged from the search" {
  cd "$BATS_TEST_TMPDIR"
  run src prs ""
  [ "$status" -eq 0 ]
  # the repository column is as wide as the widest, at most 32 (longer names cut); bad label colors as text
  [[ "${lines[0]}" == "https://github.com/p/q/pull/7"$'\t'"pr"$'\t'"p/q"*$'\t'"M p/q                              #7    Merged one [x] me "* ]]
  [[ "${lines[1]}" == *$'\t'"O longowner/repository             #1    Asked carol "* ]]
  [[ "${lines[2]}" == *$'\t'"O someorganization/a-repository-w… #2    Long dan "* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/gh.issuesearch")" = "search/issues?q=involves%3Ame%20is%3Apr%20state%3Aopen&sort=updated&order=desc&per_page=100" ]
  [ -f "$FZX_CACHE_DIR/github/issues/prs-involved-open.json" ]
  clone_here
  FZX_TOGGLES="everywhere closed" src issues "" > /dev/null
  [ "$(cat "$BATS_TEST_TMPDIR/gh.issuesearch")" = "search/issues?q=involves%3Ame%20is%3Aissue&sort=updated&order=desc&per_page=100" ]
  ! grep -q '^issue list' "$BATS_TEST_TMPDIR/gh.calls"
}

@test "issue rows: colored state icons and label chips in their GitHub colors" {
  clone_here
  env -u NO_COLOR FZX_ICONS=nerd FZX_MODE=issues "$GH_DIR/source.sh" > "$BATS_TEST_TMPDIR/out"
  # bug's d73a4a is dark: white text; the open icon in the open color
  grep -qF $'\e[48;2;215;58;74;97m bug \e[0m' "$BATS_TEST_TMPDIR/out"
  grep -qF $'\e[38;5;114m\e[0m' "$BATS_TEST_TMPDIR/out"
}

@test "preview: an issue's details, body and comments; a pull request's branches, size and checks" {
  clone_here
  src issues "" > /dev/null
  src prs "" > /dev/null
  run env FZX_PREVIEW_VIEWERS=markdown=cat "$GH_DIR/preview.sh" https://github.com/o/r/issues/12 issue o/r \
    "$FZX_CACHE_DIR/github/issues/issues-o__r-open.json" 0
  [ "${lines[0]}" = "o/r #12  open" ]
  [ "${lines[1]}" = "Crash	on start" ]
  # (lines leaves out empty ones)
  [ "${lines[2]}" = "author  alice" ]
  [ "${lines[4]}" = "labels  bug, docs" ]
  [[ "$output" == *$'The body\n\n---\n\n**carol** 2026-01-01\n\na comment' ]]
  run env FZX_PREVIEW_VIEWERS=markdown=cat "$GH_DIR/preview.sh" https://github.com/o/r/pull/40 pr o/r \
    "$FZX_CACHE_DIR/github/issues/prs-o__r-open.json" 0
  [[ "$output" == *$'branch  feat/x -> main\nchanges 3 files, +10 -2\nreview  approved\n\nchecks\n  failure  ci\n  pending  lint'* ]]
  [[ "$output" == *"*no description*" ]]
  # cached by the last update: viewed once
  # glow gets no stdin (it reads one that is not a terminal, file argument or not, and a pipe never ends)
  printf '#!/usr/bin/env bash\nIFS= read -r x && echo "stdin: $x"\necho rendered\n' > "$STUBS/glow"
  chmod +x "$STUBS/glow"
  run bash -c 'echo leak | FZX_PREVIEW_VIEWERS=markdown=glow "$0" https://github.com/o/r/pull/40 pr o/r "$1" 0' \
    "$GH_DIR/preview.sh" "$FZX_CACHE_DIR/github/issues/prs-o__r-open.json"
  [[ "$output" == *rendered && "$output" != *"stdin: leak"* ]]
  [ "$(grep -c '^pr view' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
}

@test "actions: checkout here or in the ghq clone, refused elsewhere; comment, close, reopen drop the lists" {
  load_libs log
  source "$GH_DIR/actions.sh" || :
  clone_here
  src issues "" > /dev/null
  github::action checkout -- https://github.com/o/r/pull/40
  [ "$(tail -1 "$BATS_TEST_TMPDIR/item.calls")" = "pr checkout 40 in $HERE" ]
  github::action checkout -- https://github.com/o/r/issues/12
  [ "$(tail -1 "$BATS_TEST_TMPDIR/item.calls")" = "issue develop 12 --checkout in $HERE" ]
  # another repository: its ghq clone
  mkdir -p "$BATS_TEST_TMPDIR/ghq/github.com/p/q"
  github::action checkout -- https://github.com/p/q/pull/7
  [ "$(tail -1 "$BATS_TEST_TMPDIR/item.calls")" = "pr checkout 7 in $BATS_TEST_TMPDIR/ghq/github.com/p/q" ]
  run github::action checkout -- https://github.com/n/c/pull/1 < /dev/null
  [[ "$output" == *"n/c is not cloned here"* ]]
  github::action comment -- https://github.com/o/r/issues/12
  [ "$(tail -1 "$BATS_TEST_TMPDIR/item.calls")" = "issue comment https://github.com/o/r/issues/12 --editor" ]
  [ ! -d "$FZX_CACHE_DIR/github/issues" ]
  github::action close -- https://github.com/o/r/issues/12 https://github.com/o/r/pull/40 https://github.com/o/r
  [ "$(tail -2 "$BATS_TEST_TMPDIR/item.calls" | tr '\n' '|')" = "issue close https://github.com/o/r/issues/12|pr close https://github.com/o/r/pull/40|" ]
  github::action reopen -- https://github.com/o/r/pull/40
  [ "$(tail -1 "$BATS_TEST_TMPDIR/item.calls")" = "pr reopen https://github.com/o/r/pull/40" ]
}

@test "under fzx: issues and prs accept on enter; the header names the repository and the toggle's key" {
  load_libs log session
  fzx::session_create github "$GH_DIR"
  fzx::state_set mode issues
  FZF_QUERY="x" run "$FZX" _cb transform enter -- https://github.com/o/r/issues/12 issue o/r
  [ "$output" = accept ]
  stub_fzf
  clone_here
  run "$FZX" -m github:prs
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=pull requests of o/r, last updated first (alt-7: involving you anywhere) "* ]]
  [[ "$(fzf_bind alt-k)" == *"_cb action checkout -- {+1}"* ]]
  cd "$BATS_TEST_TMPDIR"
  run "$FZX" -m github:issues
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=issues involving you, last updated first "* ]]
}

@test "menu: issues and prs summaries from the last list only" {
  load_libs log config menu
  fzx::menu_entries github "$GH_DIR"
  clone_here
  run github::summary github:issues
  [ -z "$output" ]
  src issues "" > /dev/null
  run github::summary github:issues
  [ "$output" = "2 open, o/r" ]
}

@test "notifications: unread ones, a page per subject; the read toggle; read marks the selected threads" {
  run src notifications ""
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 6 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' '|')" = "https://github.com/o/r/pull/40|https://github.com/p/q/issues/5|https://github.com/o/r/actions|https://github.com/o/r/releases|https://github.com/o/r/commit/abc|https://github.com/o/r/discussions|" ]
  [[ "${lines[0]}" == *$'\t'"notification"$'\t'"o/r"$'\t'"$FZX_CACHE_DIR/github/issues/notifications-unread.json"$'\t'"0"$'\t'"● P o/r Add x review requested "* ]]
  [[ "${lines[1]}" == *$'\t'"  I p/q Bug here mention "* ]]
  [[ "${lines[2]}" == *$'\t'"● A o/r CI failed ci activity "* ]]
  grep -qx 'api notifications?all=false&per_page=50' "$BATS_TEST_TMPDIR/gh.calls"
  src notifications "" > /dev/null
  [ "$(grep -c '^api notifications?all' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
  FZX_TOGGLES=read src notifications "" > /dev/null
  grep -qx 'api notifications?all=true&per_page=50' "$BATS_TEST_TMPDIR/gh.calls"
  load_libs log
  source "$GH_DIR/actions.sh" || :
  FZX_MODE=notifications github::action read -- https://github.com/o/r/pull/40 https://github.com/o/r/actions
  [ "$(cat "$BATS_TEST_TMPDIR/read.calls" | tr '\n' '|')" = "PATCH notifications/threads/101|PATCH notifications/threads/103|" ]
  [ ! -d "$FZX_CACHE_DIR/github/issues" ]
}

@test "preview: a notification; an issue's or pull request's details below it" {
  src notifications "" > /dev/null
  local f="$FZX_CACHE_DIR/github/issues/notifications-unread.json"
  run env FZX_PREVIEW_VIEWERS=markdown=cat "$GH_DIR/preview.sh" https://github.com/o/r/pull/40 notification o/r "$f" 0
  [ "${lines[0]}" = "o/r  pull request  unread" ]
  [ "${lines[2]}" = "reason  review requested" ]
  [[ "$output" == *"branch  feat/x -> main"*"*no description*" ]]
  run env FZX_PREVIEW_VIEWERS=markdown=cat "$GH_DIR/preview.sh" https://github.com/o/r/actions notification o/r "$f" 2
  [ "${lines[0]}" = "o/r  check suite  unread" ]
  [ "${lines[-1]}" = "url     https://github.com/o/r/actions" ]
  ! grep -q '^issue view\|^pr view.*actions' "$BATS_TEST_TMPDIR/gh.calls"
}

@test "under fzx: notifications accept on enter; header and keys; menu summary from the last list" {
  load_libs log session
  fzx::session_create github "$GH_DIR"
  fzx::state_set mode notifications
  FZF_QUERY="x" run "$FZX" _cb transform enter -- https://github.com/o/r/pull/40 notification o/r
  [ "$output" = accept ]
  stub_fzf
  run "$FZX" -m github:notifications
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=your unread notifications, latest first (alt-8: read ones too) "* ]]
  [[ "$(fzf_bind alt-u)" == *"_cb action read -- {+1}"* ]]
  load_libs config menu
  fzx::menu_entries github "$GH_DIR"
  run github::summary github:notifications
  [ -z "$output" ]
  src notifications "" > /dev/null
  run github::summary github:notifications
  [ "$output" = "6 unread" ]
}

@test "repo: the hub's rows, files, issues, prs and runs with their counts; the repository here; failures" {
  run src repo "" --repo o/r
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[0]}" = "https://github.com/o/r"$'\t'"hub"$'\t'"o/r"$'\t'"tree"$'\t'"-"$'\t'"files        main" ]
  [ "${lines[1]}" = "https://github.com/o/r/issues"$'\t'"hub"$'\t'"o/r"$'\t'"issues"$'\t'"-"$'\t'"issues       5 open" ]
  [ "${lines[2]}" = "https://github.com/o/r/pulls"$'\t'"hub"$'\t'"o/r"$'\t'"prs"$'\t'"-"$'\t'"pull requests 2 open" ]
  [ "${lines[3]}" = "https://github.com/o/r/actions"$'\t'"hub"$'\t'"o/r"$'\t'"runs"$'\t'"-"$'\t'"workflow runs last: failure CI" ]
  grep -qx 'repo view o/r --json nameWithOwner,description,url,pushedAt,defaultBranchRef,issues,pullRequests,isArchived' "$BATS_TEST_TMPDIR/gh.calls"
  # cached for FZX_GITHUB_ISSUES_TTL
  src repo "" --repo o/r > /dev/null
  [ "$(grep -c '^repo view o/r' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
  [ "$(grep -c '^run list' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
  # without runs (none, or none readable): the row says none
  echo '[]' > "$BATS_TEST_TMPDIR/runs.json"
  run src repo "" --repo p/q
  [[ "${lines[3]}" == *"workflow runs none" ]]
  clone_here
  run src repo ""
  [[ "${lines[0]}" == "https://github.com/o/r"$'\t'* ]]
  STUB_GH_FAIL=1 run src repo "" --repo x/z
  [ "$status" -eq 1 ]
  [[ "$output" == *"error"*"cannot read x/z: HTTP 404: Not Found"* ]]
  cd "$BATS_TEST_TMPDIR"
  run src repo ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"repo needs --repo OWNER/REPO or a GitHub clone here"* ]]
}

@test "runs: the state, workflow, title, branch, event, age and duration of each; errors and none" {
  run src runs "" --repo o/r
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  IFS=$'\t' read -r url kind repo file index display <<< "${lines[0]}"
  [ "$url $kind $repo $index" = "https://github.com/o/r/actions/runs/1 run o/r 0" ]
  [ "$file" = "$FZX_CACHE_DIR/github/issues/runs-o__r.json" ]
  # the workflow column as wide as the widest name; tabs in titles become spaces
  [[ "$display" == "F CI      Fix it main push "*" 2m5s" ]]
  # running: the time since it started
  [[ "${lines[1]}" == *$'\t'"R Release Next v1 workflow_dispatch "* ]]
  [[ "${lines[2]}" == *$'\t'"S CI      Old main push "*" 9s" ]]
  grep -q '^run list -R o/r -L 100 --json databaseId,' "$BATS_TEST_TMPDIR/gh.calls"
  rm -rf "$FZX_CACHE_DIR/github/issues"
  STUB_GH_RUNS_FAIL=1 run src runs "" --repo o/r
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot list workflow runs: HTTP 403: Forbidden"* ]]
  echo '[]' > "$BATS_TEST_TMPDIR/runs.json"
  run src runs "" --repo o/r
  [ "$output" = "-"$'\t'"error"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"  o/r has no workflow runs" ]
}

@test "preview: the hub's rows (README, the first issues and prs, the latest runs); a run and its jobs" {
  src repo "" --repo o/r > /dev/null
  run env FZX_PREVIEW_VIEWERS=markdown=cat "$GH_DIR/preview.sh" https://github.com/o/r hub o/r tree -
  [ "${lines[0]}" = "o/r" ]
  [ "${lines[1]}" = "The r" ]
  [ "${lines[2]}" = "branch  main" ]
  [[ "$output" == *"# The readme" ]]
  run "$GH_DIR/preview.sh" https://github.com/o/r/issues hub o/r issues -
  [ "${lines[0]}" = "2 open issues" ]
  [[ "${lines[1]}" == "O #12   Crash on start"* ]]
  run "$GH_DIR/preview.sh" https://github.com/o/r/pulls hub o/r prs -
  [ "${lines[0]}" = "3 open pull requests" ]
  run "$GH_DIR/preview.sh" https://github.com/o/r/actions hub o/r runs -
  [ "${lines[0]}" = "latest workflow runs" ]
  [[ "${lines[1]}" == "F CI      Fix it"* ]]
  run "$GH_DIR/preview.sh" https://github.com/o/r/actions/runs/1 run o/r "$FZX_CACHE_DIR/github/issues/runs-o__r.json" 0
  [ "${lines[0]}" = "CI #30  failure" ]
  [ "${lines[1]}" = "Fix	it" ]
  [[ "$output" == *$'jobs\n  failure  build  1m30s\n      failed step 2: test\n  success  lint  7s' ]]
  run "$GH_DIR/preview.sh" https://github.com/o/r/actions/runs/2 run o/r "$FZX_CACHE_DIR/github/issues/runs-o__r.json" 1
  [ "${lines[0]}" = "Release #31  in progress  attempt 2" ]
  # jobs cached by the run's last update
  [ "$(grep -c '^run view 1 -R o/r --json jobs' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
  run "$GH_DIR/preview.sh" https://github.com/o/r/actions/runs/1 run o/r "$FZX_CACHE_DIR/github/issues/runs-o__r.json" 0
  [ "$(grep -c '^run view 1 -R o/r --json jobs' "$BATS_TEST_TMPDIR/gh.calls")" -eq 1 ]
}

@test "actions: a run's log (failed jobs only, a running one watched), rerun, cancel in runs; the lists dropped" {
  load_libs log
  source "$GH_DIR/actions.sh" || :
  src runs "" --repo o/r > /dev/null
  PAGER=cat run github::action log -- https://github.com/o/r/actions/runs/1
  [ "$output" = "log of 1 -R o/r --log-failed" ]
  PAGER=cat run github::action log -- https://github.com/o/r/actions/runs/3
  [ "$output" = "log of 3 -R o/r --log" ]
  github::action log -- https://github.com/o/r/actions/runs/2
  [ "$(tail -1 "$BATS_TEST_TMPDIR/run.calls")" = "run watch 2 -R o/r" ]
  github::action rerun -- https://github.com/o/r/actions/runs/1 https://github.com/o/r/actions/runs/3 https://github.com/o/r
  [ "$(tail -2 "$BATS_TEST_TMPDIR/run.calls" | tr '\n' '|')" = "run rerun 1 -R o/r --failed|run rerun 3 -R o/r|" ]
  [ ! -d "$FZX_CACHE_DIR/github/issues" ]
  FZX_MODE=runs github::action close -- https://github.com/o/r/actions/runs/2
  [ "$(tail -1 "$BATS_TEST_TMPDIR/run.calls")" = "run cancel 2 -R o/r" ]
  # close elsewhere is the issues' and pull requests' (a run's URL skipped)
  FZX_MODE=issues github::action close -- https://github.com/o/r/actions/runs/3
  [ "$(grep -c 'run cancel' "$BATS_TEST_TMPDIR/run.calls")" -eq 1 ]
}

@test "under fzx: ctrl-o on a repository opens its hub; enter or ctrl-o on a hub row its list; runs accept" {
  load_libs log session
  fzx::session_create github "$GH_DIR"
  child_of() {
    local c="${1##*--resume }"
    c="${c%% *}"
    CHILD_ARGS=()
    mapfile -d '' -t CHILD_ARGS < "$FZX_RUNTIME_DIR/sessions/$c/meta/args"
    CHILD_MODE="${1##* -m :}"
  }
  run "$FZX" _cb transform into -- https://github.com/o/r repo o/r -
  [[ "$output" == "become:"* ]]
  child_of "$output"
  [ "$CHILD_MODE ${CHILD_ARGS[*]}" = "repo --repo o/r" ]
  fzx::state_set mode repo
  # the hidden modes (files, runs) are screens of their own; issues and prs are two views of one session
  local ids=()
  for t in tree issues prs runs; do
    run "$FZX" _cb transform enter -- https://github.com/o/r hub o/r "$t"
    child_of "$output"
    [ "$CHILD_MODE ${CHILD_ARGS[*]}" = "$t --repo o/r" ]
    c="${output##*--resume }" c="${c%% *}"
    ids+=("$c")
  done
  [ "${ids[1]}" = "${ids[2]}" ]
  [ "$(printf '%s\n' "${ids[0]}" "${ids[1]}" "${ids[3]}" | sort -u | wc -l)" -eq 3 ]
  run "$FZX" _cb transform into -- https://github.com/o/r/actions hub o/r runs
  child_of "$output"
  [ "$CHILD_MODE" = runs ]
  fzx::state_set mode runs
  run "$FZX" _cb transform enter -- https://github.com/o/r/actions/runs/1 run o/r "$FZX_CACHE_DIR/x"
  [ "$output" = accept ]
  stub_fzf
  run "$FZX" -m github:repo --repo o/r
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=o/r: enter or ctrl-o opens the list "* ]]
  run "$FZX" -m github:runs --repo o/r
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=workflow runs of o/r, latest first "* ]]
  [[ "$(fzf_bind alt-l)" == *"_cb action log --repo o/r -- {+1}"* ]]
  [[ "$(fzf_bind alt-R)" == *"_cb action rerun --repo o/r -- {+1}"* ]]
}
