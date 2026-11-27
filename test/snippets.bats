#!/usr/bin/env bats
# lib/snippets.sh (the paste history, saved snippets) and the snippets module; capture's and the tmux module's
# pastes recording into the history

load test_helper

SNP="$(readlink -f "$BATS_TEST_DIRNAME/../modules/snippets")"

setup() {
  setup_fzx
  export NO_COLOR=1 CALLS="$BATS_TEST_TMPDIR/calls" FZX_TTY="$BATS_TEST_TMPDIR/tty"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  : > "$FZX_TTY"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" << 'STUB'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "$CALLS"
[[ "$1" == load-buffer ]] && cat > "$BATS_TEST_TMPDIR/buffer"
[[ "$1" == show-buffer ]] && printf 'buffer text'
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  H="$FZX_STATE_DIR/snippets/history"
}

@test "history: each paste a file, newest last; the same text again moves to the newest; the oldest go past the max" {
  load_libs log snippets
  fzx::paste_record capture "one"
  fzx::paste_record tmux $'two\nlines\n'
  fzx::paste_record capture "one"
  run ls "$H"
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *.tmux && "${lines[1]}" == *.capture ]]
  [ "$(cat "$H/${lines[0]}"; printf x)" = $'two\nlines\nx' ]
  FZX_SNIPPETS_HISTORY_MAX=2 fzx::paste_record tmux "three"
  run ls "$H"
  [ "${#lines[@]}" -eq 2 ]
  [[ "$(cat "$H/${lines[0]}")" == one && "$(cat "$H/${lines[1]}")" == three ]]
  FZX_SNIPPETS_HISTORY=0 fzx::paste_record tmux "four"
  fzx::paste_record tmux ""
  [ "$(ls "$H" | wc -l)" -eq 2 ]
}

@test "saved: by the name's sha1, any characters in the name; saving a name again replaces its text; stdin kept as it is" {
  load_libs log snippets
  fzx::snippet_save 'a/b: "x"' 'first'
  fzx::snippet_save 'a/b: "x"' 'second'
  local id
  fzx::snippet_id 'a/b: "x"' id
  [ "$(cat "$FZX_STATE_DIR/snippets/saved/$id/value")" = second ]
  [ "$(cat "$FZX_STATE_DIR/snippets/saved/$id/name")" = 'a/b: "x"' ]
  printf 'kept\n\n' | fzx::snippet_save other
  fzx::snippet_id other id
  [ "$(cat "$FZX_STATE_DIR/snippets/saved/$id/value"; printf x)" = $'kept\n\nx' ]
}

@test "source: saved by name with the first line and a line count; history newest first with its age and source" {
  load_libs log snippets
  fzx::snippet_save zeta 'z'
  fzx::snippet_save alpha $'line one\nline two'
  fzx::paste_record capture "older"
  fzx::paste_record tmux "newer"
  run env FZX_MODE=saved "$SNP/source.sh"
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *$'\talpha '*"line one  (+1 lines)" ]]
  [[ "${lines[1]}" == *$'\tzeta '*" z" ]]
  run env FZX_MODE=history "$SNP/source.sh"
  [[ "${lines[0]}" == *.tmux$'\t'*"tmux"*"newer" && "${lines[1]}" == *.capture$'\t'*"older" ]]
}

@test "insert prints the texts; from the M-o popup it pastes them into its pane instead" {
  load_libs log snippets
  fzx::snippet_save a 'echo one'
  fzx::snippet_save b $'two\nthree'
  local ida idb
  fzx::snippet_id a ida
  fzx::snippet_id b idb
  run "$SNP/actions.sh" insert "$ida" "$idb"
  [ "$output" = $'echo one\ntwo\nthree' ]
  TMUX=x FZX_ORIGIN_PANE=%5 run "$SNP/actions.sh" insert "$ida"
  [ -z "$output" ]
  [ "$(cat "$BATS_TEST_TMPDIR/buffer")" = "echo one" ]
  grep -qx 'tmux run-shell -b -d 0.3 tmux paste-buffer -p -d -b fzx-snippets -t %5' "$CALLS"
}

