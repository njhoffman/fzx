#!/usr/bin/env bats
# the history module over a fixture zsh-histdb database

load test_helper

HIST="$(readlink -f "$BATS_TEST_DIRNAME/../modules/history")"

setup() {
  command -v sqlite3 > /dev/null || skip "sqlite3 not installed"
  setup_fzx
  export FZX_HISTDB_FILE="$BATS_TEST_TMPDIR/hist.db" HOST=here
  W="$BATS_TEST_TMPDIR/work"
  mkdir -p "$W/a_b/sub" "$W/aXb"
  ln -s "$W/a_b" "$BATS_TEST_TMPDIR/link"
  local now day=86400
  now="$(date +%s)"
  # places: 1 here:a_b, 2 here:a_b/sub, 3 here:aXb (a LIKE "_" trap), 4 there:a_b (another host)
  sqlite3 "$FZX_HISTDB_FILE" << SQL
create table commands (id integer primary key autoincrement, argv text, unique(argv) on conflict ignore);
create table places (id integer primary key autoincrement, host text, dir text, unique(host, dir) on conflict ignore);
create table history (id integer primary key autoincrement, session int, command_id int, place_id int,
  exit_status int, start_time int, duration int);
insert into places (host, dir) values ('here', '$W/a_b'), ('here', '$W/a_b/sub'), ('here', '$W/aXb'), ('there', '$W/a_b');
insert into commands (argv) values ('make test'), ('echo one
echo two'), ('false'), ('ls -la'), ('remote only');
insert into history (session, command_id, place_id, exit_status, start_time, duration) values
  (1, 1, 1, 0, $((now - 3 * day)), 4),
  (2, 1, 2, 0, $((now - 60)), 400),
  (2, 2, 1, 0, $((now - 120)), 1),
  (2, 3, 1, 1, $((now - 30)), 0),
  (1, 4, 3, 0, $((now - 400 * day)), 0),
  (3, 5, 4, 0, $((now - 10)), 0);
SQL
}

plain() { sed 's/\x1b\[[0-9;]*m//g'; }
src() { FZX_MODE="$1" "$HIST/source.sh" | plain; }

@test "host: one row per command, the latest run's id, newest first, run counts" {
  run src host
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  # false (30s ago), make test (latest run is id 2), the two-line echo, ls -la
  [[ "${lines[0]}" == 4$'\t'*'false' ]]
  # the failed column: blank on a run that succeeded
  [[ "${lines[1]}" == 2$'\t'*' 2x    make test' ]]
  [[ "${lines[2]}" == 3$'\t'*'echo one ↵ echo two' ]]
  [[ "${lines[3]}" == 5$'\t'*'ls -la' ]]
  [[ "$output" != *'remote only'* ]]
}

@test "times: HH:MM today, MM/DD this year, MM/DD/YY before" {
  run src host
  [[ "${lines[0]}" =~ $'\t'\ +[0-9]{2}:[0-9]{2}\  ]]
  [[ "${lines[3]}" =~ $'\t'\ *[0-9]{2}/[0-9]{2}/[0-9]{2}\  ]]
}

@test "a failed latest run is red, with the failed icon" {
  run bash -c "FZX_MODE=host FZX_ICONS=unicode '$HIST/source.sh'"
  [[ "${lines[0]}" == *$'\e[38;5;203m✗\e[0m \e[38;5;203mfalse\e[0m' ]]
}

@test "global includes other hosts; session follows FZX_HISTDB_SESSION, else the host's latest" {
  run src global
  [[ "$output" == *'remote only'* ]]
  FZX_HISTDB_SESSION=1 run src session
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *'make test'* && "$output" == *'ls -la'* ]]
  run src session
  [[ "$output" == *'false'* && "$output" != *'ls -la'* ]]
}

@test "directory: this directory and below, through a symlink, with LIKE metacharacters literal" {
  cd "$BATS_TEST_TMPDIR/link"
  run src directory
  [ "$status" -eq 0 ]
  [[ "$output" == *'make test'* && "$output" == *'false'* && "$output" == *'echo one'* ]]
  # aXb matches "a_b%" only if "_" is a wildcard; there is another host's run of a_b, too
  [[ "$output" != *'ls -la'* && "$output" != *'remote only'* ]]
  cd "$W/a_b/sub"
  run src directory
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *'make test' ]]
}

