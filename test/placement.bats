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
# 200x50 ($STUB_TMUX_SIZE "W H" for another); list-commands fails with $STUB_TMUX_OLD (a tmux without new-pane). Calls go to tmux.calls.
stub_tmux() {
  cat > "$BATS_TEST_TMPDIR/bin/tmux" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/tmux.calls"
case "$1" in
  list-commands) [[ -z "${STUB_TMUX_OLD:-}" ]] || exit 1 ;;
  display-message) echo "${STUB_TMUX_SIZE:-200 50}" ;;
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

@test "popup-toggle: a popup and inline only; from a split the popup; the first popup entry; nowhere: bell" {
  echo 'FZX_PLACEMENTS=(inline split:down,40% popup:center,70% float)' > "$FZX_CONFIG_DIR/config.sh"
  kept
  # inline -> the popup entry, through become()
  FZX_SESSION="$SID" run "$FZX" _cb nav placement popup-toggle
  [ "$output" = "become:$FZX --resume $SID" ]
  [ "$(< "$DIR/state/placement")" = popup:center,70% ]
  # and back to inline, never through split or float
  FZX_SESSION="$SID" run "$FZX" _cb nav placement popup-toggle
  [ "$output" = "become:$FZX --resume $SID" ]
  [ ! -f "$DIR/state/placement" ]
  # out of a split pane into the popup: the owner relaunches
  echo split:down,40% > "$DIR/state/placement"
  FZX_SESSION="$SID" run "$FZX" _cb nav placement popup-toggle
  [ "$output" = abort ]
  [ "$(< "$DIR/state/placement")" = popup:center,70% ]
  [ -f "$DIR/state/relaunch" ]
  rm "$DIR/state/relaunch" "$DIR/state/placement"
  # no popup entry: a plain popup; outside tmux and Zellij: nowhere to go
  echo 'FZX_PLACEMENTS=(inline split:down,40%)' > "$FZX_CONFIG_DIR/config.sh"
  FZX_SESSION="$SID" run "$FZX" _cb nav placement popup-toggle
  [ "$(< "$DIR/state/placement")" = popup ]
  rm "$DIR/state/placement"
  TMUX="" FZX_SESSION="$SID" run "$FZX" _cb nav placement popup-toggle
  [ "$output" = bell ]
}

@test "popup-toggle: alt-^ binds it under fzx, an empty FZX_KEYS entry leaves it unbound" {
  run "$FZX" -m counter
  [ "$(fzf_bind 'alt-^')" = "alt-^:transform:$FZX _cb nav placement popup-toggle" ]
  echo 'FZX_KEYS[popup_toggle]=""' > "$FZX_CONFIG_DIR/config.sh"
  run "$FZX" -m counter
  ! fzf_bind 'alt-^'
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
  # FZX_POPUP_LAYOUTS' 140 entry, center,90%,85%, of a 200x50 window
  grep -q -- "^new-pane -P -F #{pane_id} -c $PWD -x 182 -y 44 -X 9 -Y 3 " "$BATS_TEST_TMPDIR/tmux.calls"
  grep -q 'fzf exec module=counter' "$LOG"
  [ -z "$(session_dirs)" ]
  rm "$BATS_TEST_TMPDIR/tmux.calls"
  run "$FZX" -m counter --float=bottom,30%
  grep -q -- "^new-pane .* -x 200 -y 17 -X 0 -Y 33 " "$BATS_TEST_TMPDIR/tmux.calls"
  run "$FZX" -m counter --float=sideways
  [ "$status" -eq 2 ]
}

@test "popup layouts: the entry for the tmux window's width, not the pane's; per module; the fallbacks" {
  local w l
  for w in "100 40:center,100%" "140 40:center,90%,85%" "219 60:center,90%,85%" "300 80:center,80%"; do
    STUB_TMUX_SIZE="${w%%:*}" COLUMNS=60 run "$FZX" -m counter --popup
    read_fzf_args
    [[ " ${FZF_ARGS[*]} " == *" --popup=${w#*:} "* ]]
  done
  # a module's config.sh (here the user's layer for it) sets its own
  mkdir -p "$FZX_CONFIG_DIR/modules/counter"
  echo 'FZX_POPUP_LAYOUTS=("0:bottom,60%" "180:right,40%")' > "$FZX_CONFIG_DIR/modules/counter/config.sh"
  run "$FZX" -m counter --popup
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --popup=right,40% "* ]]
  # explicit options win
  run "$FZX" -m counter --popup=top,30%
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --popup=top,30% "* ]]
  # FZX_POPUP_OPTS / FZX_FLOAT_OPTS, when set, win over the layouts
  echo 'FZX_POPUP_OPTS=left,50%; FZX_FLOAT_OPTS=top,20%' > "$FZX_CONFIG_DIR/modules/counter/config.sh"
  run "$FZX" -m counter --popup
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --popup=left,50% "* ]]
  rm -f "$BATS_TEST_TMPDIR/tmux.calls"
  run "$FZX" -m counter --float
  grep -q -- "^new-pane .* -x 200 -y 12 -X 0 -Y 0 " "$BATS_TEST_TMPDIR/tmux.calls"
  # no layouts, or none fits: center,80%
  for l in '()' '("300:center,50%")'; do
    echo "FZX_POPUP_LAYOUTS=$l" > "$FZX_CONFIG_DIR/modules/counter/config.sh"
    run "$FZX" -m counter --popup
    read_fzf_args
    [[ " ${FZF_ARGS[*]} " == *" --popup=center,80% "* ]]
  done
}

