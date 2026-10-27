#!/usr/bin/env bats
# the git module, against a throwaway repository with a bare remote

load test_helper

bats_require_minimum_version 1.5.0

GIT_DIR_MOD="$(readlink -f "$BATS_TEST_DIRNAME/../modules/git")"

setup() {
  setup_fzx
  # isolate from the user's git config
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@t
  # raw diffs (delta, when installed, is the default filter)
  export FZX_GIT_DIFF_FILTER=""
  unset FZX_GIT_VIEW
  REMOTE="$BATS_TEST_TMPDIR/remote.git"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q --bare -b main "$REMOTE"
  git init -q -b main "$REPO"
  cd "$REPO"
  echo one > a.txt
  git add a.txt && git commit -qm "first"
  git remote add origin "$REMOTE"
  git push -q -u origin main
  echo two >> a.txt && git commit -qam "second"
  git switch -qc feature && echo f > f.txt && git add f.txt && git commit -qm "feature work" && git push -q origin feature
  git switch -q main
  echo staged > s.txt && git add s.txt
  echo changed >> a.txt
  echo new > "u space.txt"
  REAL="$(pwd -P)"
}

# source output without colors; keeps the source's exit status
src() {
  local rc
  FZX_MODE="$1" "$GIT_DIR_MOD/source.sh" "${@:2}" > "$BATS_TEST_TMPDIR/src.out"
  rc=$?
  sed 's/\x1b\[[0-9;]*m//g' "$BATS_TEST_TMPDIR/src.out"
  return "$rc"
}

@test "status: staged, modified and untracked files with absolute ids and a state icon" {
  FZX_ICONS=unicode run src status
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *"$REAL/a.txt"$'\t'" M ~ a.txt"* ]]
  [[ "$output" == *"$REAL/s.txt"$'\t'"A  + s.txt"* ]]
  [[ "$output" == *"$REAL/u space.txt"$'\t'"?? ? u space.txt"* ]]
  FZX_ICONS=none run src status
  [[ "$output" == *"$REAL/a.txt"$'\t'" M a.txt"* ]]
}

@test "status: renames show the original path" {
  git commit -qm wip
  git mv a.txt b.txt
  FZX_ICONS=unicode run src status
  # a.txt also has an unstaged change, so the worktree column is M; the icon is the rename's
  [[ "$output" == *"$REAL/b.txt"$'\t'"RM > b.txt <- a.txt"* ]]
}

@test "status: works from a subdirectory and with a DIR argument" {
  mkdir sub && cd sub
  run src status
  [[ "$output" == *"$REAL/a.txt"* ]]
  cd /
  run src status "$REPO"
  [[ "$output" == *"$REAL/a.txt"* ]]
}

@test "log: current branch, --all, --rev, and the limit" {
  run src log
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" =~ ^[0-9a-f]{40}$'\t'[0-9a-f]+\ .*second$ ]]
  run src log --all
  [ "${#lines[@]}" -eq 3 ]
  run src log --rev feature
  [[ "${lines[0]}" == *"feature work" ]]
  FZX_GIT_LOG_LIMIT=1 run src log
  [ "${#lines[@]}" -eq 1 ]
}

@test "branches: local and remote, current marked, upstream tracking, no remote HEAD" {
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
  git fetch -q origin
  git remote set-head origin main
  run src branches
  local ids
  ids="$(printf '%s\n' "${lines[@]}" | cut -f1 | sort | tr '\n' ' ')"
  [ "$ids" = "feature main origin/feature origin/main " ]
  [[ "$(printf '%s\n' "${lines[@]}" | grep $'^main\t')" == *"* main"*"[ahead 1]"* ]]
  # sorted by name: the name underlined; by last commit (the default): the date
  FZX_SORT=name run src branches
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "feature main origin/feature origin/main " ]
  grep -q $'\e\[32;4mfeature' "$BATS_TEST_TMPDIR/src.out"
  run src branches
  grep -q $'\e\[38;5;244;4m[0-9a-z ]*ago' "$BATS_TEST_TMPDIR/src.out"
}

