#!/usr/bin/env bats
# the repos module over fixture repositories under a stubbed ghq

load test_helper

REPOS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/repos")"

# git with a fixed identity, quiet
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@" > /dev/null 2>&1; }

setup() {
  setup_fzx
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  G="$BATS_TEST_TMPDIR/ghq"
  mkdir -p "$G/github.com/me" "$G/github.com/other" "$G/gitlab.com/team" "$BATS_TEST_TMPDIR/remotes"
  # me/alpha: one commit ahead of its origin, a changed file, a TODO.md with 2 open items
  g init --bare "$BATS_TEST_TMPDIR/remotes/alpha.git"
  g clone "$BATS_TEST_TMPDIR/remotes/alpha.git" "$G/github.com/me/alpha"
  A="$G/github.com/me/alpha"
  printf -- '- [ ] **One** (p1) [bug]: x\n- [x] **Done** (p2) [bug]: y\n- [ ] **Two** (p3) [feature]: z\n' > "$A/TODO.md"
  g -C "$A" add TODO.md && g -C "$A" commit -m first && g -C "$A" push -u origin main
  echo more >> "$A/TODO.md" && g -C "$A" commit -am second
  echo dirty > "$A/new.txt"
  # other/beta: clean, older commit; team/gamma on gitlab
  g init "$G/github.com/other/beta" && g -C "$G/github.com/other/beta" commit --allow-empty -m old --date=2020-01-01T00:00:00
  GIT_COMMITTER_DATE=2020-01-01T00:00:00 g -C "$G/github.com/other/beta" commit --allow-empty --amend -m old --date=2020-01-01T00:00:00
  g init "$G/gitlab.com/team/gamma" && g -C "$G/gitlab.com/team/gamma" commit --allow-empty -m init
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/ghq" << STUB
#!/usr/bin/env bash
case "\$1" in
  root) echo "$G" ;;
  list) printf '%s\n' "$G/github.com/me/alpha" "$G/github.com/other/beta" "$G/gitlab.com/team/gamma" ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/ghq"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export FZX_REPOS_TTL=120
  conf 'FZX_REPOS_OWNERS=(me)'
}

conf() { mkdir -p "$FZX_CONFIG_DIR/modules/repos"; printf '%s\n' "$@" > "$FZX_CONFIG_DIR/modules/repos/config.sh"; }
plain() { sed 's/\x1b\[[0-9;]*m//g'; }
src() { FZX_MODE="${1:-all}" "$REPOS/source.sh" | plain; }
# run a repos::function with config loaded
repos_fn() {
  bash -c 'source "$FZX_REPO/lib/core.sh"; fzx::require log config; fzx::config_load "$1" repos; source "$1/actions.sh"; shift; "$@"' _ "$REPOS" "$@"
}

@test "before any scan: every repository, owner/name (host when not github), no state" {
  run src
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *$'\t''me/alpha '* && "$output" == *$'\t''other/beta '* && "$output" == *$'\t''gitlab.com/team/gamma '* ]]
  [[ "$output" != *'●'* ]]
}

@test "scan: branch, changed files, ahead/behind, last commit, open TODO items" {
  run "$REPOS/source.sh" --scan "$A"
  [ "$status" -eq 0 ]
  IFS=$'\t' read -r dir branch changed ahead behind last todos <<< "$output"
  [ "$dir" = "$A" ] && [ "$branch" = main ] && [ "$changed" = 1 ] && [ "$ahead" = 1 ] && [ "$behind" = 0 ]
  [[ "$last" =~ ^[0-9]+$ ]] && [ "$todos" = 2 ]
}

@test "refresh fills the cache once per TTL; the rows then show the state" {
  run repos_fn repos::refresh
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FZX_CACHE_DIR/repos/status")" -eq 3 ]
  run repos_fn repos::refresh
  [ "$status" -eq 1 ]
  run src
  [[ "$output" == *'me/alpha'*'main'*'●1 ↑1 ☐2'* ]]
  # a forced scan that finds nothing new leaves it alone and says so
  run repos_fn repos::refresh force
  [ "$status" -eq 1 ]
}