@test "resize hook: a popup launch in tmux sets it once per tree, records the geometry; the owner removes it" {
  rm -f "$BATS_TEST_TMPDIR/tmux.calls"
  TMUX_PANE=%3 run "$FZX" -m counter --popup --dry-run
  ! grep -q set-hook "$BATS_TEST_TMPDIR/tmux.calls"
  # the stub fzf goes to a child and back, both popup launches: one hook
  STUB_FZF_RUN='[[ -f $BATS_TEST_TMPDIR/again ]] || { touch $BATS_TEST_TMPDIR/again; cp $FZX_SESSION_DIR/state/popup_geometry $BATS_TEST_TMPDIR/geo; cp $FZX_SESSION_DIR/state/resize_hook $BATS_TEST_TMPDIR/hook; }' \
    TMUX_PANE=%3 run "$FZX" -m counter --popup
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/geo")" = "center,90%,85% 200x50" ]
  [[ "$(< "$BATS_TEST_TMPDIR/hook")" =~ ^[0-9]+\ %3$ ]]
  local idx
  idx="$(cut -d' ' -f1 "$BATS_TEST_TMPDIR/hook")"
  [ "$(grep -c '^set-hook -w' "$BATS_TEST_TMPDIR/tmux.calls")" -eq 1 ]
  grep -q "^set-hook -w -t %3 window-resized\[$idx\] run-shell -b '.*/fzx _resized .*/sessions/[^ ]* $idx %3'$" "$BATS_TEST_TMPDIR/tmux.calls"
  grep -q "^set-hook -uw -t %3 window-resized\[$idx\]$" "$BATS_TEST_TMPDIR/tmux.calls"
  # inline: no hook
  rm -f "$BATS_TEST_TMPDIR/tmux.calls"
  TMUX_PANE=%3 run "$FZX" -m counter
  ! grep -q set-hook "$BATS_TEST_TMPDIR/tmux.calls"
}

@test "relayout: a float is resized and moved in place for the window's new size, nothing otherwise" {
  # the float's launch records its pane and geometry on the root and sets the resize hook
  TMUX_PANE=%3 kept --float
  [ -z "$(cat "$DIR/state/float_pane" 2> /dev/null)" ]
  grep -q -- "^set-hook -w -t %3 window-resized" "$BATS_TEST_TMPDIR/tmux.calls"
  # while it runs (the owner removes both when the pane ends): as the pane would have them
  printf %s %9 > "$DIR/state/float_pane"
  printf %s float > "$DIR/state/placement"
  printf %s "center,90%,85% 200x50" > "$DIR/state/float_geometry"
  rm "$BATS_TEST_TMPDIR/tmux.calls"
  FZX_SESSION="$SID" run "$FZX" _cb nav relayout
  [ -z "$output" ]
  ! grep -q "resize-pane" "$BATS_TEST_TMPDIR/tmux.calls"
  # a smaller window: the 0 entry of FZX_POPUP_LAYOUTS (center,100%), the pane resized and moved, no restart
  STUB_TMUX_SIZE="100 30" FZX_SESSION="$SID" run "$FZX" _cb nav relayout
  [ -z "$output" ]
  grep -qx -- "resize-pane -t %9 -x 100 -y 30" "$BATS_TEST_TMPDIR/tmux.calls"
  grep -qx -- "move-pane -t %9 -X 0 -Y 0" "$BATS_TEST_TMPDIR/tmux.calls"
  [ "$(< "$DIR/state/float_geometry")" = "center,100% 100x30" ]
  # an explicit spec: its own geometry
  printf %s float:bottom,30% > "$DIR/state/placement"
  STUB_TMUX_SIZE="100 30" FZX_SESSION="$SID" run "$FZX" _cb nav relayout
  grep -qx -- "resize-pane -t %9 -x 100 -y 11" "$BATS_TEST_TMPDIR/tmux.calls"
  # no float pane recorded: nothing
  rm "$DIR/state/float_pane"
  rm "$BATS_TEST_TMPDIR/tmux.calls"
  STUB_TMUX_SIZE="120 30" FZX_SESSION="$SID" run "$FZX" _cb nav relayout
  [ -z "$output" ]
  ! grep -q "resize-pane" "$BATS_TEST_TMPDIR/tmux.calls"
}

