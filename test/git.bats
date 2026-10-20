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

@test "status: staged, modified and untracked files with absolute ids" {
  run src status
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *"$REAL/a.txt"$'\t'" M a.txt"* ]]
  [[ "$output" == *"$REAL/s.txt"$'\t'"A  s.txt"* ]]
  [[ "$output" == *"$REAL/u space.txt"$'\t'"?? u space.txt"* ]]
}

@test "status: renames show the original path" {
  git commit -qm wip
  git mv a.txt b.txt
  run src status
  # a.txt also has an unstaged change, so the worktree column is M
  [[ "$output" == *"$REAL/b.txt"$'\t'"RM b.txt <- a.txt"* ]]
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
  [ "$(fzf_flag --preview)" = "$FZX _cb preview $REPO -- {1}" ]
  [ "$(fzf_bind alt-s)" = "alt-s:execute($FZX _cb action stage $REPO -- {+1})+reload($FZX _cb source)" ]
  [ "$(fzf_bind alt-c)" = "alt-c:execute($FZX _cb action switch $REPO -- {+1})+transform($FZX _cb nav restart)" ]
  load_libs log session
  fzx::session_create git "$GIT_DIR_MOD" "$REPO"
  printf '%s\0' status log branches stash > "$FZX_SESSION_DIR/meta/modes"
  run "$FZX" _cb mode next
  [[ "$output" == change-border-label*reload:* ]]
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