@test "stash: lists stashes" {
  git stash -q
  run src stash
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "stash@{0}"$'\t'"stash@{0} "* ]]
}

@test "bad arguments fail with 2" {
  cd /
  run src status
  [ "$status" -eq 2 ]
  cd "$REPO"
  run src log --rev
  [ "$status" -eq 2 ]
  run src status --bogus
  [ "$status" -eq 2 ]
  run src status a b
  [ "$status" -eq 2 ]
}

# preview output without colors (diff colors split "+" from the line text)
prev() { FZX_MODE="$1" "$GIT_DIR_MOD/preview.sh" -- "$2" | sed 's/\x1b\[[0-9;]*m//g'; }
# prev_rev <mode> <rev> <id> [extra]
prev_rev() { FZX_MODE="$1" "$GIT_DIR_MOD/preview.sh" --rev "$2" -- "${@:3}" | sed 's/\x1b\[[0-9;]*m//g'; }

@test "preview: diff for tracked files, contents for untracked, commits, branches, stashes" {
  run prev status "$REAL/a.txt"
  [[ "$output" == *"+changed"* ]]
  run prev status "$REAL/s.txt"
  [[ "$output" == *"+staged"* ]]
  run prev status "$REAL/u space.txt"
  [[ "$output" == *untracked*new* ]]
  run prev log HEAD
  [[ "$output" == *second* ]]
  run prev branches feature
  [[ "$output" == *"feature work"* ]]
  git stash -q
  run prev stash 'stash@{0}'
  [[ "$output" == *"+changed"* ]]
}

@test "preview: FZX_GIT_DIFF_FILTER is applied to diffs" {
  FZX_GIT_DIFF_FILTER="tr a-z A-Z" FZX_MODE=log run "$GIT_DIR_MOD/preview.sh" -- HEAD
  [[ "$output" == *SECOND* ]]
}

@test "actions: stage and unstage in status, ignored in other modes" {
  FZX_MODE=status run "$GIT_DIR_MOD/actions.sh" stage -- "$REAL/a.txt" "$REAL/u space.txt"
  [ "$status" -eq 0 ]
  [ "$(git diff --cached --name-only | sort | tr '\n' ' ')" = "a.txt s.txt u space.txt " ]
  FZX_MODE=status run "$GIT_DIR_MOD/actions.sh" unstage -- "$REAL/s.txt"
  [ "$(git diff --cached --name-only | sort | tr '\n' ' ')" = "a.txt u space.txt " ]
  FZX_MODE=log run "$GIT_DIR_MOD/actions.sh" stage -- "$REAL/s.txt"
  [ "$status" -eq 0 ]
  [ "$(git diff --cached --name-only | sort | tr '\n' ' ')" = "a.txt u space.txt " ]
}

@test "actions: switch to a local branch, or track a remote one" {
  git stash -q -u
  FZX_MODE=branches run "$GIT_DIR_MOD/actions.sh" switch -- feature
  [ "$(git symbolic-ref --short HEAD)" = feature ]
  git branch -qD main
  FZX_MODE=branches run "$GIT_DIR_MOD/actions.sh" switch -- origin/main
  [ "$(git symbolic-ref --short HEAD)" = main ]
  [ "$(git rev-parse --abbrev-ref main@{upstream})" = origin/main ]
}

@test "actions: the module args select the repository" {
  cd /
  FZX_MODE=status run "$GIT_DIR_MOD/actions.sh" unstage "$REPO" -- "$REAL/s.txt"
  [ "$status" -eq 0 ]
  [ -z "$(git -C "$REPO" diff --cached --name-only)" ]
}

@test "actions: unknown action fails with 2" {
  run "$GIT_DIR_MOD/actions.sh" explode -- x
  [ "$status" -eq 2 ]
}

