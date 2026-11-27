#!/usr/bin/env bats
# lib/output.sh: --to (a tmux pane, found once), --submit and --loop (the list stays open)

load test_helper

bats_require_minimum_version 1.5.0

COUNTER_DIR="$(readlink -f "$BATS_TEST_DIRNAME/fixtures/modules/counter")"

setup() {
  setup_fzx
  stub_fzf
  CALLS="$BATS_TEST_TMPDIR/tmux.calls"
  # stub tmux: panes from $BATS_TEST_TMPDIR/panes ("ID LEFT TOP RIGHT BOTTOM FLOATING"); display-message
  # knows those ids; every call goes to tmux.calls, a buffer's text after its load-buffer line
  cat > "$BATS_TEST_TMPDIR/bin/tmux" << 'STUB'
#!/usr/bin/env bash
panes="$BATS_TEST_TMPDIR/panes"
{ printf '%s|' "$@"; echo; } >> "$BATS_TEST_TMPDIR/tmux.calls"
case "$1" in
  list-panes) cat "$panes" ;;
  display-message)
    t="${4:-}"
    awk -v t="$t" '$1 == t { print $1 }' "$panes"
    ;;
  load-buffer) { cat; printf '<END>\n'; } >> "$BATS_TEST_TMPDIR/tmux.calls" ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  # %1 is the left half; %2 above %3 on the right; %4 floats over them
  printf '%s\n' '%1 0 0 39 23 0' '%2 41 0 79 11 0' '%3 41 13 79 23 0' '%4 10 5 60 15 1' > "$BATS_TEST_TMPDIR/panes"
  export TMUX=/tmp/tmux-test,1,0 TMUX_PANE=%1
  unset FZX_OUTPUT_PANE FZX_OUTPUT_SUBMIT FZX_LOOP FZX_PRINT
}

libs() {
  load_libs log session opts output
}

@test "resolve: a direction is the neighbour that way; floating panes are left out" {
  libs
  local p
  fzx::output_resolve right "" p
  [ "$p" = %2 ]
  TMUX_PANE=%3 fzx::output_resolve left "" p
  [ "$p" = %1 ]
  TMUX_PANE=%3 fzx::output_resolve up "" p
  [ "$p" = %2 ]
  TMUX_PANE=%2 fzx::output_resolve down "" p
  [ "$p" = %3 ]
  run fzx::output_resolve left "" p
  [ "$status" -eq 2 ]
  [[ "$output" == *"no pane left of %1"* ]]
  TMUX_PANE=%3 run fzx::output_resolve down "" p
  [ "$status" -eq 2 ]
}

@test "resolve: the right half's two panes: the one sharing more rows wins" {
  libs
  local p
  # %2 shares rows 0-11 with %1, %3 rows 13-23: %2
  fzx::output_resolve right "" p
  [ "$p" = %2 ]
  printf '%s\n' '%1 0 0 39 23 0' '%2 41 0 79 5 0' '%3 41 7 79 23 0' > "$BATS_TEST_TMPDIR/panes"
  fzx::output_resolve right "" p
  [ "$p" = %3 ]
}

@test "resolve: a pane id or tmux target; an unknown one, the pane fzf is in inline, or no tmux fail" {
  libs
  local p=""
  fzx::output_resolve %3 "" p
  [ "$p" = %3 ]
  run fzx::output_resolve %9 "" p
  [ "$status" -eq 2 ]
  [[ "$output" == *"no such pane"* ]]
  run fzx::output_resolve %1 "" p
  [ "$status" -eq 2 ]
  [[ "$output" == *"the pane fzf runs in"* ]]
  # from a popup the pane it was opened from is where the text goes (todos --paste from /todo-pop)
  fzx::output_resolve %1 popup p
  [ "$p" = %1 ]
  TMUX="" run fzx::output_resolve right "" p
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs tmux"* ]]
}

@test "send: a bracketed paste through a buffer of its own; a delay hands it to the server" {
  libs
  fzx::output_send_pane %2 0 'one' 'two'
  run cat "$CALLS"
  [ "${lines[0]}" = "display-message|-p|-t|%2|#{pane_id}|" ]
  [[ "${lines[1]}" =~ ^load-buffer\|-b\|fzx-out-[0-9]+-[0-9]+\|-\|$ ]]
  [ "${lines[2]}" = one ]
  [ "${lines[3]}" = two ]
  # the text ends with a newline: the next thing typed starts a line of its own
  [ "${lines[4]}" = '<END>' ]
  [[ "${lines[5]}" =~ ^paste-buffer\|-p\|-d\|-b\|fzx-out-[0-9]+-[0-9]+\|-t\|%2\|$ ]]
  rm "$CALLS"
  fzx::output_send_pane %2 0.3 'x'
  run grep '^run-shell' "$CALLS"
  [[ "$output" =~ ^run-shell\|-b\|-d\|0.3\|tmux\ paste-buffer\ -p\ -d\ -b\ fzx-out-[0-9]+-[0-9]+\ -t\ %2\|$ ]]
}

