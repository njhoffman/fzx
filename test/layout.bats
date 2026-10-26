#!/usr/bin/env bats
# responsive preview layout: FZX_PREVIEW_LAYOUTS applied on start and resize through `fzx _cb layout`

load test_helper

setup() {
  setup_fzx
  stub_fzf
  mkdir -p "$FZX_CONFIG_DIR/modules/counter"
  conf 'FZX_PREVIEW_LAYOUTS=("0:hidden" "80:down,50%" "180:")'
}

conf() { printf '%s\n' "$@" > "$FZX_CONFIG_DIR/modules/counter/config.sh"; }

# start a kept counter session; SID is its id
start_session() {
  "$FZX" --keep -m counter
  SID="$(basename "$(session_dirs)")"
}

# layout callback for the session: lay <event> <columns> [preview columns, empty = hidden]
lay() {
  FZX_SESSION="$SID" FZF_COLUMNS="$2" FZF_PREVIEW_COLUMNS="${3:-}" run "$FZX" _cb layout "$1"
}

state() { cat "$FZX_RUNTIME_DIR/sessions/$SID/state/$1"; }

@test "start and resize callbacks are appended to the events' bindings" {
  run "$FZX" -m counter
  [ "$(fzf_binds start)" = "start:reload:$FZX _cb load
start:+transform:$FZX _cb layout start" ]
  [ "$(fzf_binds resize)" = "resize:+transform:$FZX _cb layout resize" ]
}

@test "no layouts, or standalone: nothing is bound" {
  conf 'FZX_PREVIEW_LAYOUTS=()'
  run "$FZX" -m counter
  [ -z "$(fzf_binds resize)" ]
  conf 'FZX_PREVIEW_LAYOUTS=("0:down")'
  run "$FZX_REPO/test/fixtures/modules/counter/module.sh"
  [ -z "$(fzf_binds resize)" ]
}

@test "bad entries are skipped with a warning" {
  conf 'FZX_PREVIEW_LAYOUTS=("wide:right" "0:down,40%")'
  start_session
  grep -q "FZX_PREVIEW_LAYOUTS: bad entry 'wide:right'" "$LOG"
  [ "$(cat "$FZX_RUNTIME_DIR/sessions/$SID/meta/preview_layouts")" = "0:down,40%" ]
}

@test "start applies the entry the width falls in; the module's own spec needs no action" {
  start_session
  lay start 60 50
  [ "$output" = "change-preview-window(hidden)" ]
  lay start 120 50
  [ "$output" = "change-preview-window(down,50%)" ]
  [ "$(state layout)" = "80:down,50%" ]
  lay start 200 50
  [ -z "$output" ]
  [ "$(state layout)" = "180:" ]
}

@test "entries apply by width regardless of their order" {
  conf 'FZX_PREVIEW_LAYOUTS=("150:right,60%" "0:down")'
  start_session
  lay start 100 50
  [ "$output" = "change-preview-window(down)" ]
  lay resize 160 50
  [ "$output" = "change-preview-window(right,60%)" ]
}

@test "resize within the same entry prints nothing; crossing a breakpoint applies the new one" {
  start_session
  lay start 120 50
  lay resize 150 50
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  lay resize 200 50
  [ "$output" = "change-preview-window()" ]
  lay resize 60 50
  [ "$output" = "change-preview-window(hidden)" ]
}

@test "a preview hidden by hand stays hidden across breakpoints, in the new layout" {
  start_session
  lay start 200 70
  # hidden by hand: no preview columns
  lay resize 120 ""
  [ "$output" = "change-preview-window(down,50%,hidden)" ]
  lay resize 200 ""
  [ "$output" = "change-preview-window(hidden)" ]
  grep -q "layout resize 200 cols: 80:down,50% -> 180: (kept hidden)" "$LOG"
}

@test "a preview shown by hand where the entry hides it stays shown" {
  conf 'FZX_PREVIEW_LAYOUTS=("0:hidden" "70:hidden" "180:")'
  start_session
  lay start 60 ""
  [ "$output" = "change-preview-window(hidden)" ]
  # shown by hand, then a resize into another hiding entry: left alone
  lay resize 75 40
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # hidden again once an entry that shows it came between
  lay resize 200 40
  [ "$output" = "change-preview-window()" ]
  lay resize 60 90
  [ "$output" = "change-preview-window(hidden)" ]
}

@test "below the smallest breakpoint nothing applies" {
  conf 'FZX_PREVIEW_LAYOUTS=("100:down")'
  start_session
  lay start 80 50
  [ -z "$output" ]
  [ ! -f "$FZX_RUNTIME_DIR/sessions/$SID/state/layout" ]
}

@test "become() keeps a hand-hidden preview: nav saves it, start applies it" {
  start_session
  lay start 120 50
  FZX_SESSION="$SID" FZF_COLUMNS=120 FZF_PREVIEW_COLUMNS="" run "$FZX" _cb nav resume
  [[ "$output" == become:* ]]
  [ "$(state preview_hidden)" = 1 ]
  lay start 120 ""
  [ "$output" = "change-preview-window(down,50%,hidden)" ]
  # shown again before the next become(): the flag goes
  FZX_SESSION="$SID" FZF_COLUMNS=120 FZF_PREVIEW_COLUMNS=60 run "$FZX" _cb nav resume
  [ ! -f "$FZX_RUNTIME_DIR/sessions/$SID/state/preview_hidden" ]
  lay start 120 60
  [ "$output" = "change-preview-window(down,50%)" ]
}

@test "the menu keeps its start reload and refresh with layouts and tracing on" {
  FZX_TRACE=start run "$FZX"
  [ "$(fzf_binds start | head -1)" = "start:reload:$FZX _cb load" ]
  fzf_binds start | grep -qxF "start:+transform:$FZX _cb layout start"
  fzf_binds start | grep -qxF "start:+bg-transform:$FZX _cb trace start"
}