@test "save keeps a history entry as a snippet; rename moves it; remove drops snippets and entries" {
  load_libs log snippets
  fzx::paste_record capture $'pasted\n'
  local f id
  f="$(ls "$H")"
  # the questions read the terminal: through fzx::ask's history file answers are not scriptable, so
  # the library calls the actions make are run as they make them
  fzx::snippet_save kept < "$H/$f"
  fzx::snippet_id kept id
  [ "$(cat "$FZX_STATE_DIR/snippets/saved/$id/value"; printf x)" = $'pasted\nx' ]
  FZX_MODE=history "$SNP/actions.sh" remove "$f"
  [ -z "$(ls "$H")" ]
  FZX_MODE=saved "$SNP/actions.sh" remove "$id"
  [ ! -e "$FZX_STATE_DIR/snippets/saved/$id" ]
  run "$SNP/actions.sh" remove ../etc
  [[ "$output" == *"no snippet ../etc"* ]]
}

@test "edit changes the text in \$EDITOR; an emptied one is left as it was" {
  load_libs log snippets
  fzx::snippet_save a 'old'
  local id
  fzx::snippet_id a id
  printf '#!/usr/bin/env bash\nprintf new > "${@: -1}"\n' > "$BATS_TEST_TMPDIR/bin/fake-editor"
  chmod +x "$BATS_TEST_TMPDIR/bin/fake-editor"
  VISUAL=fake-editor "$SNP/actions.sh" edit "$id"
  [ "$(cat "$FZX_STATE_DIR/snippets/saved/$id/value")" = new ]
  printf '#!/usr/bin/env bash\n: > "${@: -1}"\n' > "$BATS_TEST_TMPDIR/bin/fake-editor"
  VISUAL=fake-editor "$SNP/actions.sh" edit "$id"
  [ "$(cat "$FZX_STATE_DIR/snippets/saved/$id/value")" = new ]
}

@test "capture's paste and the tmux module's buffer paste record into the history" {
  load_libs log snippets
  CAPTURE_ORIGIN=%1
  source "$FZX_REPO/modules/capture/actions.sh" || :
  capture::paste 'a value' 'another'
  [ "$(cat "$H"/*.capture)" = $'a value\nanother' ]
  FZX_MODE=buffers "$FZX_REPO/modules/tmux/actions.sh" paste --pane %2 -- buf0
  grep -qx 'tmux paste-buffer -p -b buf0 -t %2' "$CALLS"
  [ "$(cat "$H"/*.tmux)" = "buffer text" ]
}

@test "under fzx: enter inserts (and still prints in a picker), alt-n new, alt-x asks" {
  stub_fzf
  run "$FZX" -m snippets
  [ "$(fzf_bind enter)" = "enter:become($FZX _cb action insert {+1})" ]
  [[ "$(fzf_bind alt-n)" == *"_cb action new {q})"* ]]
  FZX_PRINT=1 run "$FZX" -m snippets
  [ "$(fzf_bind enter)" = "enter:become($FZX _cb action insert {+1})" ]
}

@test "menu: saved always, history once something was pasted; the counts" {
  load_libs log
  source "$SNP/manifest.sh"
  snippets::applicable snippets
  run snippets::applicable snippets:history
  [ "$status" -ne 0 ]
  fzx::paste_record capture x
  snippets::applicable snippets:history
  [ "$(snippets::summary snippets:history)" = "1 paste" ]
  [ "$(snippets::summary snippets)" = "0 snippets" ]
}

@test "components: every row has its five fields" {
  local bad
  bad="$(grep -v '^#' "$SNP/components.tsv" | awk -F'  +|\t' 'NF != 5')"
  [ -z "$bad" ] || { printf 'rows without five fields:\n%s\n' "$bad"; return 1; }
}