@test "send: --submit presses Enter after the paste, with no newline at the text's end" {
  libs
  FZX_OUTPUT_SUBMIT=1 fzx::output_send_pane %2 0 'make test'
  run cat "$CALLS"
  [ "${lines[2]}" = 'make test<END>' ]
  [[ "${lines[3]}" == paste-buffer\|* ]]
  [ "${lines[4]}" = "send-keys|-t|%2|Enter|" ]
  rm "$CALLS"
  FZX_OUTPUT_SUBMIT=1 fzx::output_send_pane %2 0.3 'x'
  [[ "$(grep '^run-shell' "$CALLS")" == *" -t %2 && tmux send-keys -t %2 Enter|" ]]
}

@test "send: FZX_OUTPUT_NEWLINE=0 leaves the newline off without pressing Enter" {
  libs
  FZX_OUTPUT_NEWLINE=0 fzx::output_send_pane %2 0 'make test'
  run cat "$CALLS"
  [ "${lines[2]}" = 'make test<END>' ]
  ! grep -q send-keys "$CALLS"
}

@test "send: a pane that is gone, or not an id, fails; nothing selected sends nothing" {
  libs
  run fzx::output_send_pane %9 0 x
  [ "$status" -eq 1 ]
  [ "$output" = "pane %9 is gone" ]
  run fzx::output_send_pane left 0 x
  [ "$status" -eq 2 ]
  rm -f "$CALLS"
  fzx::output_send_pane %2 0
  [ ! -e "$CALLS" ]
}

@test "items: the accept template filled in per row: a field, fields with text between, the row, its index" {
  libs
  local out=() ph
  fzx::_output_items out '{3}' 0 4 -- 'a' 'b'
  [ "${#out[@]}" -eq 2 ] && [ "${out[0]}" = a ] && [ "${out[1]}" = b ]
  fzx::_output_items out '{1}:{2}' 0 4 -- f1 f2 10 20
  [ "${out[0]}" = f1:10 ] && [ "${out[1]}" = f2:20 ]
  fzx::_output_items out '#{n} {}!' 7 -- 'whole row'
  [ "${out[0]}" = '#7 whole row!' ]
  fzx::_output_items out '{1}' --
  [ "${#out[@]}" -eq 0 ]
  fzx::_output_placeholders '{1}:{2}' ph
  [ "$ph" = '{+n} -- {+1} {+2}' ]
  fzx::_output_placeholders '{n}' ph
  [ "$ph" = '{+n} --' ]
  FZX_OPTS=(--accept-nth=3)
  fzx::_output_template ph
  [ "$ph" = '{3}' ]
  FZX_OPTS=(--accept-nth '{1}:{2}')
  fzx::_output_template ph
  [ "$ph" = '{1}:{2}' ]
  FZX_OPTS=()
  fzx::_output_template ph
  [ "$ph" = '{}' ]
}

@test "binds: --loop sends on enter and stays; ctrl-] sends and closes; a picker" {
  run "$FZX" -m counter --loop --dry-run
  [ "$status" -eq 0 ]
  "$FZX" -m counter --loop > /dev/null
  [ "$(fzf_bind enter)" = "enter:transform($FZX _cb output loop items {+n} -- {+})" ]
  [ "$(fzf_binds 'ctrl-]' | tail -1)" = "ctrl-]:become($FZX _cb output once items {+n} -- {+})" ]
  [ "$(fzf_binds enter | wc -l)" -eq 1 ] || [[ "$(fzf_binds enter | tail -1)" == *"output loop"* ]]
  ! grep -q 'bound twice' "$LOG"
}

@test "binds: --to sends on enter and closes; --submit needs --to; the module's own enter is kept" {
  "$FZX" -m counter --to right > /dev/null
  [[ "$(fzf_binds enter | tail -1)" == "enter:become($FZX _cb output once items {+n} -- {+})" ]]
  [[ "$(fzf_binds 'ctrl-]' | tail -1)" == "ctrl-]:become($FZX _cb output once items"* ]]
  run "$FZX" -m counter --submit
  [ "$status" -eq 2 ]
  [[ "$output" == *"--submit needs --to"* ]]
  run "$FZX" -m counter --to %9
  [ "$status" -eq 2 ]
  COUNTER_BIND_ENTER=1 "$FZX" -m counter --to right --loop > /dev/null
  [ "$(fzf_binds enter | tail -1)" = "enter:accept" ]
}

@test "binds: a default action that prints is what goes out (history's insert)" {
  run "$FZX" -m history --loop --dry-run
  [[ "$output" == *"'enter:transform($FZX _cb output loop action insert {+1})'"* ]]
}

