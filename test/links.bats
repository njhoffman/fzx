#!/usr/bin/env bats
# lib/links.sh, the repos module's links action and the shell's repos and clone, against a stub ghq over
# fixture repositories

load test_helper

setup() {
  setup_fzx
  load_libs log links
  ROOT="$BATS_TEST_TMPDIR/ghq"
  export FZX_REPOS_LINKS_DIR="$BATS_TEST_TMPDIR/git" GHQ_ROOT_DIR="$ROOT"
  mkdir -p "$ROOT/github.com/a/one" "$ROOT/github.com/b/two" "$ROOT/github.com/c/one" "$BATS_TEST_TMPDIR/bin"
  # ghq: list -p prints the fixture repositories (sorted, so a/one comes before c/one); get makes one
  cat > "$BATS_TEST_TMPDIR/bin/ghq" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/ghq.calls"
case "$1" in
  list)
    if [[ " $* " == *" -p "* ]]; then find "$GHQ_ROOT_DIR" -mindepth 3 -maxdepth 3 -type d | sort
    else (cd "$GHQ_ROOT_DIR" && find . -mindepth 3 -maxdepth 3 -type d | sed 's|^\./||' | sort); fi
    ;;
  get) repo="${*: -1}"; repo="${repo#git@}"; repo="${repo/://}"; repo="${repo%.git}"; mkdir -p "$GHQ_ROOT_DIR/$repo" ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/ghq"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "link_repos: links each repository by name, the first keeps a shared name, dead links go" {
  mkdir -p "$FZX_REPOS_LINKS_DIR"
  ln -s "$BATS_TEST_TMPDIR/gone" "$FZX_REPOS_LINKS_DIR/gone"
  run fzx::link_repos
  [ "$status" -eq 0 ]
  [ "$(readlink "$FZX_REPOS_LINKS_DIR/one")" = "$ROOT/github.com/a/one" ]
  [ "$(readlink "$FZX_REPOS_LINKS_DIR/two")" = "$ROOT/github.com/b/two" ]
  [ ! -L "$FZX_REPOS_LINKS_DIR/gone" ]
  [[ "$output" == *"taken: one by "*"/a/one (not "*"/c/one)"* ]]
  [[ "${lines[-1]}" == "2 linked, 1 dead removed, 1 names taken (in "*"/git)" ]]
  # again: nothing new; a link with a trailing slash counts as the same
  ln -sfn "$ROOT/github.com/b/two/" "$FZX_REPOS_LINKS_DIR/two"
  run fzx::link_repos
  [ "${lines[-1]}" = "0 linked, 0 dead removed, 1 names taken (in $FZX_REPOS_LINKS_DIR)" ]
}

@test "link_repos: a dry run changes nothing; a name held by a directory is reported; no directory set" {
  mkdir -p "$FZX_REPOS_LINKS_DIR/two"
  run fzx::link_repos --dry-run
  [[ "$output" == *"would link one -> "* && "$output" == *"/git/two is not a link"* ]]
  [[ "${lines[-1]}" == "dry run: 1 linked, 0 dead removed, 2 names taken"* ]]
  [ ! -e "$FZX_REPOS_LINKS_DIR/one" ]
  FZX_REPOS_LINKS_DIR="" run fzx::link_repos
  [ "$status" -eq 2 ]
  # link_repo is quiet without a directory (clones elsewhere just skip it)
  FZX_REPOS_LINKS_DIR="" run fzx::link_repo "$ROOT/github.com/a/one"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "repos module: the links action runs on its own; FZX_REPOS_LINKS_DIR defaults to ~/git when it exists" {
  run "$FZX_REPO/modules/repos/actions.sh" links --dry-run
  [[ "${lines[-1]}" == "dry run: 2 linked"* ]]
  load_libs config
  mkdir -p "$BATS_TEST_TMPDIR/home/git"
  run env -u FZX_REPOS_LINKS_DIR HOME="$BATS_TEST_TMPDIR/home" bash -c 'source "$0/lib/core.sh"; fzx::require log config; fzx::config_load; echo "$FZX_REPOS_LINKS_DIR"' "$FZX_REPO"
  [ "$output" = "$BATS_TEST_TMPDIR/home/git" ]
  run env -u FZX_REPOS_LINKS_DIR HOME="$BATS_TEST_TMPDIR/nohome" bash -c 'source "$0/lib/core.sh"; fzx::require log config; fzx::config_load; echo "[$FZX_REPOS_LINKS_DIR]"' "$FZX_REPO"
  [ "$output" = "[]" ]
}

@test "zsh: repos links (--dry-run, unknown options), clone clones anything ghq takes and links it" {
  command -v zsh > /dev/null || skip "zsh not installed"
  local zint
  zint="$(readlink -f "$BATS_TEST_DIRNAME/../shell/fzx.zsh")"
  run zsh -f -c "FZX_ZSH_NO_BIND=1; source '$zint'; repos --dry-run"
  [[ "${lines[-1]}" == "dry run: 2 linked"* ]]
  run zsh -f -c "FZX_ZSH_NO_BIND=1; source '$zint'; repos"
  [ -L "$FZX_REPOS_LINKS_DIR/two" ]
  run zsh -f -c "FZX_ZSH_NO_BIND=1; source '$zint'; repos --bogus"
  [ "$status" -eq 2 ]
  run zsh -f -c "FZX_ZSH_NO_BIND=1; source '$zint'; clone git@bitbucket.org:team/app.git"
  [ "$status" -eq 0 ]
  grep -qx 'get -p -- git@bitbucket.org:team/app.git' "$BATS_TEST_TMPDIR/ghq.calls"
  [ "$(readlink "$FZX_REPOS_LINKS_DIR/app")" = "$ROOT/bitbucket.org/team/app" ]
  run zsh -f -c "FZX_ZSH_NO_REPOS=1 FZX_ZSH_NO_BIND=1; source '$zint'; whence -w clone"
  # (an older clone command may be on PATH: only the function must be missing)
  [[ "$output" != *function* ]]
}