@test "under fzx: header, binds carrying the module args, modes switch in place" {
  stub_fzf
  run "$FZX" -m git "$REPO"
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=repo  main  ↑1 ↓0 origin/main "* ]]
  [ "$(fzf_flag --preview)" = "$FZX _cb preview $REPO -- {1} {3}" ]
  [[ "$(fzf_bind alt-s)" == "alt-s:execute($FZX _cb action stage $REPO -- {+1})+change-prompt("*")+reload($FZX _cb source)" ]]
  [ "$(fzf_bind alt-c)" = "alt-c:execute($FZX _cb action switch $REPO -- {+1})+transform($FZX _cb nav restart)" ]
  load_libs log session
  fzx::session_create git "$GIT_DIR_MOD" "$REPO"
  printf '%s\0' status log branches stash > "$FZX_SESSION_DIR/meta/modes"
  run "$FZX" _cb mode next
  [[ "$output" == change-border-label*reload\(* ]]
}

@test "under fzx: ctrl-o on a branch opens its log as a child; elsewhere it does nothing" {
  load_libs log session
  fzx::session_create git "$GIT_DIR_MOD"
  printf '%s\0' status log branches stash > "$FZX_SESSION_DIR/meta/modes"
  fzx::state_set mode branches
  run "$FZX" _cb transform into -- feature
  [[ "$output" == "become:$FZX --resume "*" -m :log" ]]
  local child="${output% -m*}"
  child="${child##* }"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${args[*]}" = "--rev feature $REAL" ]
  fzx::state_set mode status
  run "$FZX" _cb transform into -- "$REAL/a.txt"
  [ -z "$output" ]
}

@test "manifest: applicable only inside a work tree; stash only with stashes" {
  source "$GIT_DIR_MOD/manifest.sh"
  git::applicable git
  run git::applicable git:stash
  [ "$status" -eq 1 ]
  git stash -q
  git::applicable git:stash
  cd /
  run git::applicable git
  [ "$status" -eq 1 ]
}

@test "manifest: summaries count changes, commits vs upstream, branches and stashes" {
  source "$GIT_DIR_MOD/manifest.sh"
  [ "$(git::summary git)" = "1 staged, 1 modified, 1 untracked" ]
  [ "$(git::summary git:log)" = "2 commits, 1 ahead / 0 behind origin/main" ]
  [ "$(git::summary git:log --all)" = "3 commits on all refs" ]
  [ "$(git::summary git:branches)" = "2 local, 2 remote, on main" ]
  git stash -q
  [ "$(git::summary git:stash)" = "1 stashes" ]
}

@test "manifest: the summary key follows HEAD and the refs; outside a repository it is empty" {
  source "$GIT_DIR_MOD/manifest.sh"
  local k1 k2 k3
  k1="$(git::summary_key git)"
  [[ "$k1" == "$(git rev-parse HEAD)"* ]]
  git commit -q --allow-empty -m another
  k2="$(git::summary_key git)"
  [ "$k1" != "$k2" ]
  # a stash (refs/stash appears) changes it without a new HEAD
  touch -d '1 minute ago' .git/index .git/HEAD .git/logs/HEAD
  k2="$(git::summary_key git)"
  echo change >> "$(git ls-files | head -1)"
  git stash -q
  k3="$(git::summary_key git)"
  [ "$k2" != "$k3" ]
  cd "$BATS_TEST_TMPDIR"
  [ -z "$(git::summary_key git)" ]
}

@test "tags: newest first, lightweight ones marked; reflog: HEAD's moves, or a ref's with --rev" {
  git tag -a v1 -m "release one" HEAD~1
  git tag light
  run src tags
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | sort | tr '\n' ' ')" = "light v1 " ]
  [[ "$(printf '%s\n' "${lines[@]}" | grep $'^light\t')" == *lightweight* ]]
  [[ "$(printf '%s\n' "${lines[@]}" | grep $'^v1\t')" == *"release one" ]]
  run src reflog
  [[ "${lines[0]}" =~ ^[0-9a-f]{40}$'\t'[0-9a-f]+\ HEAD@\{0\} ]]
  [[ "$output" == *"checkout: moving from feature to main"* ]]
  run src reflog --rev feature
  [[ "${lines[0]}" == *"feature@{0}"* ]]
}

