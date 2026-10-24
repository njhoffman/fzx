#!/usr/bin/env bats
# placements: the cycle through FZX_PLACEMENTS, --split/--float, the owner's tmux panes, the relaunch loop and
# FZF_TMUX

load test_helper

setup() {
  setup_fzx
  stub_fzf
  stub_tmux
  export TMUX=fake
  mkdir -p "$FZX_CONFIG_DIR"
}

# stub tmux: split-window and new-pane run the pane's command in the background and print a pane id;
# list-panes lists that pane while the command runs (never, with $BATS_TEST_TMPDIR/closed); the window is
# 200x50; list-commands fails with $STUB_TMUX_OLD (a tmux without new-pane). Calls go to tmux.calls.
stub_tmux() {
  cat > "$BATS_TEST_TMPDIR/bin/tmux" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/tmux.calls"
case "$1" in
  list-commands) [[ -z "${STUB_TMUX_OLD:-}" ]] || exit 1 ;;
  display-message) echo "200 50" ;;
  split-window | new-pane)
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

@test "the cycle: inline -> split -> popup -> float; into and out of a tmux pane the owner relaunches" {
  kept
  local p
  for p in split:down,40% popup float; do
    FZX_SESSION="$SID" run "$FZX" _cb nav placement next
    [ "$output" = abort ]
    [ "$(< "$DIR/state/placement")" = "$p" ]
    [ -f "$DIR/state/relaunch" ]
    rm "$DIR/state/relaunch"
  done
  FZX_SESSION="$SID" run "$FZX" _cb nav placement next
  [ "$output" = abort ]
  [ ! -f "$DIR/state/placement" ]
  [ -f "$DIR/state/relaunch" ]
  # between inline and a popup, become() restarts in place
  echo 'FZX_PLACEMENTS=(inline popup)' > "$FZX_CONFIG_DIR/config.sh"
  rm "$DIR/state/relaunch"
  FZX_SESSION="$SID" run "$FZX" _cb nav placement next
  [ "$output" = "become:$FZX --resume $SID" ]
  [ ! -f "$DIR/state/relaunch" ]
}

@test "float: skipped by the cycle on a tmux without new-pane" {
  echo 'FZX_PLACEMENTS=(inline float)' > "$FZX_CONFIG_DIR/config.sh"
  kept
  STUB_TMUX_OLD=1 FZX_SESSION="$SID" run "$FZX" _cb nav placement next
  [ "$output" = bell ]
  STUB_TMUX_OLD=1 TMUX=fake run "$FZX" -m counter --float
  grep -q 'placement float is not available here' "$LOG"
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
  rm -rf "$FZX_RUNTIME_DIR/sessions"
  kept --float
  [ "$(< "$DIR/state/placement")" = float ]
  rm -rf "$FZX_RUNTIME_DIR/sessions"
  kept --float=right,40%
  [ "$(< "$DIR/state/placement")" = float:right,40% ]
}

@test "float: the owner runs the session in a floating pane, placed in cells from the --popup syntax" {
  STUB_FZF_OUT=picked run "$FZX" -m counter --float
  [ "$status" -eq 0 ]
  [ "$output" = picked ]
  # FZX_FLOAT_OPTS center,80% of a 200x50 window
  grep -q -- "^new-pane -P -F #{pane_id} -c $PWD -x 160 -y 40 -X 20 -Y 5 " "$BATS_TEST_TMPDIR/tmux.calls"
  grep -q 'fzf exec module=counter' "$LOG"
  [ -z "$(session_dirs)" ]
  rm "$BATS_TEST_TMPDIR/tmux.calls"
  run "$FZX" -m counter --float=bottom,30%
  grep -q -- "^new-pane .* -x 200 -y 15 -X 0 -Y 35 " "$BATS_TEST_TMPDIR/tmux.calls"
  run "$FZX" -m counter --float=sideways
  [ "$status" -eq 2 ]
}

@test "float geometry: positions and sizes like fzf's --popup" {
  load_libs log run
  local g
  fzx::float_geometry center,80% 200 50 g && [ "$g" = "-x 160 -y 40 -X 20 -Y 5" ]
  fzx::float_geometry "" 200 50 g && [ "$g" = "-x 100 -y 25 -X 50 -Y 12" ]
  fzx::float_geometry right,40% 200 50 g && [ "$g" = "-x 80 -y 50 -X 120 -Y 0" ]
  fzx::float_geometry left,30 200 50 g && [ "$g" = "-x 30 -y 50 -X 0 -Y 0" ]
  fzx::float_geometry top,80%,40% 200 50 g && [ "$g" = "-x 160 -y 20 -X 20 -Y 0" ]
  fzx::float_geometry center,300,90%,border-native 200 50 g && [ "$g" = "-x 200 -y 45 -X 0 -Y 2" ]
  ! fzx::float_geometry middle,50% 200 50 g
}

@test "FZF_TMUX: FZF_TMUX_OPTS in fzf-tmux syntax picks the starting placement" {
  load_libs log run
  local p
  _fzf_tmux() { p=""; FZF_TMUX=1 FZF_TMUX_OPTS="$1" fzx::placement_from_fzf_tmux p; }
  _fzf_tmux "" && [ "$p" = popup ]
  _fzf_tmux "-p" && [ "$p" = popup ]
  _fzf_tmux "-p80%,60%" && [ "$p" = popup:center,80%,60% ]
  _fzf_tmux "-p 70%" && [ "$p" = popup:center,70% ]
  _fzf_tmux "-p -w 90% -h 50%" && [ "$p" = popup:center,90%,50% ]
  _fzf_tmux "-d40%" && [ "$p" = split:down,40% ]
  _fzf_tmux "-d 30" && [ "$p" = split:down,30 ]
  _fzf_tmux "-u" && [ "$p" = split:up,50% ]
  _fzf_tmux "-r 40%" && [ "$p" = split:right,40% ]
  _fzf_tmux "-l25%" && [ "$p" = split:left,25% ]
  _fzf_tmux "--bogus" && [ "$p" = popup ]
  # off, or outside tmux
  ! FZF_TMUX=0 fzx::placement_from_fzf_tmux p
  ! FZF_TMUX="" fzx::placement_from_fzf_tmux p
  ! TMUX="" FZF_TMUX=1 fzx::placement_from_fzf_tmux p
}

@test "FZF_TMUX: a new run starts there; a placement flag wins; resumes are untouched" {
  FZF_TMUX=1 FZF_TMUX_OPTS="-d 30%" kept
  [ "$(< "$DIR/state/placement")" = split:down,30% ]
  rm -rf "$FZX_RUNTIME_DIR/sessions"
  FZF_TMUX=1 FZF_TMUX_OPTS="-d 30%" kept --float
  [ "$(< "$DIR/state/placement")" = float ]
  rm -rf "$FZX_RUNTIME_DIR/sessions"
  kept
  FZF_TMUX=1 run "$FZX" --resume "$SID"
  [ ! -f "$DIR/state/placement" ]
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
