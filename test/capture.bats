#!/usr/bin/env bats
# the capture module on a private tmux server with an empty config; never the user's tmux server

load test_helper

setup() {
  setup_fzx
  export FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null NO_COLOR=1
  unset TMUX_PANE FZX_TMUX_PANE FZX_TOGGLES
  CAP="$FZX_REPO/modules/capture"
  export TEST_TMUX_BIN="$(command -v tmux)" TEST_TMUX_SOCKET="$BATS_TEST_TMPDIR/tmux.sock"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" << 'STUB'
#!/usr/bin/env bash
exec "$TEST_TMUX_BIN" -S "$TEST_TMUX_SOCKET" "$@"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  tmux -f /dev/null new-session -d -s cap -x 120 -y 10 'bash --noprofile --norc'
  tmux set-option -g history-limit 5000
  PANE="$(tmux display-message -p -t cap '#{pane_id}')"
  export TMUX_PANE="$PANE"
}

teardown() {
  tmux kill-server 2> /dev/null || :
}

# type a command into the pane and wait for its last line
fill() {
  local n
  tmux send-keys -t "${2:-$PANE}" "clear; $1; echo cap-done" Enter
  for n in {1..100}; do
    [[ "$(tmux capture-pane -p -J -S - -t "${2:-$PANE}")" == *$'\ncap-done'* ]] && return 0
    sleep 0.02
  done
  return 1
}
src() { FZX_MODE="$1" "$CAP/source.sh" "${@:2}"; }

@test "menu: a summary per entry from the active pane, keyed by the pane and its output" {
  source "$CAP/manifest.sh"
  fill 'echo see https://example.com/a and /tmp/x.txt'
  run capture::summary capture:urls
  [ "$output" = "1 URLs" ]
  run capture::summary capture:paths
  [[ "$output" =~ ^[1-9][0-9]*\ paths$ ]]
  local k1 k2
  k1="$(capture::summary_key capture)"
  [[ "$k1" == "$PANE:"* ]]
  fill 'seq 30'
  k2="$(capture::summary_key capture)"
  [ "$k1" != "$k2" ]
  # under the menu's session the source still reads the pane (no session state of its own)
  fill 'echo https://example.com/b'
  FZX_SESSION=nope FZX_SESSION_DIR="$BATS_TEST_TMPDIR/nope" run capture::summary capture:urls
  [ "$output" = "$(capture::summary capture:urls)" ] && [ "$output" != "0 URLs" ]
}

@test "lines: the screen first, newest first, then the scrollback nearest first, each with its place" {
  fill "for i in \$(seq 1 30); do echo row-\$i; done"
  run src lines
  [ "$status" -eq 0 ]
  # the 10-line screen holds row-23..row-30, cap-done and the prompt; scrollback above it
  [[ "${lines[0]}" == *$'\t'"   vis  "* ]]
  local first_off
  first_off="$(printf '%s\n' "${lines[@]}" | grep -m1 -v $'\t   vis  ')"
  [[ "$first_off" == row-22$'\t'"    ↑1  row-22"$'\t'* ]]
  [[ "$output" == *row-1$'\t'"   ↑22  row-1"$'\t'* ]]
  # the screen lines come newest first
  local i30 i23
  i30="$(printf '%s\n' "${lines[@]}" | grep -n '^row-30' | cut -d: -f1)"
  i23="$(printf '%s\n' "${lines[@]}" | grep -n '^row-23' | cut -d: -f1)"
  ((i30 < i23))
  # the y field: 0 is the screen's top, the scrollback negative
  [[ "$output" == *row-22$'\t'*$'\t'-1* ]]
}

@test "visible toggle: the screen only; FZX_CAPTURE_LINES bounds the scrollback" {
  fill "for i in \$(seq 1 30); do echo row-\$i; done"
  FZX_TOGGLES=visible run src lines
  [[ "$output" == *row-30* && "$output" != *row-22* ]]
  FZX_CAPTURE_LINES=5 run src lines
  [[ "$output" == *row-18* && "$output" != *row-17$'\t'* ]]
}

@test "copy mode: the scrolled view is the screen, lines below it are marked down" {
  fill "for i in \$(seq 1 30); do echo row-\$i; done"
  tmux copy-mode -t "$PANE"
  tmux send-keys -t "$PANE" -X scroll-up
  tmux send-keys -t "$PANE" -X scroll-up
  tmux send-keys -t "$PANE" -X scroll-up
  run src lines
  [[ "$output" == *row-21$'\t'"   vis  "* ]]
  [[ "$output" == *cap-done$'\t'"    ↓"* ]]
  FZX_TOGGLES=visible run src lines
  [[ "$output" != *cap-done* ]]
}