@test "worktrees: every work tree, the current one marked, its branch" {
  git worktree add -q "$BATS_TEST_TMPDIR/wt" feature
  run src worktrees
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "$REAL"$'\t'"* "* ]]
  [[ "$output" == *"$(cd "$BATS_TEST_TMPDIR/wt" && pwd -P)"$'\t'*feature* ]]
}

@test "commit: the files a commit changed, renames with their original, a root commit's files" {
  git commit -qam wip
  git mv a.txt moved.txt
  git commit -qm "move"
  FZX_ICONS=none run src commit --rev HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "$REAL/moved.txt"$'\t'"R moved.txt <- a.txt"$'\t'"a.txt" ]
  FZX_ICONS=none run src commit --rev HEAD~1
  [[ "$output" == *"$REAL/s.txt"$'\t'"A s.txt"$'\t'* ]]
  FZX_ICONS=none run src commit --rev "$(git rev-list --max-parents=0 HEAD)"
  [ "$output" = "$REAL/a.txt"$'\t'"A a.txt"$'\t' ]
  run src commit
  [ "$status" -eq 2 ]
  run src commit --rev nope
  [ "$status" -eq 2 ]
}

@test "preview: a commit's file (renames follow the original), blame in status and commit, tags, worktrees" {
  git commit -qam wip
  git mv a.txt moved.txt
  echo more >> moved.txt
  git add moved.txt
  git commit -qm "move"
  run prev_rev commit HEAD "$REAL/moved.txt" a.txt
  [[ "$output" == *"rename from a.txt"* && "$output" == *"+more"* ]]
  FZX_GIT_VIEW=blame run prev_rev commit HEAD "$REAL/moved.txt" a.txt
  [[ "$output" == *"T "*" 4) more"* ]]
  FZX_GIT_VIEW=blame run prev status "$REAL/moved.txt"
  [[ "$output" == *"1) one"* ]]
  git tag -a v1 -m "release one"
  run prev tags v1
  [[ "$output" == *"release one"* ]]
  run prev worktrees "$REAL"
  [[ "$output" == "## main"* ]]
}

@test "preview: auto filter uses delta when installed, at the preview's width; empty is none" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\necho "delta $*"\n' > "$BATS_TEST_TMPDIR/bin/delta"
  chmod +x "$BATS_TEST_TMPDIR/bin/delta"
  FZX_GIT_DIFF_FILTER=auto FZF_PREVIEW_COLUMNS=70 PATH="$BATS_TEST_TMPDIR/bin:$PATH" run prev log HEAD
  [ "$output" = "delta --paging=never --width=70" ]
  run prev log HEAD
  [[ "$output" == *second* ]]
}

@test "under fzx: ctrl-o opens a commit's files from log, reflog and stash, a tag's log, a work tree's status" {
  load_libs log session
  fzx::session_create git "$GIT_DIR_MOD"
  printf '%s\0' status log branches tags stash reflog worktrees > "$FZX_SESSION_DIR/meta/modes"
  local child args
  for mode in log reflog stash; do
    fzx::state_set mode "$mode"
    run "$FZX" _cb transform into -- abc123
    [[ "$output" == "become:$FZX --resume "*" -m :commit" ]]
    child="${output% -m*}" child="${child##* }"
    mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
    [ "${args[*]}" = "--rev abc123 $REAL" ]
  done
  fzx::state_set mode tags
  run "$FZX" _cb transform into -- v1
  [[ "$output" == *" -m :log" ]]
  fzx::state_set mode worktrees
  run "$FZX" _cb transform into -- /some/tree
  [[ "$output" == *" -m :status" ]]
  child="${output% -m*}" child="${child##* }"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${args[*]}" = "/some/tree" ]
}

