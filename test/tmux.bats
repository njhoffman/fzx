#!/usr/bin/env bats
# Integration tests use a private server and an empty config; never the user's tmux server.
load test_helper

setup() {
  setup_fzx
  export FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null
  export LSAN_OPTIONS=detect_leaks=0
  unset TMUX_PANE FZX_TMUX_PANE FZX_TOGGLES TMUX_PREFIX FZX_TMUX_SESSION_PREFIX
  export TMUX_MOD="$FZX_REPO/modules/tmux"
  export TEST_TMUX_BIN="$(command -v tmux)"
  export TEST_TMUX_SOCKET="$BATS_TEST_TMPDIR/tmux.sock"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${TEST_TMUX_SWITCH_LOG:-}" && ( "$1" == switch-client || "$1" == attach-session ) ]]; then
  printf '%s\n' "$@" > "$TEST_TMUX_SWITCH_LOG"
  exit 0
fi
exec "$TEST_TMUX_BIN" -S "$TEST_TMUX_SOCKET" "$@"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  tmux -f /dev/null new-session -d -s first -x 150 -y 35 'bash --noprofile --norc'
  export TMUX_PANE="$(tmux display-message -p -t first '#{pane_id}')"
  export PANE="$TMUX_PANE"
  export SECOND="$(tmux new-session -d -s second -P -F '#{session_id}' 'sleep 600')"
}

teardown() {
  tmux kill-server 2>/dev/null || :
}

src() {
  FZX_MODE="$1" "$TMUX_MOD/source.sh" "${@:2}" > "$BATS_TEST_TMPDIR/src.out"
  local rc=$?
  sed 's/\x1b\[[0-9;]*m//g' "$BATS_TEST_TMPDIR/src.out"
  return "$rc"
}
act() { FZX_MODE="$1" "$TMUX_MOD/actions.sh" "${@:2}"; }

@test "tmux: sessions, windows and panes use stable IDs across rename" {
  run src sessions
  [ "$status" -eq 0 ]
  [[ "$output" == *$'$0\tfirst '* && "$output" == *"$SECOND"$'\tsecond '* ]] || { printf '%s\n' "$output"; return 1; }
  run src windows
  [[ "$output" == *$'$0:@0\tfirst:'* ]]
  run src panes
  [[ "$output" == *"$PANE"$'\tfirst:'* ]]
  tmux rename-session -t '$0' 'name with spaces'
  run src sessions
  [[ "$output" == *$'$0\tname with spaces '* ]]
}

@test "tmux: sessions, windows and panes sort by tmux's order, last activity or name; the age shows, the sorted column underlined" {
  run src sessions
  [[ "${lines[0]}" =~ $'\t'.*\ \ [0-9]+[smhd]$'\t' ]] || { printf '%s\n' "$output"; return 1; }
  ! grep -q $'\e\[4m' "$BATS_TEST_TMPDIR/src.out"
  tmux rename-session -t '$0' zeta
  FZX_SORT=name run src sessions
  [[ "${lines[0]}" == *$'\tsecond '* && "${lines[1]}" == *$'\tzeta '* ]]
  grep -q $'\e\[4m\e\[[0-9;]*msecond' "$BATS_TEST_TMPDIR/src.out"
  FZX_SORT=recent run src windows
  grep -q $'\e\[4m\e\[[0-9;]*m[0-9]*[smhd]\e' "$BATS_TEST_TMPDIR/src.out"
}

@test "tmux: reference modes read installed commands, bindings, options and variables" {
  local mode
  # hooks lists only set hooks, and the empty test server has none
  tmux set-hook -g after-new-window 'display-message hook-test'
  for mode in commands keys options variables styles formats status hooks; do
    run src "$mode"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\t'* ]]
  done
  run src variables
  [[ "$output" == *'#{pane_id}'$'\t'*"$PANE"* ]]
  run src styles
  [[ "$output" == *'-style'* ]]
}

@test "tmux: color stays in display fields and metadata never changes accepted IDs" {
  local mode line id display metadata
  for mode in sessions commands variables keys; do
    FZX_MODE="$mode" "$TMUX_MOD/source.sh" > "$BATS_TEST_TMPDIR/color.out"
    IFS=$'\t' read -r id display metadata < "$BATS_TEST_TMPDIR/color.out"
    [[ "$id" != *$'\e'* ]]
    [[ "$display" == *$'\e['* ]]
    jq -e 'type == "object"' <<< "$metadata" > /dev/null
  done
}

