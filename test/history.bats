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
  # false (30s ago), make test (latest run is id 2), the two-line echo, ls -la; the command in field 3
  [[ "${lines[0]}" == 4$'\t'*$'\tfalse' ]]
  [[ "${lines[1]}" == 2$'\t'*' 2x '*$'\tmake test' ]]
  [[ "${lines[2]}" == 3$'\t'*$'\techo one ↵ echo two' ]]
  [[ "${lines[3]}" == 5$'\t'*$'\tls -la' ]]
  [[ "$output" != *'remote only'* ]]
  # host mode has no host column
  [[ "$output" != *here* ]]
}

@test "ages: seconds, minutes, days and years since the latest run; the latest run's duration" {
  run src host
  [[ "$(cut -f2 <<< "${lines[0]}")" =~ ^\ +3[0-9]s\  ]]
  [[ "$(cut -f2 <<< "${lines[1]}")" =~ ^\ +1m\ +2x\ +6m\ $ ]]
  [[ "$(cut -f2 <<< "${lines[2]}")" =~ ^\ +2m\ +1s\ $ ]]
  [[ "$(cut -f2 <<< "${lines[3]}")" =~ ^\ +1y\  ]]
}

@test "a failed latest run is red, with the failed icon" {
  run bash -c "FZX_MODE=host FZX_ICONS=unicode '$HIST/source.sh'"
  [[ "${lines[0]}" == *$'\e[38;5;203m✗\e[0m '*$'\t\e[38;5;203mfalse\e[0m' ]]
}

@test "commands are colored by their parts" {
  sqlite3 "$FZX_HISTDB_FILE" "insert into commands (argv) values ('sudo git log -n 3 \"\$HOME/a b\" | less; echo \$X');
    insert into history (session, command_id, place_id, exit_status, start_time, duration)
      values (2, 6, 1, 0, $(date +%s), 0)"
  run bash -c "FZX_MODE=host '$HIST/source.sh' | sed '1!d' | cut -f3"
  local C=$'\e[1;38;5;255m' O=$'\e[38;5;110m' Q=$'\e[38;5;150m' P=$'\e[38;5;221m' A=$'\e[38;5;250m' V=$'\e[38;5;116m' E=$'\e[0m'
  [ "$output" = "${C}sudo$E ${C}git$E ${A}log$E ${O}-n$E ${A}3$E ${Q}\"\$HOME/a$E ${Q}b\"$E ${P}|$E ${C}less$E${P};$E ${C}echo$E ${V}\$X$E" ]
}

@test "global (the default) includes other hosts, each row naming its host; session follows FZX_HISTDB_SESSION, else the host's latest" {
  run src global
  [[ "$output" == *'remote only'* ]]
  [[ "$(grep 'remote only' <<< "$output" | cut -f2)" == *' there ' ]]
  [[ "$(grep 'make test' <<< "$output" | cut -f2)" == *' here  ' ]]
  FZX_MODE='' run "$HIST/source.sh"
  [ "${#lines[@]}" -eq 5 ]
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

@test "failed and succeeded toggles; frequent and frecent sorts; the runs toggle" {
  FZX_TOGGLES=failed run src host
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *false ]]
  FZX_TOGGLES=succeeded run src host
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" != *false* ]]
  FZX_SORT=frequent run src host
  [[ "${lines[0]}" == *'make test' ]]
  # frecent: make test ran twice, but 3 days ago and a minute ago; false ran once, 30s ago
  sqlite3 "$FZX_HISTDB_FILE" "insert into history (session, command_id, place_id, exit_status, start_time, duration)
    values (1, 4, 3, 0, $(($(date +%s) - 401 * 86400)), 0), (1, 4, 3, 0, $(($(date +%s) - 402 * 86400)), 0)"
  FZX_SORT=frequent run src host
  [[ "${lines[0]}" == *'ls -la' ]]
  FZX_SORT=frecent run src host
  [[ "${lines[0]}" == *'make test' && "${lines[3]}" == *'ls -la' ]]
  # the sorted column underlined: the count, or the age
  run bash -c "FZX_MODE=host FZX_SORT=frequent '$HIST/source.sh' | sed '1!d'"
  [[ "$output" == *$'\e[38;5;244;4m3x\e[0m'* ]]
  run bash -c "FZX_MODE=host '$HIST/source.sh' | sed '1!d'"
  [[ "$output" =~ $'\e[38;5;'[0-9]+$';4m'[0-9]+[smhdwy]o?$'\e[0m' ]]
  # every run, newest first, without counts
  FZX_TOGGLES=runs run src host
  [ "${#lines[@]}" -eq 7 ]
  [ "$(cut -f1 <<< "$output" | tr '\n' ' ')" = "4 2 3 1 5 7 8 " ]
  [[ "$output" != *x\ * ]]
}

