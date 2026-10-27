#!/usr/bin/env bats
# the github module against a stub gh (searches, the API's trees, blobs, contents and READMEs) and ghq

load test_helper

bats_require_minimum_version 1.5.0

GH_DIR="$(readlink -f "$BATS_TEST_DIRNAME/../modules/github")"
SHA=0123456789abcdef0123456789abcdef01234567

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  # gh: each call's args on a line of gh.calls (searches also in gh.search, one arg per line)
  cat > "$STUBS/gh" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/gh.calls"
args=("$@")
[[ "$1" == -H ]] && args=("${@:3}")
[[ "${args[0]}" == api && "${args[1]}" == -H ]] && args=(api "${args[@]:3}")
case "${args[0]} ${args[1]}" in
  "auth token") echo tok ;;
  "search repos" | "search code")
    printf '%s\n' "${args[@]}" > "$BATS_TEST_TMPDIR/gh.search"
    [[ -n "${STUB_GH_FAIL:-}" ]] && { echo "API rate limit exceeded" >&2; exit 1; }
    if [[ "${args[1]}" == repos ]]; then cat "$BATS_TEST_TMPDIR/repos.json"; else cat "$BATS_TEST_TMPDIR/code.json"; fi
    ;;
  "api rate_limit") echo "searches left: 29/30, code 9/10 (per minute)" ;;
  "api "*)
    path="${args[1]}"
    case "$path" in
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
  cat > "$STUBS/ghq" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/ghq.calls"
[[ "$1" == list ]] && echo "$HOME/ghq/${*: -1}"
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
  sed 's/\x1b\[[0-9;]*m//g' "$BATS_TEST_TMPDIR/src.out"
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
  [[ "${lines[1]}" == *$'\t'"o/noreadme "* ]]
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
  FZX_GITHUB_MARKDOWN=cat run "$GH_DIR/preview.sh" https://github.com/junegunn/fzf repo junegunn/fzf "$file" 0
  [ "${lines[0]}" = junegunn/fzf ]
  [[ "$output" == *"license     MIT License"* && "$output" == *"# The readme"* ]]
  FZX_GITHUB_MARKDOWN=cat run "$GH_DIR/preview.sh" https://github.com/o/noreadme repo o/noreadme "$file" 1
  [[ "${lines[0]}" == "o/noreadme  archived" && "$output" == *"no README"* ]]
}

@test "preview: a code hit's fragments, then the file; a tree file, a large one, a directory" {
  src code x > /dev/null
  local file
  file="$(cut -f4 "$BATS_TEST_TMPDIR/src.out" | head -1)"
  run --separate-stderr bash -c '"$0" "$@" | sed "s/\x1b\[[0-9;]*m//g"' "$GH_DIR/preview.sh" "https://github.com/o/r/blob/$SHA/lib/opts.sh" code o/r "$file" 0
  [ "${lines[0]}" = "o/r  lib/opts.sh" ]
  [[ "$output" == *"# fzx::bind adds a key"$'\n'"fzx::bind() {"* ]]
  [[ "$output" == *"blob aaaa"* ]]
  run bash -c '"$0" "$@" | sed "s/\x1b\[[0-9;]*m//g"' "$GH_DIR/preview.sh" "https://github.com/o/r/blob/$SHA/lib/a.sh" blob o/r b2:20 lib/a.sh
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
  run "$GH_DIR/actions.sh" fetch --dest out https://github.com/o/r/blob/main/missing.sh https://example.com/x
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot fetch"* && "$output" == *"not a GitHub URL"* ]]
}

@test "actions: rows without a URL are skipped; the browser opens urls; web opens the search" {
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
  [[ "$(fzf_bind enter)" == "enter:transform:$FZX _cb transform enter -- {1} {2} {3}" ]]
  [[ "$(fzf_bind ctrl-o)" == *"_cb transform into -- {1} {2} {3}" ]]
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