@test "tmux: key notes, repeat/change markers, defaults and free keys" {
  tmux bind-key -r -T prefix -N 'Custom test note' F12 display-message 'literal $HOME; quotes'
  tmux unbind-key -q -T prefix F11
  FZX_TOGGLES=changed run src keys --table prefix
  [ "$status" -eq 0 ]
  [[ "$output" == *'Custom test note'* && "$output" == *'*+'* ]]
  [[ "$output" != *'[root]'* ]]
  local line id display metadata
  line="$(printf '%s\n' "$output" | rg 'Custom test note')"
  IFS=$'\t' read -r id display metadata <<< "$line"
  [ "$(jq -r .key <<< "$metadata")" = F12 ]
  FZX_MODE=keys run "$TMUX_MOD/preview.sh" -- "$id" "$display" "$metadata"
  [ "$status" -eq 0 ]
  [[ "$output" == *'CURRENT BINDING'* && "$output" == *'DEFAULT BINDING'* && "$output" == *literal*'$HOME'*quotes* ]]
  FZX_TOGGLES=unassigned run src keys --table prefix
  [ "$status" -eq 0 ]
  [[ "$output" == *$'F11\t'* && "$output" != *$'F12\t'* ]]
}

@test "tmux: option scopes, overrides, custom filtering and hooks" {
  tmux set-option -g status-left global-value
  tmux set-option -t first status-left local-value
  tmux set-option -t first @test-user 'some value'
  run src options --pane "$PANE" --option-scope session --user-only
  [ "$status" -eq 0 ]
  [[ "$output" == '@test-user'$'\t'* && "$output" != *status-left* ]]
  FZX_TOGGLES=changed run src options --pane "$PANE" --option-scope session --builtin-only
  [ "$status" -eq 0 ]
  [[ "$output" == *'status-left'*'local-value'* && "$output" != *'@test-user'* ]]
  local line id display metadata
  line="$(printf '%s\n' "$output" | rg '^status-left\b')"
  IFS=$'\t' read -r id display metadata <<< "$line"
  [ "$(jq -r .inherited <<< "$metadata")" = global-value ]
  FZX_MODE=options run "$TMUX_MOD/preview.sh" -- "$id" "$display" "$metadata"
  [ "$status" -eq 0 ]
  [[ "$output" == *'local-value'* && "$output" == *'global-value'* && "$output" == *'OVERRIDDEN'* ]]
  tmux set-hook -t first after-new-window 'display-message hook-test'
  run src hooks --pane "$PANE" --option-scope session
  [[ "$output" == *'after-new-window'*'hook-test'* ]]
}

@test "tmux: styles and formats render actual hex/index colors and expanded values" {
  tmux set-option -t first status-style 'fg=#abcdef,bg=colour17,bold'
  tmux set-option -t first status-left '#[fg=#ff0000]#{session_name}'
  FZX_MODE=styles "$TMUX_MOD/source.sh" --pane "$PANE" --option-scope session > "$BATS_TEST_TMPDIR/styles"
  [[ "$(cat "$BATS_TEST_TMPDIR/styles")" == *$'\e[38;2;171;205;239m'* && "$(cat "$BATS_TEST_TMPDIR/styles")" == *$'\e[48;5;17m'* ]]
  FZX_MODE=formats "$TMUX_MOD/source.sh" --pane "$PANE" --option-scope session > "$BATS_TEST_TMPDIR/formats"
  local id display metadata
  IFS=$'\t' read -r id display metadata < "$BATS_TEST_TMPDIR/formats"
  [ "$id" = status-left ]
  [[ "$(jq -r .rendered <<< "$metadata")" == *first* ]]
  [[ "$display" == *$'\e[38;2;255;0;0m'* ]]
  FZX_MODE=formats run "$TMUX_MOD/preview.sh" --pane "$PANE" -- "$id" "$display" "$metadata"
  [ "$status" -eq 0 ]
  [[ "$output" == *'RENDERED'* && "$output" == *first* ]]
}