@test "under fzx: alt-v flips the status and commit previews between diff and blame" {
  load_libs log session
  fzx::session_create git "$GIT_DIR_MOD"
  fzx::state_set mode status
  run "$FZX" _cb transform view
  [ "$output" = "change-preview-label( blame )+refresh-preview" ]
  [ "$(cat "$FZX_SESSION_DIR/state/git_view")" = blame ]
  run bash -c "'$FZX' _cb preview -- '$REAL/a.txt' | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "$output" == *"1) one"* ]]
  run "$FZX" _cb transform view
  [ "$output" = "change-preview-label( diff )+refresh-preview" ]
  fzx::state_set mode log
  run "$FZX" _cb transform view
  [ -z "$output" ]
}

@test "under fzx: commit is a hidden mode: out of the cycle, alone in its session, header names the commit" {
  stub_fzf
  FZX_ICONS=none run "$FZX" -m git "$REPO"
  [ "$status" -eq 0 ]
  [ -n "$(fzf_bind alt-0)" ]
  read_fzf_args
  local footer="" a
  for a in "${FZF_ARGS[@]}"; do [[ "$a" == --footer=* ]] && footer="$a"; done
  [[ "$footer" == *worktrees* && "$footer" != *commit* ]]
  FZX_ICONS=none run "$FZX" -m git:commit --rev HEAD "$REPO"
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=repo  main  ↑1 ↓0 origin/main  "*" second "* ]]
  [ -z "$(fzf_bind alt-0)" ]
  footer=""
  for a in "${FZF_ARGS[@]}"; do [[ "$a" == --footer=* ]] && footer="$a"; done
  [[ "$footer" != *status* ]]
}

act() { FZX_MODE="$1" "$GIT_DIR_MOD/actions.sh" "${@:2}"; }
subjects() { git log --format=%s "$@" | tr '\n' ' '; }

@test "patch: add -p stages the hunks answered yes" {
  printf 'y\n' | act status patch -- "$REAL/a.txt"
  [[ "$(git diff --cached -- a.txt)" == *"+changed"* ]]
}

@test "switch: log, reflog and tags check out detached; branches still switch" {
  git stash -q -u
  act log switch -- "$(git rev-parse HEAD~1)"
  ! git symbolic-ref -q HEAD
  [ "$(git rev-parse HEAD)" = "$(git rev-parse main~1)" ]
  git tag v1 main
  act tags switch -- v1
  [ "$(git rev-parse HEAD)" = "$(git rev-parse main)" ]
  act branches switch -- main
  [ "$(git symbolic-ref --short HEAD)" = main ]
}

@test "switch in commit mode: files as of the commit, staged; files with local changes or absent are skipped" {
  git commit -qam wip
  echo three >> s.txt && git commit -qam third
  local first
  first="$(git rev-list --max-parents=0 HEAD)"
  echo dirty >> s.txt
  FZX_MODE=commit run "$GIT_DIR_MOD/actions.sh" switch --rev "$first" -- "$REAL/a.txt" "$REAL/s.txt" "$REAL/f.txt"
  [ "$(cat a.txt)" = one ]
  [ "$(git diff --cached --name-only)" = a.txt ]
  [[ "$output" == *"local changes: s.txt"* ]]
  [[ "$(tail -n 1 s.txt)" == dirty ]]
}

@test "pick: cherry-picks oldest first whatever the selection order; stash: apply keeps the stash" {
  git stash -q -u
  git switch -q feature
  echo g > g.txt && git add g.txt && git commit -qm "feature two"
  echo h > h.txt && git add h.txt && git commit -qm "feature three"
  git switch -q main
  act log pick -- "$(git rev-parse feature)" "$(git rev-parse feature~1)"
  [ "$(subjects -2)" = "feature three feature two " ]
  act stash pick -- 'stash@{0}'
  [ "$(git stash list | wc -l)" -eq 1 ]
  [[ "$(cat a.txt)" == *changed* ]]
}

@test "revert: newest first, no editor" {
  git stash -q -u
  echo x >> a.txt && git commit -qam "x"
  echo y >> a.txt && git commit -qam "y"
  act log revert -- "$(git rev-parse HEAD~1)" "$(git rev-parse HEAD)"
  [ "$(subjects -2)" = "Revert \"x\" Revert \"y\" " ]
  [ "$(cat a.txt)" = "$(printf 'one\ntwo')" ]
}

