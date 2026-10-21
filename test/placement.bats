#!/usr/bin/env bats
# placements: the cycle through FZX_PLACEMENTS, --split, the owner's split pane and its relaunch loop

load test_helper

setup() {
  setup_fzx
  stub_fzf
  stub_tmux
  export TMUX=fake
  mkdir -p "$FZX_CONFIG_DIR"
}

# stub tmux: split-window runs the pane's command in the background and prints a pane id; list-panes
# lists that pane while the command runs (never, with $BATS_TEST_TMPDIR/closed). Calls go to tmux.calls.
stub_tmux() {
  cat > "$BATS_TEST_TMPDIR/bin/tmux" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/tmux.calls"
case "$1" in
  split-window)
    sh -c "${!#}" > /dev/null 2>&1 < /dev/null &
    echo "$!" > "$BATS_TEST_TMPDIR/pane.pid"
    echo %9
    ;;
  list-panes)
    [[ -f "$BATS_TEST_TMPDIR/closed" ]] && exit 0
    kill -0 "$(< "$BATS_TEST_TMPDIR/pane.pid")" 2> /dev/null && echo %9
    ;;
esac
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
}

kept() {
  "$FZX" --keep -m counter "$@"
  SID="$(basename "$(session_dirs)")"
  DIR="$FZX_RUNTIME_DIR/sessions/$SID"
}

@test "the cycle: inline -> popup restarts through become; into and out of a split the owner relaunches" {
  kept
  FZX_SESSION="$SID" run "$FZX" _cb nav placement next
  [ "$output" = "become:$FZX --resume $SID" ]
  [ "$(< "$DIR/state/placement")" = popup ]
  [ ! -f "$DIR/state/relaunch" ]
  FZX_SESSION="$SID" run "$FZX" _cb nav placement next
  [ "$output" = abort ]
  [ "$(< "$DIR/state/placement")" = split:down,40% ]
  [ -f "$DIR/state/relaunch" ]
  rm "$DIR/state/relaunch"
  FZX_SESSION="$SID" run "$FZX" _cb nav placement next
  [ "$output" = abort ]
  [ ! -f "$DIR/state/placement" ]
  [ -f "$DIR/state/relaunch" ]
}

@test "the cycle skips what cannot run here; prev and a named placement; no move rings the bell" {
  echo 'FZX_PLACEMENTS=(inline popup split:right)' > "$FZX_CONFIG_DIR/config.sh"
  kept
  # Zellij has popups but no tmux splits
  TMUX="" ZELLIJ=1 FZX_SESSION="$SID" run "$FZX" _cb nav placement prev
  [ "$(< "$DIR/state/placement")" = popup ]
  TMUX="" ZELLIJ=1 FZX_SESSION="$SID" run "$FZX" _cb nav placement next
  [ ! -f "$DIR/state/placement" ]
  FZX_SESSION="$SID" run "$FZX" _cb nav placement split:left,30%
  [ "$(< "$DIR/state/placement")" = split:left,30% ]
  FZX_SESSION="$SID" run "$FZX" _cb nav placement split:left,30%
  [ "$output" = bell ]
  TMUX="" FZX_SESSION="$SID" run "$FZX" _cb nav placement bogus
  [ "$output" = bell ]
}

@test "--split and --popup set the starting placement" {
  kept --split
  [ "$(< "$DIR/state/placement")" = split:down,40% ]
  rm -rf "$FZX_RUNTIME_DIR/sessions"
  kept --split=left,30
  [ "$(< "$DIR/state/placement")" = split:left,30 ]
  rm -rf "$FZX_RUNTIME_DIR/sessions"
  kept --popup=top,40%
  [ "$(< "$DIR/state/placement")" = popup:top,40% ]
}

@test "split: the owner runs the session in a tmux pane with its environment and prints its result" {
  STUB_FZF_OUT=picked STUB_FZF_RC=0 MY_SETTING=kept run "$FZX" -m counter --split=left,30%
  [ "$status" -eq 0 ]
  [ "$output" = picked ]
  grep -q -- "^split-window -P -F #{pane_id} -c $PWD -h -b -l 30% " "$BATS_TEST_TMPDIR/tmux.calls"
  # the fzf in the pane is a resume of the same session, with the caller's environment
  [ -n "$(< "$BATS_TEST_TMPDIR/fzf.session")" ]
  grep -q 'fzf exec module=counter' "$LOG"
  # the pane's files are gone afterwards
  [ -z "$(session_dirs)" ]
}

@test "split: the pane's exit status is the owner's; a pane closed by hand counts as an abort" {
  STUB_FZF_RC=1 run "$FZX" -m counter --split
  [ "$status" -eq 1 ]
  touch "$BATS_TEST_TMPDIR/closed"
  STUB_FZF_RUN='sleep 1' run "$FZX" -m counter --split
  [ "$status" -eq 130 ]
}

@test "split: a bad direction fails; outside tmux the split runs inline" {
  run "$FZX" -m counter --split=sideways
  [ "$status" -eq 2 ]
  TMUX="" STUB_FZF_OUT=inline run "$FZX" -m counter --split
  [ "$output" = inline ]
  [ ! -f "$BATS_TEST_TMPDIR/tmux.calls" ]
  grep -q 'placement split:down,40% is not available here' "$LOG"
}

@test "relaunch: a placement change from inline into a split relaunches the current screen there" {
  # the first fzf (inline) asks for the split and aborts, as the placement key would; the second runs in
  # the pane and picks
  export FZX
  STUB_FZF_RUN='if [[ ! -f "$BATS_TEST_TMPDIR/once" ]]; then touch "$BATS_TEST_TMPDIR/once"
      "$FZX" _cb nav placement split:down,40% > /dev/null; exit 130; fi; echo from-pane' run "$FZX" -m counter
  [ "$status" -eq 0 ]
  [ "$output" = from-pane ]
  grep -q '^split-window ' "$BATS_TEST_TMPDIR/tmux.calls"
  grep -q 'relaunch for a placement change' "$LOG"
}