@test "tmux: variables include aliases, descriptions, empty values and full preview values" {
  FZX_TOGGLES=empty run src variables --pane "$PANE"
  [ "$status" -eq 0 ]
  [[ "$output" == *'#{pane_id}'*'#D'*'Unique pane ID'* ]]
  [[ "$output" == *'#{buffer_name}'* ]]
  local line id display metadata
  line="$(printf '%s\n' "$output" | rg '^#\{pane_id\}')"
  IFS=$'\t' read -r id display metadata <<< "$line"
  FZX_MODE=variables run "$TMUX_MOD/preview.sh" -- "$id" "$display" "$metadata"
  [ "$status" -eq 0 ]
  [[ "$output" == *'CURRENT VALUE'*"$PANE"* && "$output" == *'Unique pane ID'* ]]
}

@test "tmux: cycle sessions with prefix matching and call configured alias helpers" {
  export TEST_TMUX_SWITCH_LOG="$BATS_TEST_TMPDIR/switch"
  tmux rename-session -t first group-one
  tmux rename-session -t second group-two
  TMUX=fake run act sessions next-session --prefix group- --
  [ "$status" -eq 0 ]
  [ "$(tail -n1 "$TEST_TMUX_SWITCH_LOG")" = "$SECOND" ]
  TMUX=fake run act sessions prev-session --prefix group- --
  [ "$status" -eq 0 ]
  [ "$(tail -n1 "$TEST_TMUX_SWITCH_LOG")" = "$SECOND" ]
  run src sessions --prefix group-two
  [[ "$output" == "$SECOND"$'\t'* && "$output" != *group-one* ]]
  export FZX_TMUX_HELPERS="$BATS_TEST_TMPDIR/helpers" HELPER_LOG="$BATS_TEST_TMPDIR/helper.log"
  mkdir -p "$FZX_TMUX_HELPERS"
  local helper
  for helper in apply-theme popup-shell nvim-layout; do
    cat > "$FZX_TMUX_HELPERS/$helper.sh" <<'HELPER'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" "$@" >> "$HELPER_LOG"
HELPER
    chmod +x "$FZX_TMUX_HELPERS/$helper.sh"
  done
  act sessions theme-float -- "$SECOND"
  [ "$(cat "$HELPER_LOG")" = $'apply-theme.sh\n'"$SECOND"$'\nfloat' ]
  act sessions scratch --
  act sessions nvim-layout --
  [[ "$(cat "$HELPER_LOG")" == *'popup-shell.sh'*'nvim-layout.sh'* ]]
}

@test "tmux: file-backed format samples and variables work without a live server" {
  cat > "$BATS_TEST_TMPDIR/options" <<'OPTIONS'
status-left '#[fg=#ff0000]#S #{pane_title}'
status-style fg=colour81,bg=colour17
OPTIONS
  cat > "$BATS_TEST_TMPDIR/data" <<'DATA'
session_name="offline session"
pane_title="sample title"
DATA
  tmux kill-server
  run src formats --options-file "$BATS_TEST_TMPDIR/options" --data-file "$BATS_TEST_TMPDIR/data"
  [ "$status" -eq 0 ]
  [[ "$output" == *'offline session sample title'* ]]
  run src variables --data-file "$BATS_TEST_TMPDIR/data"
  [ "$status" -eq 0 ]
  [[ "$output" == *'#{pane_title}'*'sample title'* ]]
}

@test "tmux: live colored key browser previews notes and accepts only the plain binding" {
  tmux bind-key -r -T prefix -N 'Styled test note UniqueTmuxFzx' F12 display-message 'chosen value'
  local picker state screen n
  printf -v picker '%q -m tmux:keys --query %q --table prefix > %q' "$FZX" "'UniqueTmuxFzx" "$BATS_TEST_TMPDIR/accepted"
  tmux new-window -d -n references "$picker"
  for n in {1..80}; do
    state="$("$FZX" debug state 2>/dev/null)" || :
    screen="$(tmux capture-pane -p -e -t references 2>/dev/null)" || :
    [[ "$screen" == *'DEFAULT BINDING'* && "$screen" == *'Styled test note'* ]] && break
    sleep 0.05
  done
  [[ "$screen" == *'CURRENT BINDING'* && "$screen" == *'DEFAULT BINDING'* && "$screen" == *$'\e['* ]] || {
    printf '%s\n' "$screen"
    printf '%s' "$state" | jq '{query, matchCount, totalCount, current:(.current.text|split("\t")[0]|.[0:100])}'
    return 1
  }
  "$FZX" debug send accept
  for n in {1..60}; do
    [[ -s "$BATS_TEST_TMPDIR/accepted" ]] && break
    sleep 0.05
  done
  local accepted="$(cat "$BATS_TEST_TMPDIR/accepted")"
  [[ "$accepted" == 'bind-key -r -T prefix F12 '* && "$accepted" != *$'\e'* && "$accepted" != *'"changed"'* ]]
}

