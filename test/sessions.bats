#!/usr/bin/env bats
# the sessions module over session trees made in the test: kept ones (--keep, owner gone), a live one (its
# owner the test's own shell) and the list's own tree

load test_helper

SES="$(readlink -f "$BATS_TEST_DIRNAME/../modules/sessions")"

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none
  stub_fzf
  load_libs log session
  # a kept tree: counter, two then a child; its owner (fzx) has exited
  STUB_FZF_RUN='printf two > "$FZX_SESSION_DIR/state/mode"; printf needle > "$FZX_SESSION_DIR/state/query"; printf alpha > "$FZX_SESSION_DIR/state/toggles"' \
    "$FZX" --keep -m counter -- arg1
  KEPT="$(basename "$(session_dirs)")"
  (fzx::session_attach "$KEPT" && fzx::session_create_child counter "$FZX_REPO/test/fixtures/modules/counter" && fzx::state_set mode one && printf '%s' "$FZX_SESSION" > "$BATS_TEST_TMPDIR/child")
  CHILD="$(< "$BATS_TEST_TMPDIR/child")"
  # a live tree: the owner is this shell
  fzx::session_create counter "$FZX_REPO/test/fixtures/modules/counter"
  LIVE="$FZX_SESSION"
  fzx::state_set mode three
  # make the trees' ages differ: kept the oldest
  printf 1000 > "$FZX_RUNTIME_DIR/sessions/$KEPT/meta/started_ms"
  printf 1500 > "$FZX_RUNTIME_DIR/sessions/$CHILD/meta/started_ms"
  # the list's own tree
  fzx::session_create sessions "$SES"
  OWN="$FZX_SESSION"
}

@test "source: every other tree, newest first, its screens under it; kept and live; the own tree left out" {
  run "$SES/source.sh"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == "$LIVE"$'\t'"$LIVE"$'\tlive  counter:three '* ]]
  [[ "${lines[1]}" == "$KEPT"$'\t'"$KEPT"$'\tkept  counter:two '*"  arg1  q: needle" ]]
  [[ "${lines[2]}" == "$CHILD"$'\t'"$CHILD"$'\t    └ counter:one '* ]]
  [[ "$output" != *"$OWN"* ]]
}

@test "preview: the path, what enter does, module, mode, args, query, toggles, owner; gone" {
  run "$SES/preview.sh" "$CHILD"
  [ "${lines[0]}" = "counter:two > counter:one" ]
  [[ "${lines[1]}" == "kept, its owner gone: enter resumes it here" ]]
  run "$SES/preview.sh" "$KEPT"
  [[ "$output" == *"args       arg1"* && "$output" == *"query      needle"* && "$output" == *"toggles    alpha"* ]]
  [[ "$output" == *"owner      "*"(kept)"* && "$output" == *"placement  inline"* ]]
  run "$SES/preview.sh" "$LIVE"
  [[ "${lines[1]}" == "live in another terminal: enter opens a copy" ]]
  run "$SES/preview.sh" nosuch
  [ "$output" = "session nosuch is gone" ]
}

@test "enter: a kept session resumes here; a live one opens as a copy under this list, its state copied" {
  run "$FZX" _cb transform enter "$CHILD"
  [ "$output" = "become:$FZX --resume $CHILD" ]
  printf 'foo' > "$FZX_RUNTIME_DIR/sessions/$LIVE/state/query"
  run "$FZX" _cb transform enter "$LIVE"
  [[ "$output" == "become:$FZX --resume "*" -m :three" ]]
  local copy="${output##*--resume }"
  copy="${copy%% *}"
  [ "$copy" != "$LIVE" ]
  [ "$(< "$FZX_RUNTIME_DIR/sessions/$copy/meta/parent")" = "$OWN" ]
  [ "$(< "$FZX_RUNTIME_DIR/sessions/$copy/state/query")" = foo ]
  run "$FZX" _cb transform enter nosuch
  [ "$output" = bell ]
}