@test "host and global are cached: the runs added since lead, a command run again moves up, delete drops the cache" {
  run src global
  [ "${#lines[@]}" -eq 5 ]
  [ -s "$FZX_CACHE_DIR/history/global.rows" ]
  [ "$(cat "$FZX_CACHE_DIR/history/global.last")" = 6 ]
  # nothing ran since: the same rows
  run src global
  [ "${#lines[@]}" -eq 5 ]
  sqlite3 "$FZX_HISTDB_FILE" "insert into history (session, command_id, place_id, exit_status, start_time, duration)
    values (2, 4, 1, 0, $(date +%s), 0)"
  run src global
  [ "${#lines[@]}" -eq 5 ]
  [[ "${lines[0]}" == 7$'\t'*' 2x '*$'\tls -la' ]]
  [ "$(grep -c 'ls -la' <<< "$output")" -eq 1 ]
  [ "$(cat "$FZX_CACHE_DIR/history/global.last")" = 7 ]
  # what the cache holds is what a fresh read gives
  # (ids and commands: the ages move on)
  local cached
  cached="$(cut -f1,3 <<< "$output")"
  rm -rf "$FZX_CACHE_DIR/history"
  run src global
  [ "$(cut -f1,3 <<< "$output")" = "$cached" ]
  # a database with fewer runs than the cache knows (replaced) is read whole
  printf '99\n' > "$FZX_CACHE_DIR/history/global.last"
  run src global
  [ "$(cut -f1,3 <<< "$output")" = "$cached" ]
  # deleting forgets the cached rows too
  "$HIST/actions.sh" delete 7
  [ ! -e "$FZX_CACHE_DIR/history/global.rows" ]
  run src global
  [[ "$output" != *'ls -la'* ]]
}

@test "a cache written while fzf stops reading is complete" {
  FZX_MODE=global "$HIST/source.sh" | head -1 > /dev/null
  [ "$(wc -l < "$FZX_CACHE_DIR/history/global.rows")" -eq 5 ]
}

@test "preview: the command, the latest run, its success rate, median, recent runs and where it ran" {
  run bash -c "'$HIST/preview.sh' 2 | sed 's/\x1b\[[0-9;]*m//g'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'make test'* ]]
  [[ "$output" == *'status     0'* && "$output" == *'duration   400s'* ]]
  [[ "$output" == *"directory  $W/a_b/sub"* ]]
  [[ "$output" == *'runs       2   100% ok'* ]]
  [[ "$output" == *'median     400s'* ]]
  [[ "$output" == *'recent runs'* ]]
  [[ "$output" =~ [0-9:]+\ +0\ +400s\ +here\ +$W/a_b/sub ]]
  [[ "$output" =~ [0-9:]+\ +0\ +4s\ +here\ +$W/a_b$'\n' ]]
  [[ "$output" == *'directories'*"$W/a_b"* ]]
  run bash -c "'$HIST/preview.sh' 4 | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "$output" == *'status     1'* && "$output" == *'1 failed'* ]]
}

@test "cd prints the command after a cd into the directory it ran in, ~ for home" {
  run "$HIST/actions.sh" cd 2
  [ "$status" -eq 0 ]
  [ "$output" = "cd $(printf '%q' "$W/a_b/sub") && make test" ]
  sqlite3 "$FZX_HISTDB_FILE" "insert into places (host, dir) values ('here', '$HOME/x y');
    insert into history (session, command_id, place_id, exit_status, start_time, duration) values (2, 4, 5, 0, 1, 0)"
  run "$HIST/actions.sh" cd 7
  [ "$output" = 'cd ~/x\ y && ls -la' ]
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
  # only the command is searched
  [[ " ${FZF_ARGS[*]} " == *" --with-nth=2.. --nth=2 --tabstop=1 "* ]]
  [[ "$(fzf_bind alt-enter)" == *'_cb action run'* ]]
  [[ "$(fzf_bind alt-c)" == "alt-c:become($FZX _cb action cd {+1})" ]]
  [[ "$(fzf_bind ctrl-y)" == *'_cb notify copy'* ]]
  [[ "$(fzf_bind alt-e)" == *'_cb toggle failed'* ]]
  [[ "$(fzf_bind alt-s)" == *'_cb toggle succeeded'* ]]
  [[ "$(fzf_bind alt-a)" == *'_cb toggle runs'* ]]
}