@test "tmux: buffers preview exact contents and delete by name" {
  printf 'literal $HOME; "quotes"\nsecond line' | tmux load-buffer -b 'named buffer' -
  run src buffers
  [[ "$output" == 'named buffer'$'\t'* ]]
  FZX_MODE=buffers run "$TMUX_MOD/preview.sh" -- 'named buffer' ''
  [ "$output" = $'literal $HOME; "quotes"\nsecond line' ]
  run act buffers kill -- 'named buffer'
  [ "$status" -eq 0 ]
  run src buffers
  [ -z "$output" ]
}

@test "tmux: rename and move retain spaces and stable targets" {
  source "$TMUX_MOD/actions.sh" || :
  tmux::ask() { printf -v "$2" '%s' "$ANSWER"; }
  export FZX_MODE=windows
  ANSWER='window with spaces'
  tmux::action rename -- '@0'
  [ "$(tmux display-message -p -t '@0' '#{window_name}')" = "$ANSWER" ]
  ANSWER="$SECOND"
  tmux::action move -- '@0'
  [ "$(tmux display-message -p -t '@0' '#{session_id}')" = "$SECOND" ]
}

@test "tmux: link, swap and mark operate on selected objects" {
  source "$TMUX_MOD/actions.sh" || :
  tmux::ask() { printf -v "$2" '%s' "$ANSWER"; }
  FZX_MODE=windows ANSWER="$SECOND" tmux::action link -- '@0'
  [[ "$(tmux list-windows -t "$SECOND" -F '#{window_id}')" == *'@0'* ]]
  [ "$(tmux display-message -p -t "$SECOND:@0" '#{session_id}')" = "$SECOND" ]
  FZX_MODE=windows ANSWER='@1' tmux::action swap -- '@0'
  FZX_MODE=panes tmux::action mark -- "$PANE"
  [ "$(tmux display-message -p -t "$PANE" '#{pane_marked}')" = 1 ]
}

@test "tmux: live fzf opens the capture module on a pane and uses Escape to return and quit" {
  local picker state sid root n
  printf -v picker '%q -m tmux:panes --pane %q' "$FZX" "$PANE"
  tmux new-window -d -n picker "$picker"
  for n in {1..60}; do
    state="$("$FZX" debug state 2>/dev/null)" || :
    [[ "$state" == *'first:'* ]] && break
    sleep 0.05
  done
  [[ "$state" == *'first:'* ]] || { tmux capture-pane -p -t picker; return 1; }
  "$FZX" debug send 'change-query(first:)+first'
  for n in {1..60}; do
    state="$("$FZX" debug state 2>/dev/null)" || :
    [[ "$(printf '%s' "$state" | jq -r .query)" == first: ]] && break
    sleep 0.05
  done
  "$FZX" debug send 'trigger(ctrl-o)'
  for n in {1..60}; do
    for sid in "$FZX_RUNTIME_DIR"/sessions/*; do
      [[ -f "$sid/meta/module" && -f "$sid/state/mode" && "$(cat "$sid/meta/module")" == capture &&
        "$(cat "$sid/state/mode")" == lines ]] && break 2
    done
    sleep 0.05
  done
  [ "$(cat "$sid/state/mode")" = lines ]
  for n in {1..60}; do
    "$FZX" debug state "${sid##*/}" >/dev/null 2>&1 && break
    sleep 0.05
  done
  "$FZX" debug send 'trigger(alt-0)' "${sid##*/}" || { cat "$LOG"; return 1; }
  for n in {1..60}; do
    [[ "$(cat "$sid/state/mode")" == urls ]] && break
    sleep 0.05
  done
  [ "$(cat "$sid/state/mode")" = urls ]
  root="$(cat "$sid/meta/root")"
  "$FZX" debug send 'trigger(esc)' "${sid##*/}"
  for n in {1..60}; do
    state="$("$FZX" debug state "$root" 2>/dev/null)" || :
    [[ "$(printf '%s' "$state" | jq -r .query)" == first: ]] && break
    sleep 0.05
  done
  [ "$(printf '%s' "$state" | jq -r .query)" = first: ] || { printf '%s\n' "$state"; cat "$LOG"; return 1; }
  "$FZX" debug send 'trigger(esc)' "$root"
  for n in {1..60}; do
    [[ ! -d "$FZX_RUNTIME_DIR/sessions/$root" ]] && break
    sleep 0.05
  done
  [ ! -d "$FZX_RUNTIME_DIR/sessions/$root" ]
}