@test "modes filter on the scanned state and the owner" {
  repos_fn repos::refresh
  run src changed
  [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == *alpha* ]]
  run src unsynced
  [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == *alpha* ]]
  run src todos
  [ "${#lines[@]}" -eq 1 ]
  run src mine
  [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == *me/alpha* ]]
}

@test "sort: newest commit first, or by name" {
  repos_fn repos::refresh
  run src
  [[ "${lines[2]}" == *other/beta* ]]
  FZX_SORT=name run src
  [[ "${lines[0]}" == *gitlab.com/team/gamma* && "${lines[1]}" == *me/alpha* && "${lines[2]}" == *other/beta* ]]
}

@test "extra roots: their repositories are added, links into ghq collapse" {
  mkdir -p "$BATS_TEST_TMPDIR/git" "$BATS_TEST_TMPDIR/own"
  ln -s "$A" "$BATS_TEST_TMPDIR/git/alpha"
  g init "$BATS_TEST_TMPDIR/own/delta"
  conf 'FZX_REPOS_OWNERS=(me)' "FZX_REPOS_ROOTS=('$BATS_TEST_TMPDIR/git' '$BATS_TEST_TMPDIR/own')"
  run src
  [ "${#lines[@]}" -eq 4 ]
  [[ "$output" == *delta* ]]
}

@test "rescan replaces only the given repositories' rows" {
  repos_fn repos::refresh
  rm "$A/new.txt"
  run repos_fn repos::rescan "$A"
  [ "$(wc -l < "$FZX_CACHE_DIR/repos/status")" -eq 3 ]
  run src changed
  [ "${#lines[@]}" -eq 0 ]
}

@test "fetch picks up new upstream commits; bad paths are refused" {
  repos_fn repos::refresh
  # another clone pushes two commits
  g clone "$BATS_TEST_TMPDIR/remotes/alpha.git" "$BATS_TEST_TMPDIR/elsewhere"
  g -C "$BATS_TEST_TMPDIR/elsewhere" commit --allow-empty -m up1
  g -C "$BATS_TEST_TMPDIR/elsewhere" commit --allow-empty -m up2
  g -C "$BATS_TEST_TMPDIR/elsewhere" push origin main
  run "$REPOS/actions.sh" fetch "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *fetched* ]]
  run src
  [[ "${lines[0]}" == *'↑1 ↓2'* ]]
  run "$REPOS/actions.sh" fetch "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
}

@test "remote web addresses from ssh and https remotes" {
  g -C "$G/github.com/other/beta" remote add origin git@github.com:other/beta.git
  g -C "$G/gitlab.com/team/gamma" remote add origin https://gitlab.com/team/gamma.git
  [ "$(repos_fn repos::url "$G/github.com/other/beta")" = https://github.com/other/beta ]
  [ "$(repos_fn repos::url "$G/gitlab.com/team/gamma")" = https://gitlab.com/team/gamma ]
}

@test "preview: path, status, commits and the open TODO items by priority" {
  run bash -c "'$REPOS/preview.sh' '$A' | sed 's/\x1b\[[0-9;]*m//g'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'## main...origin/main [ahead 1]'* && "$output" == *'second'* ]]
  [[ "$output" == *'TODO (2 open)'*'P1 One'*'P3 Two'* ]]
}

@test "under fzx: the scan is bound to start, ctrl-o opens git on the repository" {
  stub_fzf
  run "$FZX" -m repos
  [ "$status" -eq 0 ]
  fzf_binds start | grep -qxF "start:+bg-transform:$FZX _cb transform refresh"
  [ "$(fzf_bind ctrl-o)" = "ctrl-o:transform:$FZX _cb nav goto git {1}" ]
}

@test "refresh transform: through fzx's callback, a reload of the source when the scan changed the cache" {
  stub_fzf
  "$FZX" --keep -m repos
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" run "$FZX" _cb transform refresh
  [ "$status" -eq 0 ]
  [ "$output" = "reload:$FZX _cb source" ]
  # within the TTL: no scan, no reload
  FZX_SESSION="$sid" run "$FZX" _cb transform refresh
  [ -z "$output" ]
}
