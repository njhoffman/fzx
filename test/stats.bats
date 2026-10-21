#!/usr/bin/env bats
# step 4: usage statistics rows and the `fzx stats` summary

load test_helper

COUNTER_DIR="$(readlink -f "$BATS_TEST_DIRNAME/fixtures/modules/counter")"

setup() {
  setup_fzx
  stub_fzf
  STATS="$FZX_STATE_DIR/stats.tsv"
}

# rows for one event as "module mode count detail", in file order
rows() {
  awk -F'\t' -v e="$1" '$6 == e { print $4, $5, $8, $9 }' "$STATS"
}

# a kept session, attached in the test shell
kept_session() {
  "$FZX" --keep -m counter "$@"
  SID="$(basename "$(session_dirs)")"
  load_libs log session
  fzx::session_attach "$SID"
}

@test "a run records start and exit with the right root, duration and outcome" {
  STUB_FZF_OUT=x run "$FZX" -m counter:two --x
  [ "$(rows start)" = "counter two - counter --x" ]
  [ "$(rows exit)" = "counter two - rc:0 accept" ]
  local root sid
  root="$(awk -F'\t' '$6 == "start" { print $2 }' "$STATS")"
  sid="$(awk -F'\t' '$6 == "exit" { print $3 }' "$STATS")"
  [ "$root" = "$sid" ]
  [[ "$(awk -F'\t' '$6 == "exit" { print $7 }' "$STATS")" =~ ^[0-9]+$ ]]
}

@test "exit kinds: abort, nomatch, error" {
  STUB_FZF_RC=130 run "$FZX" -m counter
  STUB_FZF_RC=1 run "$FZX" -m counter
  STUB_FZF_RC=2 run "$FZX" -m counter
  [ "$(rows exit | cut -d' ' -f4- | tr '\n' ',')" = "rc:130 abort,rc:1 nomatch,rc:2 error," ]
}

@test "the exit row names the session the user ended in" {
  local nav="n=\$(cat \"\$BATS_TEST_TMPDIR/calls\" 2> /dev/null || echo 0); echo \$((n + 1)) > \"\$BATS_TEST_TMPDIR/calls\"; if [ \"\$n\" -eq 0 ]; then c=\$('$FZX' _cb nav goto counter:three --y); c=\${c% -m*}; '$FZX' --resume \${c##* } -m :three; exit \$?; fi"
  STUB_FZF_RUN="$nav" STUB_FZF_RC=130 run "$FZX" -m counter
  [ "$(rows exit)" = "counter three - rc:130 abort" ]
  [ "$(rows nav)" = "counter one - goto:counter:three" ]
}

@test "--dry-run and failed starts record nothing" {
  run "$FZX" -m counter --dry-run
  run "$FZX" -m counter:nine
  [ ! -s "$STATS" ]
}

@test "FZX_STATS=0 records nothing, including from callbacks" {
  FZX_STATS=0 STUB_FZF_RUN="'$FZX' _cb load > /dev/null" run "$FZX" -m counter
  [ ! -s "$STATS" ]
}

@test "FZX_STATS=0 in the user config turns recording off" {
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_STATS=0' > "$FZX_CONFIG_DIR/config.sh"
  STUB_FZF_RUN="'$FZX' _cb load > /dev/null" run "$FZX" -m counter
  [ ! -s "$STATS" ]
}

@test "load: a miss records source, a hit records cache; ctrl-r records reload" {
  kept_session
  "$FZX" _cb load > /dev/null
  "$FZX" _cb load > /dev/null
  "$FZX" _cb source > /dev/null
  [ "$(rows source | tr '\n' ',')" = "counter one 2 miss,counter one 2 reload," ]
  [ "$(rows cache)" = "counter one 2 session" ]
}

@test "a persistent cache hit is recorded as such" {
  mkdir -p "$FZX_CONFIG_DIR/modules/counter"
  echo 'FZX_PERSIST=cache:1h' > "$FZX_CONFIG_DIR/modules/counter/config.sh"
  STUB_FZF_RUN="'$FZX' _cb load > /dev/null" run "$FZX" -m counter
  STUB_FZF_RUN="'$FZX' _cb load > /dev/null" run "$FZX" -m counter
  [ "$(rows cache)" = "counter one 2 persistent" ]
}

@test "a failing source is recorded with its exit code; persist=none has no line count" {
  kept_session
  COUNTER_FAIL=1 "$FZX" _cb source > /dev/null || true
  [ "$(rows source)" = "counter one - fail:3" ]
  fzx::meta_set persist none
  "$FZX" _cb load > /dev/null
  [ "$(rows source | tail -n 1)" = "counter one - miss" ]
}

@test "actions record item count and exit code" {
  kept_session
  "$FZX" _cb action mark a b c
  "$FZX" _cb action fail a || true
  [ "$(rows action | tr '\n' ',')" = "counter one 3 mark:0,counter one 1 fail:1," ]
}

@test "mode switches record from>to, with :restart when fzf restarts" {
  kept_session
  "$FZX" _cb mode next > /dev/null
  "$FZX" _cb mode next > /dev/null
  [ "$(rows mode | tr '\n' ',')" = "counter one - one>two,counter two - two>three:restart," ]
}