@test "tmux: switch selects panes across sessions and attaches outside tmux" {
  export TEST_TMUX_SWITCH_LOG="$BATS_TEST_TMPDIR/switch"
  target="$(tmux display-message -p -t "$SECOND" '#{pane_id}')"
  TMUX=fake run act panes switch -- "$target"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMUX_SWITCH_LOG")" = $'switch-client\n-t\n'"$SECOND" ]
  run act sessions switch -- '$0'
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMUX_SWITCH_LOG")" = $'attach-session\n-t\n$0' ]
}

@test "tmux: invalid arguments and IDs fail before modifying a session" {
  run src sessions --pane bad
  [ "$status" -eq 2 ]
  # the capture modes moved to the capture module
  run src lines
  [ "$status" -eq 2 ]
  run src unknown
  [ "$status" -eq 2 ]
  run act sessions kill -- first
  [ "$status" -eq 2 ]
  run act commands kill -- kill-server
  [ "$status" -eq 0 ]
  tmux has-session -t first
}

@test "tmux: callback mode changes, confirmation and pane arguments are wired into fzf" {
  stub_fzf
  export STUB_FZF_RUN='"$FZX_REPO/bin/fzx" _cb source'
  run "$FZX" -m tmux:panes --pane "$PANE"
  [ "$status" -eq 0 ]
  run fzf_bind ctrl-x
  [[ "$output" == *'_cb action kill --pane '* && "$output" == *'+reload('* ]]
  run fzf_bind ctrl-o
  [[ "$output" == *'_cb transform capture'* ]]
  run fzf_flag --preview
  [[ "$output" == *"--pane $PANE -- {1} {2} {3}" ]]
}

@test "tmux: hooks list only set hooks unless the empty toggle is on" {
  tmux set-hook -g after-new-window 'display-message hook-test'
  run src hooks
  [ "$status" -eq 0 ]
  [[ "$output" == *'after-new-window'*'hook-test'* ]]
  [[ "$output" != *'after-bind-key'* ]]
  FZX_TOGGLES=empty run src hooks
  [[ "$output" == *'after-bind-key'* ]]
}

@test "tmux: formats leave out keyword options named *-format" {
  tmux set-option -s extended-keys-format csi-u 2> /dev/null || skip "this tmux has no extended-keys-format"
  run src formats
  [ "$status" -eq 0 ]
  [[ "$output" == *'window-status-format'* && "$output" != *'extended-keys-format'* ]]
}

@test "tmux: command reference has no wrapped signature or hyphenation breaks" {
  local line id display metadata
  line="$(src commands | rg '^split-window\t')"
  IFS=$'\t' read -r id display metadata <<< "$line"
  FZX_MODE=commands run "$TMUX_MOD/preview.sh" -- "$id" "$display" "$metadata"
  [ "$status" -eq 0 ]
  local reference="${output#*REFERENCE}"
  [[ "$reference" == *'Create a new pane'* ]]
  [[ "$reference" != *'(alias:'* && "$reference" != *$'‐ '* ]]
}

@test "tmux: nvim opens a reference list as plain text and refuses other screens" {
  export FZX_TMUX_NVIM="$BATS_TEST_TMPDIR/nvim" NVIM_COPY="$BATS_TEST_TMPDIR/nvim.copy"
  cat > "$FZX_TMUX_NVIM" <<'NVIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$NVIM_COPY.args"
cp -- "${@: -1}" "$NVIM_COPY"
NVIM
  chmod +x "$FZX_TMUX_NVIM"
  run act commands nvim --
  [ "$status" -eq 0 ]
  grep -q '^split-window ' "$NVIM_COPY"
  ! grep -q $'\e' "$NVIM_COPY"
  grep -qx 'setlocal buftype=nofile filetype=tmux' "$NVIM_COPY.args"
  run act sessions nvim --
  [ "$status" -eq 2 ]
  [[ "$output" == *'reference lists'* ]]
}