@test "extraction: urls with queries, paths with line numbers, hashes, valid ips, words; the nearest copy wins" {
  fill "printf '%s\n' 'https://example.test/a?q=1&b=2' '/tmp/with-file.txt:42' 'README.md' 'abcdef123456 192.168.1.3 999.2.3.4'; for i in \$(seq 1 15); do echo pad; done; echo https://example.test/a?q=1\&b=2"
  run src urls
  [ "$(printf '%s\n' "${lines[@]}" | grep -c '^https://example.test/a?q=1&b=2')" -eq 1 ]
  [[ "$output" == 'https://example.test/a?q=1&b=2'$'\t'"   vis  "* ]]
  run src paths
  [[ "$output" == *'/tmp/with-file.txt:42'$'\t'* && "$output" == *'README.md'$'\t'* ]]
  run src hashes
  [[ "$output" == *'abcdef123456'$'\t'* ]]
  run src ips
  [[ "$output" == *'192.168.1.3'$'\t'* && "$output" != *'999.2.3.4'* ]]
  run src words
  [[ "$output" == *'cap-done'$'\t'* ]]
}

@test "other panes: alt-. moves to the window's next pane, remembered for the session; the header follows" {
  local other
  other="$(tmux split-window -d -t cap -P -F '#{pane_id}' 'bash --noprofile --norc')"
  fill "echo only-in-other" "$other"
  load_libs log session
  fzx::session_create capture "$CAP"
  run "$FZX" _cb transform pane next --
  [[ "$output" == 'transform-header('*'_cb transform header --)+'*'reload('* ]]
  [ "$(cat "$FZX_SESSION_DIR/state/capture_pane")" = "$other" ]
  run src lines
  [[ "$output" == *only-in-other* ]]
  run "$FZX" _cb transform header --
  [[ "$output" == "pane 2/2  $other  bash  "*" lines, "*" on screen  ·  alt-. alt-, other panes" ]]
  # and back, wrapping
  run "$FZX" _cb transform pane next --
  [ "$(cat "$FZX_SESSION_DIR/state/capture_pane")" = "$PANE" ]
}

@test "paste: literal, bracketed, into the origin pane, no Enter; the private buffer is gone" {
  run "$CAP/actions.sh" paste --pane "$PANE" -- 'one $(touch SHOULD_NOT_EXIST)' 'two'
  [ "$status" -eq 0 ]
  sleep 0.2
  [[ "$(tmux capture-pane -p -t "$PANE")" == *'one $(touch SHOULD_NOT_EXIST)'* ]]
  [ ! -e SHOULD_NOT_EXIST ]
  [ -z "$(tmux list-buffers -F '#{buffer_name}' | grep fzx-capture)" ]
}

@test "preview: where the value is and the lines around it, the hit's line marked" {
  fill "for i in \$(seq 1 30); do echo row-\$i; done"
  local y
  y="$(src lines | grep '^row-5'$'\t' | cut -f3)"
  run "$CAP/preview.sh" --pane "$PANE" -- row-5 "$y"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "$PANE in bash, 18 lines above the screen" ]]
  [[ "$output" == *$'\n'"▶ row-5"$'\n'* && "$output" == *"  row-4"* ]]
}

@test "under fzx: header, pane keys, paste and copy bound; the tmux module no longer captures" {
  stub_fzf
  run "$FZX" -m capture:urls --pane "$PANE"
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=pane 1/1  $PANE  bash  "*"10 on screen "* ]]
  [[ "$(fzf_bind alt-.)" == *'_cb transform pane next --pane '* ]]
  [[ "$(fzf_bind alt-p)" == *'_cb action paste --pane '* ]]
  [[ "$(fzf_bind ctrl-y)" == *'builtin copy {+1}'* || "$(fzf_bind ctrl-y)" == *'copy'*'{+1}'* ]]
  run "$FZX" -m tmux:urls
  [ "$status" -ne 0 ] || [[ "$(cat "$BATS_TEST_TMPDIR/fzf.mode" 2> /dev/null)" != urls ]]
}


@test "snapshot: under fzx the origin pane is read as it was before fzf started; other panes live" {
  fill "echo before-fzf"
  load_libs log session
  fzx::session_create capture "$CAP"
  run bash -c "source '$FZX_REPO/lib/core.sh'; fzx::require log config session; source '$CAP/source.sh'; capture::args; capture::snapshot"
  [ -f "$FZX_SESSION_DIR/state/capture_snapshot" ]
  # the pane changes afterwards (fzf drawing over it): the list still shows what was there
  fill "echo after-fzf"
  run src lines
  [[ "$output" == *before-fzf* && "$output" != *after-fzf* ]]
  # the preview reads the snapshot too
  local y
  y="$(printf '%s\n' "$output" | grep '^before-fzf'$'\t' | cut -f3)"
  run "$CAP/preview.sh" -- before-fzf "$y"
  [[ "$output" == *"▶ before-fzf"* ]]
}
