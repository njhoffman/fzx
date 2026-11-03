#!/usr/bin/env bats
# the claude module over a stubbed claude-projects, claude and tmux

load test_helper

CLAUDE="$(readlink -f "$BATS_TEST_DIRNAME/../modules/claude")"

setup() {
  setup_fzx
  export FZX_ICONS=unicode
  P="$BATS_TEST_TMPDIR/projects"
  mkdir -p "$P/alpha" "$P/beta" "$P/gamma" "$BATS_TEST_TMPDIR/bin"
  printf '## 1. Next\n\n- [ ] **One.** (p3) [bug]: x\n- [x] **Done.** (p1) [bug]: y\n- [ ] **Two.** (p1) [feature]: z\n' > "$P/alpha/TODO.md"
  local now day
  now="$(date +%s)"
  day=86400
  # alpha: own git project, dirty, a session an hour ago; beta: own dotbare, no session; gamma: sessions only,
  # last session 30 days ago
  printf '%s\n' \
    "$P/alpha	alpha	git	0.2.0	main	3	1	0	2	1	0	$((now - 3600))	4	own" \
    "$P/beta	beta	dotbare	1.0.0		0	0	0	0	0	0	0	0	own" \
    "$P/gamma	gamma	plain			0	0	0	0	0	0	$((now - 30 * day))	2	sessions" > "$BATS_TEST_TMPDIR/rows"
  # claude-projects: the rows, counting its runs; show prints a marker card
  cat > "$BATS_TEST_TMPDIR/bin/claude-projects" << STUB
#!/usr/bin/env bash
echo run >> "$BATS_TEST_TMPDIR/scans"
case "\$1" in
  show) printf 'CARD %s\n' "\${@: -1}" ;;
  *) cat "$BATS_TEST_TMPDIR/rows" ;;
esac
STUB
  # claude and tmux record how they were called (and claude where)
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "$PWD" "$*" >> "%s/calls"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  printf '#!/usr/bin/env bash\nprintf "tmux %%s\\n" "$*" >> "%s/calls"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude-config"
}

plain() { sed 's/\x1b\[[0-9;:]*m//g'; }
src() { FZX_MODE="${1:-all}" "$CLAUDE/source.sh" | plain; }
claude_fn() {
  bash -c 'source "$FZX_REPO/lib/core.sh"; fzx::require log config; fzx::config_load "$1" claude; source "$1/actions.sh"; shift; "$@"' _ "$CLAUDE" "$@"
}

@test "first open: scans into the cache; rows by last session, path first, sessions-only marked" {
  run src
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ -s "$FZX_CACHE_DIR/claude/projects" ]
  [[ "${lines[0]}" == "$P/alpha"$'\t''alpha '*'git'*'0.2.0'*'⎇ main'*'1h'*'4'*'● 3 ↑ 1 ☐ 2 !1'* ]]
  [[ "${lines[1]}" == "$P/gamma"$'\t''gamma*'*'plain'*'4w'*'2'* ]]
  [[ "${lines[2]}" == "$P/beta"$'\t''beta '*'dotbare'*'1.0.0'* ]]
}

@test "later opens serve the cache without scanning" {
  src > /dev/null
  src > /dev/null
  [ "$(wc -l < "$BATS_TEST_TMPDIR/scans")" -eq 1 ]
}

@test "modes: own drops sessions-only projects, active keeps recent or unfinished work" {
  run src own
  [ "${#lines[@]}" -eq 2 ] && [[ "$output" != *gamma* ]]
  run src active
  [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == "$P/alpha"* ]]
  mkdir -p "$FZX_CONFIG_DIR/modules/claude"
  echo 'FZX_CLAUDE_ACTIVE_DAYS=60' > "$FZX_CONFIG_DIR/modules/claude/config.sh"
  run src active
  [ "${#lines[@]}" -eq 2 ]
}

@test "sort by name, the sorted column underlined" {
  FZX_SORT=name run src
  [[ "${lines[0]}" == *alpha* && "${lines[1]}" == *beta* && "${lines[2]}" == *gamma* ]]
  run bash -c "FZX_SORT=name '$CLAUDE/source.sh' | grep alpha"
  [[ "$output" == *$'\e[4malpha\e[0m'* ]]
  run bash -c "'$CLAUDE/source.sh' | grep alpha"
  [[ "$output" == *$'\e[4m1h\e[0m'* ]]
}