@test "delete: kept trees whole (from any of their screens); live ones refused" {
  run "$SES/actions.sh" delete "$CHILD" "$LIVE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is live in another terminal"* ]]
  [ ! -d "$FZX_RUNTIME_DIR/sessions/$KEPT" ]
  [ ! -d "$FZX_RUNTIME_DIR/sessions/$CHILD" ]
  [ -d "$FZX_RUNTIME_DIR/sessions/$LIVE" ]
}

@test "under fzx: enter is the transform, alt-x delete, no sorting; menu summary" {
  run "$FZX" -m sessions
  [ "$status" -eq 0 ]
  [ "$(fzf_bind enter)" = "enter:transform:$FZX _cb transform enter {1}" ]
  [[ "$(fzf_bind alt-x)" == "alt-x:execute($FZX _cb action delete {+1})+"*"reload("* ]]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --no-sort "* ]]
  source "$SES/manifest.sh"
  FZX_SESSION="$OWN" run sessions::summary sessions
  [ "$output" = "1 kept, 1 live" ]
}

@test "enter on a kept session: this list's owner adopts it (owner pid and start copied, state/adopt on the list's root)" {
  printf '%s' "$(< "$FZX_RUNTIME_DIR/sessions/$OWN/meta/owner_pid")" > "$BATS_TEST_TMPDIR/own_pid"
  run "$FZX" _cb transform enter "$CHILD"
  [ "$output" = "become:$FZX --resume $CHILD" ]
  [ "$(< "$FZX_RUNTIME_DIR/sessions/$OWN/state/adopt")" = "$KEPT" ]
  [ "$(< "$FZX_RUNTIME_DIR/sessions/$KEPT/meta/owner_pid")" = "$(< "$BATS_TEST_TMPDIR/own_pid")" ]
  [ "$(< "$FZX_RUNTIME_DIR/sessions/$KEPT/meta/owner_start")" = "$(< "$FZX_RUNTIME_DIR/sessions/$OWN/meta/owner_start")" ]
  # now owned by a live process (this test's shell): another list sees it live and copies it
  run "$SES/preview.sh" "$KEPT"
  [[ "${lines[1]}" == "live in another terminal: enter opens a copy" ]]
}

@test "owner loop: a relaunch the adopted tree asks for launches its current screen; its own relaunch first" {
  load_libs log session run
  _FZX_ROOT_SESSION="$OWN"
  ! fzx::_relaunch_root rr
  printf '%s' "$KEPT" > "$FZX_RUNTIME_DIR/sessions/$OWN/state/adopt"
  ! fzx::_relaunch_root rr
  touch "$FZX_RUNTIME_DIR/sessions/$KEPT/state/relaunch"
  fzx::_relaunch_root rr
  [ "$rr" = "$KEPT" ]
  touch "$FZX_RUNTIME_DIR/sessions/$OWN/state/relaunch"
  fzx::_relaunch_root rr
  [ "$rr" = "$OWN" ]
}

@test "owner loop end to end: the list's fzf adopts a kept tree and asks it to relaunch; the owner launches that tree's screen" {
  # the first fzf (the list) adopts KEPT and leaves a relaunch on it, as a placement change there would
  printf '%s' "$CHILD" > "$FZX_RUNTIME_DIR/sessions/$KEPT/state/current"
  export KEPT
  STUB_FZF_RUN='printf "%s\n" "$FZX_SESSION" >> "$BATS_TEST_TMPDIR/launches"
    if [[ ! -f "$BATS_TEST_TMPDIR/adopted" ]]; then touch "$BATS_TEST_TMPDIR/adopted"
      root=$(cat "$FZX_SESSION_DIR/meta/root" 2>/dev/null || echo "$FZX_SESSION")
      printf %s "$KEPT" > "$FZX_RUNTIME_DIR/sessions/$root/state/adopt"
      touch "$FZX_RUNTIME_DIR/sessions/$KEPT/state/relaunch"; fi' \
    run "$FZX" -m sessions
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/launches")" -eq 2 ]
  [ "$(sed -n 2p "$BATS_TEST_TMPDIR/launches")" = "$CHILD" ]
  [ ! -f "$FZX_RUNTIME_DIR/sessions/$KEPT/state/relaunch" ]
  # the list's own tree is cleaned up, the adopted one kept
  [ -d "$FZX_RUNTIME_DIR/sessions/$KEPT/meta" ]
}