@test "navigation records resume, back, back:none and placement changes" {
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_PLACEMENTS=(inline popup)' >> "$FZX_CONFIG_DIR/config.sh"
  kept_session
  "$FZX" _cb nav resume > /dev/null
  "$FZX" _cb nav back > /dev/null
  TMUX=fake "$FZX" _cb nav popout > /dev/null
  TMUX=fake "$FZX" _cb nav popout > /dev/null
  local child
  child="$("$FZX" _cb nav goto counter --x)"
  FZX_SESSION="${child##* }" "$FZX" _cb nav back > /dev/null
  [ "$(rows nav | cut -d' ' -f4 | tr '\n' ',')" = "resume,back:none,placement:popup,placement:inline,goto:counter,back," ]
}

@test "previews are not recorded" {
  kept_session
  "$FZX" _cb preview x > /dev/null
  [ ! -s "$STATS" ] || [ -z "$(rows preview)" ]
}

@test "tabs and newlines in details are flattened" {
  kept_session $'a\tb' $'c\nd'
  [ "$(awk -F'\t' 'END { print NF }' "$STATS")" = 9 ]
  [ "$(wc -l < "$STATS")" -eq 1 ] || [ "$(rows start | wc -l)" -eq 1 ]
}

# fixture rows: ts root sid module mode event duration count detail
write_stats() {
  local now=$((EPOCHSECONDS * 1000)) old=$(((EPOCHSECONDS - 30 * 86400) * 1000))
  mkdir -p "$FZX_STATE_DIR"
  {
    printf '%s\tr1\tr1\tps\tuser\tstart\t0\t-\tps\n' "$now"
    printf '%s\tr1\tr1\tps\tuser\tsource\t100\t300\tmiss\n' "$now"
    printf '%s\tr1\tr1\tps\tuser\tsource\t300\t100\treload\n' "$now"
    printf '%s\tr1\tr1\tps\tuser\tcache\t2\t300\tsession\n' "$now"
    printf '%s\tr1\tr1\tps\tuser\tcache\t2\t300\tsession\n' "$now"
    printf '%s\tr1\tr1\tps\tuser\tcache\t2\t300\tsession\n' "$now"
    printf '%s\tr1\tr1\tps\tuser\taction\t5\t2\tterm:0\n' "$now"
    printf '%s\tr1\tr1\tps\tuser\tmode\t3\t-\tuser>all\n' "$now"
    printf '%s\tr1\tc1\tgit\tlog\tsource\t50\t10\tmiss\n' "$now"
    printf '%s\tr1\tc1\tgit\tlog\texit\t65000\t-\trc:0 accept\n' "$now"
    printf '%s\tr2\tr2\tps\tall\tstart\t0\t-\tps\n' "$now"
    printf '%s\tr2\tr2\tps\tall\tsource\t1\t-\tfail:2\n' "$now"
    printf '%s\tr2\tr2\tps\tall\texit\t1500\t-\trc:130 abort\n' "$now"
    printf '%s\tr0\tr0\told\tmain\tstart\t0\t-\told\n' "$old"
  } > "$STATS"
}

@test "stats: summary per module" {
  write_stats
  run "$FZX" stats
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == MODULE* ]]
  [[ "${lines[1]}" =~ ^ps\ +2\  ]]
  [[ "${lines[1]}" == *" 33.2s/1m05s "* ]]
  [[ "${lines[1]}" == *" 2 200ms/300ms (1 failed) "* ]]
  [[ "${lines[1]}" =~ \ 200\ +75%\ +1/1\ +1\ +1$ ]]
  [[ "${lines[2]}" =~ ^old\ +1\  ]]
  [[ "${lines[3]}" =~ ^git\ +0\  ]]
}

@test "stats: --since and --module filter rows" {
  write_stats
  run "$FZX" stats --since 7d
  [[ "$output" != *old* ]]
  run "$FZX" stats --module git
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" =~ ^git ]]
}

@test "stats: --raw prints a header and the matching rows" {
  write_stats
  run "$FZX" stats --raw --module git
  [ "${lines[0]}" = $'ts_ms\troot\tsid\tmodule\tmode\tevent\tduration_ms\tcount\tdetail' ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "stats: no file yet, bad options" {
  run "$FZX" stats
  [ "$status" -eq 0 ]
  [[ "$output" == "no stats recorded yet"* ]]
  run "$FZX" stats --since soon
  [ "$status" -eq 2 ]
  run "$FZX" stats --bogus
  [ "$status" -eq 2 ]
}

@test "gc prunes old rows once the stats file passes 1 MiB" {
  mkdir -p "$FZX_STATE_DIR"
  local old=$(((EPOCHSECONDS - 200 * 86400) * 1000)) now=$((EPOCHSECONDS * 1000))
  awk -v old="$old" -v pad="$(printf '%0100d' 0)" 'BEGIN { for (i = 0; i < 12000; i++) printf "%s\tr\tr\tm\tx\tsource\t1\t1\t%s\n", old, pad }' > "$STATS"
  printf '%s\tr\tr\tm\tx\tstart\t0\t-\tkeep\n' "$now" >> "$STATS"
  run "$FZX" gc
  [ "$(wc -l < "$STATS")" -eq 1 ]
  grep -q keep "$STATS"
}

@test "gc leaves a small stats file alone" {
  write_stats
  run "$FZX" gc
  [ "$(wc -l < "$STATS")" -eq 14 ]
}