@test "failed toggle and frequent sort" {
  FZX_TOGGLES=failed run src host
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *false ]]
  FZX_SORT=frequent run src host
  [[ "${lines[0]}" == *'make test' ]]
}

@test "preview: the command, the latest run and where it ran" {
  run bash -c "'$HIST/preview.sh' 2 | sed 's/\x1b\[[0-9;]*m//g'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'make test'* ]]
  [[ "$output" == *'status     0'* && "$output" == *'duration   400s'* ]]
  [[ "$output" == *"directory  $W/a_b/sub"* ]]
  [[ "$output" == *'runs       2'* ]]
  [[ "$output" == *'directories'*"$W/a_b"* ]]
  run bash -c "'$HIST/preview.sh' 4 | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "$output" == *'status     1'* && "$output" == *'1 failed'* ]]
}

@test "insert prints the exact command, run exits 10, bad ids are refused" {
  run "$HIST/actions.sh" insert 3
  [ "$status" -eq 0 ]
  [ "$output" = $'echo one\necho two' ]
  run "$HIST/actions.sh" run 2
  [ "$status" -eq 10 ]
  [ "$output" = 'make test' ]
  run "$HIST/actions.sh" insert '1;drop table history'
  [ "$status" -eq 2 ]
}

@test "delete forgets every run of the selected commands" {
  run "$HIST/actions.sh" delete 2
  [ "$status" -eq 0 ]
  [ "$(sqlite3 "$FZX_HISTDB_FILE" "select count(*) from history where command_id = 1")" = 0 ]
  [ "$(sqlite3 "$FZX_HISTDB_FILE" "select count(*) from commands where argv = 'make test'")" = 0 ]
  [ "$(sqlite3 "$FZX_HISTDB_FILE" "select count(*) from history")" = 4 ]
}

@test "under fzx: module args are the query, history scheme, the components are there" {
  stub_fzf
  run "$FZX" -m history -- git st
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --query=git st "* && " ${FZF_ARGS[*]} " == *" --scheme=history "* ]]
  [[ "$(fzf_bind alt-enter)" == *'_cb action run'* ]]
  [[ "$(fzf_bind alt-e)" == *'_cb toggle failed'* ]]
}

@test "zsh widget: the scope's mode, the session and the typed text; exit 10 accepts the line" {
  command -v zsh > /dev/null || skip "zsh not installed"
  cat > "$BATS_TEST_TMPDIR/fzxstub" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$FZX_HISTDB_SESSION" "$@" > "$BATS_TEST_TMPDIR/stub.args"
printf 'chosen cmd\n'
exit "${STUB_RC:-0}"
STUB
  chmod +x "$BATS_TEST_TMPDIR/fzxstub"
  # the widget body in a file: quoting it through script -c and zsh -c gets lost
  cat > "$BATS_TEST_TMPDIR/widget.zsh" << ZSH
FZX_ZSH_BIN='$BATS_TEST_TMPDIR/fzxstub'
source '$BATS_TEST_DIRNAME/../shell/fzx.zsh'
function zle { print -r -- "zle \$*"; }
HISTDB_SESSION=42 SHELL_HISTORY_SCOPE=directory LBUFFER='git st'
fzx-history-widget
print -r -- "buffer=\$BUFFER"
ZSH
  export BATS_TEST_TMPDIR
  run script -qec "zsh -f -i '$BATS_TEST_TMPDIR/widget.zsh'" /dev/null
  [[ "$output" == *'zle reset-prompt'* && "$output" == *'buffer=chosen cmd'* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/stub.args")" = $'42\n-m\nhistory:directory\n--\ngit st' ]
  STUB_RC=10 run script -qec "zsh -f -i '$BATS_TEST_TMPDIR/widget.zsh'" /dev/null
  [[ "$output" == *'zle accept-line'* ]]
}