@test "branch: a new branch at the selection, switched to; an empty name cancels" {
  git stash -q -u
  printf 'topic\n' | act log branch -- "$(git rev-parse HEAD~1)"
  [ "$(git symbolic-ref --short HEAD)" = topic ]
  [ "$(git rev-parse HEAD)" = "$(git rev-parse main~1)" ]
  printf '\n' | act branches branch -- main
  [ "$(git symbolic-ref --short HEAD)" = topic ]
}

@test "stash: status stashes the selected files only (untracked too); stash mode pops" {
  act status stash -- "$REAL/a.txt" "$REAL/u space.txt"
  [ "$(git stash list | wc -l)" -eq 1 ]
  [ "$(cat a.txt)" = "$(printf 'one\ntwo')" ]
  [ ! -e "u space.txt" ]
  [ "$(git diff --cached --name-only)" = s.txt ]
  act stash stash -- 'stash@{0}'
  [ "$(git stash list | wc -l)" -eq 0 ]
  [ -e "u space.txt" ]
}

@test "ignore: anchored paths appended once, after a missing final newline" {
  printf 'build' > .gitignore
  act status ignore -- "$REAL/u space.txt"
  act status ignore -- "$REAL/u space.txt"
  [ "$(cat .gitignore)" = "$(printf 'build\n/u space.txt')" ]
  [ -z "$(git status --porcelain -- 'u space.txt')" ]
}

@test "commit, amend (refused once pushed unless FZX_GIT_DESTRUCTIVE=1) and fetch need no selection" {
  GIT_EDITOR="printf 'from editor\n' >" act status commit --
  [ "$(git log -1 --format=%s)" = "from editor" ]
  git add a.txt
  GIT_EDITOR=true act log amend --
  [ "$(git log -1 --format=%s)" = "from editor" ]
  [ -z "$(git diff --cached --name-only)" ]
  git push -q origin main
  echo more >> a.txt && git add a.txt
  run act status amend --
  [ "$status" -ne 0 ]
  [[ "$output" == *"published history"* ]]
  FZX_GIT_DESTRUCTIVE=1 GIT_EDITOR=true act status amend --
  [ -z "$(git diff --cached --name-only)" ]
  git -C "$REMOTE" branch -q newer main
  act branches fetch --
  git rev-parse --verify -q origin/newer
}

@test "verbs outside their modes do nothing" {
  act log stage -- "$REAL/a.txt"
  act status pick -- HEAD
  act branches ignore -- x
  [ ! -e .gitignore ]
  [ "$(git diff --cached --name-only)" = s.txt ]
  [ "$(subjects -1)" = "second " ]
}

@test "help and actions menu: verbs show the current mode's meaning, idle ones are left out" {
  local args=(m:git $'c:mode\tstatus\t-\t' $'c:mode\tlog\t-\t' $'c:mode\tstash\t-\t'
    $'k:git\talt-k\taction: log: cherry-pick the selected commits; stash: apply the stash'
    $'k:git\tctrl-y\taction: copy the selection')
  FZX_MODE=stash run "$FZX" keys "${args[@]}"
  [[ "$output" == *"action: apply the stash"* && "$output" != *cherry-pick* ]]
  FZX_MODE=status run "$FZX" keys "${args[@]}"
  # bound but idle here: neither listed nor offered as free
  [[ "$output" != *alt-k* ]]
  [[ "$output" != *"apply the stash"* && "$output" == *"copy the selection"* ]]
}

@test "destructive verbs: listed only with FZX_GIT_DESTRUCTIVE=1, confirmed, and refused without it" {
  run "$GIT_DIR_MOD/components.tsv"
  [[ "$output" != *drop* ]]
  FZX_GIT_DESTRUCTIVE=1 run "$GIT_DIR_MOD/components.tsv"
  [[ "$output" == *$'\n''action  drop     alt-x'*confirm* ]]
  stub_fzf
  run "$FZX" -m git "$REPO"
  [ -z "$(fzf_bind alt-x)" ]
  FZX_GIT_DESTRUCTIVE=1 run "$FZX" -m git "$REPO"
  [[ "$(fzf_bind alt-x)" == *'_cb action drop'* ]]
  run act status drop -- "$REAL/u space.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"set FZX_GIT_DESTRUCTIVE=1"* ]]
  [ -e "u space.txt" ]
}