@test "zsh widget: global unless FZX_ZSH_HISTORY_MODE says otherwise, the session and the typed text; exit 10 accepts the line" {
  command -v zsh > /dev/null || skip "zsh not installed"
  cat > "$BATS_TEST_TMPDIR/fzxstub" << 'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "$FZX_HISTDB_SESSION" "$*" >> "$BATS_TEST_TMPDIR/stub.args"
printf 'chosen cmd\n'
exit "${STUB_RC:-0}"
STUB
  chmod +x "$BATS_TEST_TMPDIR/fzxstub"
  # the widget body in a file: quoting it through script -c and zsh -c gets lost
  cat > "$BATS_TEST_TMPDIR/widget.zsh" << ZSH
FZX_ZSH_BIN='$BATS_TEST_TMPDIR/fzxstub'
source '$BATS_TEST_DIRNAME/../shell/fzx.zsh'
function zle { print -r -- "zle \$*"; }
HISTDB_SESSION=42 LBUFFER='git st'
fzx-history-widget
print -r -- "buffer=\$BUFFER"
LBUFFER=''
FZX_ZSH_HISTORY_MODE=directory fzx-history-widget
FZX_ZSH_HISTORY_MODE=bogus fzx-history-widget
ZSH
  export BATS_TEST_TMPDIR
  run script -qec "zsh -f -i '$BATS_TEST_TMPDIR/widget.zsh'" /dev/null
  [[ "$output" == *'zle reset-prompt'* && "$output" == *'buffer=chosen cmd'* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/stub.args")" = $'42|-m history:global -- git st\n42|-m history:directory\n42|-m history:global' ]
  STUB_RC=10 run script -qec "zsh -f -i '$BATS_TEST_TMPDIR/widget.zsh'" /dev/null
  [[ "$output" == *'zle accept-line'* ]]
}

@test "interrupted runs (130, 141) are neither failed nor red; FZX_HISTORY_INTERRUPTED sets the codes" {
  sqlite3 "$FZX_HISTDB_FILE" "insert into commands (argv) values ('fzf'), ('yes | head');
    insert into history (session, command_id, place_id, exit_status, start_time, duration) values
      (2, 6, 1, 0, $(($(date +%s) - 9)), 1), (2, 6, 1, 130, $(($(date +%s) - 8)), 2),
      (2, 6, 1, 1, $(($(date +%s) - 7)), 2), (2, 6, 1, 130, $(($(date +%s) - 6)), 2),
      (2, 7, 1, 141, $(($(date +%s) - 5)), 0)"
  run bash -c "FZX_MODE=host FZX_ICONS=unicode '$HIST/source.sh'"
  [[ "${lines[0]}" == 11$'\t'*$'\e[38;5;179m⊘\e[0m '*$'\t\e[1;38;5;255myes\e[0m '* ]]
  [[ "${lines[1]}" == 10$'\t'*'4x'*$'⊘'*$'\t\e[1;38;5;255mfzf\e[0m' ]]
  FZX_TOGGLES=failed run src host
  [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == *$'\tfalse' ]]
  FZX_TOGGLES=succeeded run src host
  [[ "$output" == *$'\tfzf'* && "$output" == *$'\tyes | head'* ]]
  # with no codes, 130 is a failure like any other
  FZX_HISTORY_INTERRUPTED='' FZX_TOGGLES=failed run src host
  [ "${#lines[@]}" -eq 3 ]
  # the preview: the status named, the interrupted runs counted apart and left out of the success rate
  run bash -c "'$HIST/preview.sh' 10 | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "$output" == *'status     130 interrupted'* ]]
  [[ "$output" == *'runs       4   1 failed   2 interrupted   50% ok'* ]]
}