@test "todos --paste PANE is --to PANE: enter pastes the lines through the output callback" {
  "$FZX" -m todos --paste %2 > /dev/null
  [ "$(fzf_binds enter | tail -1)" = "enter:become($FZX _cb output once items {+n} -- {+3})" ]
}

@test "callback: loop pastes, notes it in the footer, clears the selection and reloads" {
  load_libs log session
  fzx::session_create counter "$COUNTER_DIR"
  FZX_OUTPUT_PANE=%2 run "$FZX" _cb output loop items 0 3 -- a b
  [ "$status" -eq 0 ]
  [[ "$output" == "change-footer"*"sent to %2 (2)"*"+clear-selection+reload($FZX _cb source)" ]]
  [ "$(sed -n '3,4p' "$CALLS")" = $'a\nb' ]
  # a pane gone: the footer says so, the selection stays
  FZX_OUTPUT_PANE=%9 run "$FZX" _cb output loop items 0 -- a
  [[ "$output" == "change-footer"*"pane %9 is gone"* ]]
  [[ "$output" != *clear-selection* ]]
  # and the info line says so from now on
  [[ "$(< "$FZX_SESSION_DIR/meta/output_target")" == *"%9 (gone)"* ]]
  [[ "$output" == *"+toggle+toggle" ]]
}

@test "callback: without a pane the lines go to the root's out file; once prints nothing" {
  load_libs log session
  fzx::session_create counter "$COUNTER_DIR"
  run "$FZX" _cb output loop items 0 -- one
  [[ "$output" == *"printed"* ]]
  run "$FZX" _cb output once items 0 -- two
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(< "$FZX_SESSION_DIR/out")" = $'one\ntwo' ]
}

@test "owner: --loop output is streamed to a pipe, then the rest once fzf closes" {
  export STUB_FZF_RUN="'$FZX' _cb output loop items 0 -- first > /dev/null; sleep 0.3; '$FZX' _cb output loop items 0 1 -- second third > /dev/null"
  run --separate-stderr "$FZX" -m counter --loop
  [ "$status" -eq 0 ]
  [ "$output" = $'first\nsecond\nthird' ]
}

@test "title and info: the loop icon in the title, the target pane and its command after fzf's info" {
  # the stub answers #{pane_current_command} with zsh for a pane it knows
  sed -i 's/^    awk -v t="\$t"/    [[ "${5:-}" == "#{pane_id} #{pane_current_command}" ]] \&\& { awk -v t="$t" '"'"'$1 == t { print $1 " zsh"; f = 1 } END { exit !f }'"'"' "$panes"; exit; }\n    awk -v t="$t"/' "$BATS_TEST_TMPDIR/bin/tmux"
  export FZX_TITLE_CURRENT_COLOR="" FZX_ICONS=unicode NO_COLOR=1
  "$FZX" -m counter --loop --to right > /dev/null
  read_fzf_args
  run grep '^--border-label=' < <(printf '%s\n' "${FZF_ARGS[@]}")
  [ "$output" = "--border-label= counter:one ∞ " ]
  run grep '^--info-command=' < <(printf '%s\n' "${FZF_ARGS[@]}")
  [[ "$output" == "--info-command=IFS= read -r m < "*"/meta/output_target; printf %s \"\$FZF_INFO  \$m\"" ]]
  # the command, as fzf runs it, over the file the launch wrote
  local f="$BATS_TEST_TMPDIR/target"
  printf '◎ %%2 zsh\n' > "$f"
  [ "$(FZF_INFO='2/2 (0)' bash -c "IFS= read -r m < $f; printf %s \"\$FZF_INFO  \$m\"")" = '2/2 (0)  ◎ %2 zsh' ]
  # an in-place refresh (lib/nav.sh) makes the title again from the session: the mark comes with it
  libs
  local m
  fzx::session_create counter "$COUNTER_DIR"
  fzx::meta_set title_marks " ∞"
  fzx::session_title m
  [ "$m" = "counter ∞" ]
  # words without icons; a pane that is gone says so
  FZX_ICONS=none FZX_LOOP=1 fzx::output_title m
  [ "$m" = " loop" ]
  FZX_ICONS=none FZX_OUTPUT_PANE=%2 fzx::output_target m
  [ "$m" = "to %2 zsh" ]
  FZX_OUTPUT_PANE=%9 fzx::output_target m
  [ "$m" = "◎ %9 (gone)" ]
  # no flags: no marks, no info command
  "$FZX" -m counter > /dev/null
  read_fzf_args
  printf '%s\n' "${FZF_ARGS[@]}" | grep -qx -- '--border-label= counter:one '
  ! printf '%s\n' "${FZF_ARGS[@]}" | grep -q -- '--info-command'
}