@test "drop: status discards unstaged changes (staged kept) and deletes untracked files" {
  echo more >> s.txt
  FZX_GIT_DESTRUCTIVE=1 act status drop -- "$REAL/a.txt" "$REAL/s.txt" "$REAL/u space.txt"
  [ "$(cat a.txt)" = "$(printf 'one\ntwo')" ]
  [ "$(cat s.txt)" = staged ]
  [ "$(git diff --cached --name-only)" = s.txt ]
  [ ! -e "u space.txt" ]
}

@test "drop: local branches deleted, remote ones left; stashes dropped highest first" {
  git stash -q -u
  echo x > x.txt && git stash -q -u
  echo y > y.txt && git stash -q -u
  FZX_GIT_DESTRUCTIVE=1 run act branches drop -- feature origin/feature
  ! git show-ref --verify --quiet refs/heads/feature
  git show-ref --verify --quiet refs/remotes/origin/feature
  [[ "$output" == *"not a local branch: origin/feature"* ]]
  local keep
  keep="$(git rev-parse 'stash@{1}')"
  FZX_GIT_DESTRUCTIVE=1 act stash drop -- 'stash@{0}' 'stash@{2}'
  [ "$(git stash list | wc -l)" -eq 1 ]
  [ "$(git rev-parse 'stash@{0}')" = "$keep" ]
}

# three commits on main above "first": second, c3, c4; local changes kept aside by --autostash
history3() {
  git commit -qam wip
  echo c3 > c3.txt && git add c3.txt && git commit -qm c3
  echo c4 > c4.txt && git add c4.txt && git commit -qm c4
}

@test "fixup: what is staged folds into the commit, local changes survive; nothing staged is refused" {
  history3
  echo fix >> c3.txt && git add c3.txt
  echo loose > loose.txt
  FZX_GIT_DESTRUCTIVE=1 run act log fixup -- "$(git rev-parse HEAD~1)"
  [ "$status" -eq 0 ]
  [ "$(subjects -3)" = "c4 c3 wip " ]
  [ "$(git show HEAD~1:c3.txt)" = "$(printf 'c3\nfix')" ]
  [ -e loose.txt ]
  FZX_GIT_DESTRUCTIVE=1 run act log fixup -- HEAD
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing staged"* ]]
}

@test "squash and reword rewrite the selected commit; commits off the branch or before merges are refused" {
  history3
  GIT_EDITOR="printf 'c3 and c4\n' >" FZX_GIT_DESTRUCTIVE=1 act log squash -- "$(git rev-parse HEAD)"
  [ "$(subjects -2)" = "c3 and c4 wip " ]
  [ -e c4.txt ]
  GIT_EDITOR="printf 'work\n' >" FZX_GIT_DESTRUCTIVE=1 act log reword -- "$(git rev-parse HEAD~1)"
  [ "$(subjects -3)" = "c3 and c4 work second " ]
  FZX_GIT_DESTRUCTIVE=1 run act log reword -- feature
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in the current branch's history"* ]]
  git merge -q --no-ff --no-edit feature
  FZX_GIT_DESTRUCTIVE=1 run act log reword -- "$(git rev-parse HEAD~1)"
  [[ "$output" == *"merges follow"* ]]
  FZX_GIT_DESTRUCTIVE=1 run act log squash -- "$(git rev-list --max-parents=0 HEAD)"
  [ "$status" -ne 0 ]
}

@test "rebase: rebase -i of the commits after the selected one" {
  history3
  GIT_SEQUENCE_EDITOR="sed -i '/ c3$/d'" FZX_GIT_DESTRUCTIVE=1 act log rebase -- "$(git rev-parse HEAD~2)"
  [ "$(subjects -2)" = "c4 wip " ]
  [ ! -e c3.txt ]
}