@test "relayout: a popup restarts when the window's size or the spec changed, nothing otherwise" {
  TMUX_PANE=%3 kept --popup
  [ "$(< "$DIR/state/popup_geometry")" = "center,90%,85% 200x50" ]
  FZX_SESSION="$SID" run "$FZX" _cb nav relayout
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  STUB_TMUX_SIZE="201 50" FZX_SESSION="$SID" run "$FZX" _cb nav relayout
  [ "$output" = "become:$FZX --resume $SID" ]
  grep -q 'nav relayout: popup center,90%,85% 200x50 -> center,90%,85% 201x50' "$LOG"
  # an explicit spec follows the window too; inline and splits are left alone
  echo popup:top,40% > "$DIR/state/placement"
  FZX_SESSION="$SID" run "$FZX" _cb nav relayout
  [ "$output" = "become:$FZX --resume $SID" ]
  rm "$DIR/state/placement"
  STUB_TMUX_SIZE="90 20" FZX_SESSION="$SID" run "$FZX" _cb nav relayout
  [ -z "$output" ]
}

@test "resized: tells the fzf on screen to relayout once the size settles; a gone tree removes its hook" {
  cat > "$BATS_TEST_TMPDIR/bin/curl" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/curl.calls"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  kept
  printf '%s' "$SID" > "$DIR/state/current"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$DIR/fzf.sock"
  FZX_RESIZE_SETTLE_MS=0 run "$FZX" _resized "$DIR" 1234 %3
  [ "$status" -eq 0 ]
  grep -q -- "--unix-socket $DIR/fzf.sock -X POST http://localhost --data-binary transform:$FZX _cb nav relayout" "$BATS_TEST_TMPDIR/curl.calls"
  # still changing: nothing is sent
  rm "$BATS_TEST_TMPDIR/curl.calls"
  cat > "$BATS_TEST_TMPDIR/size" << 'EOF2'
#!/usr/bin/env bash
n=$(cat "$BATS_TEST_TMPDIR/n" 2> /dev/null || echo 0); echo $((n + 1)) > "$BATS_TEST_TMPDIR/n"; echo "$((100 + n)) 50"
EOF2
  sed -i 's|display-message) echo .*|display-message) [ -n "${STUB_TMUX_GROW:-}" ] \&\& exec bash "$BATS_TEST_TMPDIR/size"; echo "${STUB_TMUX_SIZE:-200 50}" ;;|' "$BATS_TEST_TMPDIR/bin/tmux"
  STUB_TMUX_GROW=1 FZX_RESIZE_SETTLE_MS=0 run "$FZX" _resized "$DIR" 1234 %3
  [ ! -f "$BATS_TEST_TMPDIR/curl.calls" ]
  # the tree is gone: the hook goes
  FZX_RESIZE_SETTLE_MS=0 run "$FZX" _resized "$BATS_TEST_TMPDIR/nonexistent" 1234 %3
  grep -q '^set-hook -uw -t %3 window-resized\[1234\]$' "$BATS_TEST_TMPDIR/tmux.calls"
}

@test "window size: tmux's window, else COLUMNS/LINES, else tput; fails when unknown" {
  load_libs log run
  local w h
  fzx::window_size w h && [ "$w $h" = "200 50" ]
  TMUX="" COLUMNS=91 LINES=33 fzx::window_size w h && [ "$w $h" = "91 33" ]
  STUB_TMUX_SIZE="x y" COLUMNS=91 LINES=33 fzx::window_size w h && [ "$w $h" = "91 33" ]
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/tput"
  chmod +x "$BATS_TEST_TMPDIR/bin/tput"
  ! TMUX="" COLUMNS="" LINES="" fzx::window_size w h
}

@test "float geometry: positions and sizes like fzf's --popup, the border added outside" {
  load_libs log run
  local g
  fzx::float_geometry center,80% 200 50 g && [ "$g" = "-x 162 -y 42 -X 19 -Y 4" ]
  fzx::float_geometry "" 200 50 g && [ "$g" = "-x 102 -y 27 -X 49 -Y 11" ]
  fzx::float_geometry right,40% 200 50 g && [ "$g" = "-x 82 -y 50 -X 118 -Y 0" ]
  fzx::float_geometry left,30 200 50 g && [ "$g" = "-x 32 -y 50 -X 0 -Y 0" ]
  fzx::float_geometry top,80%,40% 200 50 g && [ "$g" = "-x 162 -y 22 -X 19 -Y 0" ]
  fzx::float_geometry center,300,90%,border-native 200 50 g && [ "$g" = "-x 200 -y 47 -X 0 -Y 1" ]
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