@test "refresh: once per TTL, true only when the rows changed; a failed scan keeps the cache" {
  run claude_fn claude::refresh
  [ "$status" -eq 0 ]
  run claude_fn claude::refresh
  [ "$status" -eq 1 ]
  run claude_fn claude::refresh force
  [ "$status" -eq 1 ]
  sed -i 's/0\.2\.0/0.3.0/' "$BATS_TEST_TMPDIR/rows"
  run claude_fn claude::refresh force
  [ "$status" -eq 0 ]
  grep -q 0.3.0 "$FZX_CACHE_DIR/claude/projects"
  : > "$BATS_TEST_TMPDIR/rows"
  run claude_fn claude::refresh force
  [ "$status" -eq 1 ]
  grep -q 0.3.0 "$FZX_CACHE_DIR/claude/projects"
}

@test "no claude-projects: nothing listed, and the menu leaves the module out" {
  rm "$BATS_TEST_TMPDIR/bin/claude-projects"
  run bash -c "PATH='$BATS_TEST_TMPDIR/bin:/usr/bin:/bin' '$CLAUDE/source.sh' 2> /dev/null"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run bash -c "PATH='$BATS_TEST_TMPDIR/bin:/usr/bin:/bin'; source '$CLAUDE/manifest.sh'; claude::applicable"
  [ "$status" -ne 0 ]
}

@test "summary: projects and yours, and the ones in use" {
  src > /dev/null
  run bash -c "source '$CLAUDE/manifest.sh'; claude::summary claude"
  [ "$output" = "3 projects, 2 yours" ]
  run bash -c "source '$CLAUDE/manifest.sh'; claude::summary claude:active"
  [ "$output" = "1 in use" ]
}

@test "preview: kind, version, TODO items by priority and the recent sessions' titles" {
  src > /dev/null
  local sdir="$CLAUDE_CONFIG_DIR/projects/${P//[^A-Za-z0-9-]/-}-alpha"
  mkdir -p "$sdir"
  printf '%s\n' '{"type":"user","cwd":"x"}' '{"type":"custom-title","customTitle":"alpha-work","sessionId":"s"}' \
    '{"type":"last-prompt","lastPrompt":"fix   the\nthing","sessionId":"s"}' > "$sdir/s1.jsonl"
  printf '%s\n' '{"type":"last-prompt","lastPrompt":"only a prompt","sessionId":"t"}' > "$sdir/s2.jsonl"
  touch -d '2 days ago' "$sdir/s2.jsonl"
  run bash -c "'$CLAUDE/preview.sh' '$P/alpha' | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'alpha  git  0.2.0'* ]]
  [[ "$output" == *'TODO (2 open, 1 P1)'*'P1 Two.'*'P3 One.'* ]]
  [[ "$output" == *'Sessions (4)'*'alpha-work'*'fix the thing'*'only a prompt'* ]]
}

@test "preview: a sessions-only project with no transcripts here, and a missing directory" {
  src > /dev/null
  run bash -c "'$CLAUDE/preview.sh' '$P/gamma' | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "$output" == *'gamma (sessions only)  plain'* && "$output" == *'(started in subdirectories)'* ]]
  run "$CLAUDE/preview.sh" "$P/nope"
  [ "$status" -eq 1 ]
}

@test "claude action in tmux: a window per project, named after it, in its directory" {
  TMUX=1 run "$CLAUDE/actions.sh" claude "$P/alpha" "$P/beta"
  [ "$status" -eq 0 ]
  grep -qxF "tmux new-window -c $P/alpha -n alpha -- claude" "$BATS_TEST_TMPDIR/calls"
  grep -qxF "tmux new-window -c $P/beta -n beta -- claude" "$BATS_TEST_TMPDIR/calls"
  TMUX=1 run "$CLAUDE/actions.sh" resume "$P/alpha"
  grep -qxF "tmux new-window -c $P/alpha -n alpha -- claude --continue" "$BATS_TEST_TMPDIR/calls"
}

@test "claude action outside tmux: runs here in the first project; bad paths are refused" {
  run "$CLAUDE/actions.sh" resume "$P/beta" "$P/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" == *'starting in'* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "$P/beta|--continue" ]
  run "$CLAUDE/actions.sh" claude "$P/nope"
  [ "$status" -eq 2 ]
}

@test "card action: claude-projects show per project in the pager" {
  PAGER=cat run "$CLAUDE/actions.sh" card "$P/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CARD $P/alpha"* ]]
}

@test "under fzx: the scan is bound to start, enter prints the path, alt-l opens git on the project" {
  stub_fzf
  run "$FZX" -m claude
  [ "$status" -eq 0 ]
  fzf_binds start | grep -qxF "start:+bg-transform:$FZX _cb transform refresh"
  [ "$(fzf_bind alt-l)" = "alt-l:transform:$FZX _cb nav goto git {1}" ]
  [ "$(fzf_bind alt-t)" = "alt-t:transform:$FZX _cb nav goto todos --dir {1}" ]
  [ "$(fzf_bind ctrl-o)" = "ctrl-o:execute($FZX _cb action claude {+1})" ]
}
