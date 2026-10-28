#!/usr/bin/env bats
# the todos module over fixture TODO.md files

load test_helper

TODOS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/todos")"

setup() {
  setup_fzx
  export TODO_TODAY=2026-10-26 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  P="$BATS_TEST_TMPDIR/proj"
  Q="$BATS_TEST_TMPDIR/other"
  mkdir -p "$P/sub" "$Q"
  git init -q "$P" && git init -q "$Q"
  cat > "$P/TODO.md" << 'EOF'
# Project

Categories: module

## 1. Roadmap: what comes next

- [ ] **Low thing.** (p3) [chore] tidy up
- [ ] **Urgent bug.** (p1) [bug]: it breaks
      when run twice

      ```
      - [ ] **Not an item.** (p1) [bug] inside a fence
      ```
- [x] **Shipped.** (p1) [feature] done already
- [ ] **Late.** (p2) [feature] (due 2026-10-01) overdue
- [ ] **New module.** [module] no priority given

## 2. Later

- [ ] **Someday: maybe.** (p2) [feature] a colon in the title
EOF
  printf '## Stuff\n\n- [ ] **Other repo item.** (p1) [bug] x\n' > "$Q/TODO.md"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\n[[ "$1" == list ]] && printf "%%s\\n" "%s" "%s"\n' "$P" "$Q" > "$BATS_TEST_TMPDIR/bin/ghq"
  chmod +x "$BATS_TEST_TMPDIR/bin/ghq"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

plain() { sed 's/\x1b\[[0-9;]*m//g'; }
# the printable line (field 3) of each row
lines_of() { (cd "$1" && FZX_MODE="${2:-here}" "$TODOS/source.sh") | cut -f3; }

@test "here: open items by urgency, the fence skipped, categories from the Categories line" {
  run lines_of "$P/sub"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  [ "${lines[0]}" = 'TODO.md:15 ☐  (P2) [feature] Late [due 2026-10-01]' ]
  [ "${lines[1]}" = 'TODO.md:8 ☐  (P1) [bug] Urgent bug' ]
  [ "${lines[2]}" = 'TODO.md:16 ☐  (P2) [module] New module' ]
  [ "${lines[3]}" = 'TODO.md:20 ☐  (P2) [feature] Someday: maybe' ]
  [ "${lines[4]}" = 'TODO.md:7 ☐  (P3) [chore] Low thing' ]
}

@test "done toggle adds completed items last; file order sorts by line" {
  FZX_TOGGLES=done run lines_of "$P"
  [ "${#lines[@]}" -eq 6 ]
  [ "${lines[5]}" = 'TODO.md:14 ☑  (P1) [feature] Shipped' ]
  FZX_SORT=file run lines_of "$P"
  [[ "${lines[0]}" == 'TODO.md:7 '* && "${lines[4]}" == 'TODO.md:20 '* ]]
}

@test "all: every repository's TODO.md, labelled by repository" {
  run lines_of "$BATS_TEST_TMPDIR" all
  [ "${#lines[@]}" -eq 6 ]
  [[ "$output" == *'other/TODO.md:3 ☐  (P1) [bug] Other repo item'* ]]
  [[ "$output" == *'proj/TODO.md:8 ☐  (P1) [bug] Urgent bug'* ]]
}

@test "display: box, priority, category, section up to its colon, overdue in red" {
  run bash -c "cd '$P' && FZX_MODE=here '$TODOS/source.sh' | sed '1!d' | cut -f2"
  [[ "$output" == *$'\e[1;31m[due 2026-10-01, OVERDUE]'* ]]
  [[ "$(plain <<< "$output")" == '☐  P2  feature   Roadmap                       Late  [due 2026-10-01, OVERDUE]' ]]
}

@test "preview: the card with the item's details" {
  local id
  id="$(cd "$P" && FZX_MODE=here "$TODOS/source.sh" | sed -n 2p | cut -f1)"
  run bash -c "'$TODOS/preview.sh' \"\$1\" | sed 's/\x1b\[[0-9;]*m//g'" _ "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Roadmap: what comes next'* && "$output" == *'● P1 high   bug'* ]]
  [[ "$output" == *'Urgent bug'*'TODO.md:8'* && "$output" == *'it breaks when run twice'* ]]
}

@test "done checks the box only while the line still holds that item" {
  local id
  id="$(cd "$P" && FZX_MODE=here "$TODOS/source.sh" | sed -n 2p | cut -f1)"
  chmod 640 "$P/TODO.md"
  run "$TODOS/actions.sh" done "$id"
  [ "$status" -eq 0 ]
  [ "$(sed -n 8p "$P/TODO.md")" = '- [x] **Urgent bug.** (p1) [bug]: it breaks' ]
  [ "$(stat -c %a "$P/TODO.md")" = 640 ]
  # the same id again: no longer open
  run "$TODOS/actions.sh" done "$id"
  [ "$status" -eq 1 ]
  # an item that moved: a line inserted above makes the old id stale
  id="$(cd "$P" && FZX_MODE=here "$TODOS/source.sh" | sed -n 1p | cut -f1)"
  sed -i '3i extra line' "$P/TODO.md"
  run "$TODOS/actions.sh" done "$id"
  [ "$status" -eq 1 ]
  [[ "$output" == *'no longer the open item "Late"'* ]]
  [ "$(grep -c '^- \[x\]' "$P/TODO.md")" = 2 ]
}

@test "edit opens the editor at the item's line" {
  local id
  id="$(cd "$P" && FZX_MODE=here "$TODOS/source.sh" | sed -n 2p | cut -f1)"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/editor.args"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/ed1"
  chmod +x "$BATS_TEST_TMPDIR/bin/ed1"
  VISUAL=ed1 EDITOR=ed1 run "$TODOS/actions.sh" edit "$id"
  [ "$(cat "$BATS_TEST_TMPDIR/editor.args")" = $'+8\n--\n'"$P/TODO.md" ]
}

@test "under fzx: enter prints the lines; --paste makes enter paste into the pane; copy keys" {
  stub_fzf
  cd "$P"
  run "$FZX" -m todos -- p1 bug
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=3 "* && " ${FZF_ARGS[*]} " == *" --query=p1 bug "* ]]
  [[ "$(fzf_bind ctrl-y)" == *'{+4}'* && "$(fzf_bind alt-y)" == *'{+3}'* ]]
  run "$FZX" -m todos -- --paste %7
  [ "$(fzf_bind enter)" = "enter:become:$FZX _cb action paste %7 {+3}" ]
}

@test "here: the nearest TODO.md in the format up to the repository's top; others passed over" {
  # a subdirectory's own list wins over the top's
  mkdir -p "$P/sub/deep"
  printf '## Sub\n\n- [ ] **Sub item.** (p1) [bug] x\n' > "$P/sub/TODO.md"
  run lines_of "$P/sub/deep"
  [ "$output" = 'TODO.md:3 ☐  (P1) [bug] Sub item' ]
  # a TODO.md in another format is skipped for the next one up
  printf '# notes\n\n* something\n' > "$P/sub/TODO.md"
  run lines_of "$P/sub/deep"
  [ "${#lines[@]}" -eq 5 ]
  # outside a repository: the current directory only, never its parents
  mkdir -p "$BATS_TEST_TMPDIR/plain/inner"
  printf '## Plain\n\n- [ ] **Up.** (p1) [bug] x\n' > "$BATS_TEST_TMPDIR/plain/TODO.md"
  run lines_of "$BATS_TEST_TMPDIR/plain/inner"
  [ -z "$output" ]
  run lines_of "$BATS_TEST_TMPDIR/plain"
  [ "$output" = 'TODO.md:3 ☐  (P1) [bug] Up' ]
}

@test "paste: the lines go to a tmux buffer, the server pastes them into the pane a moment later" {
  printf '#!/usr/bin/env bash\n{ printf "%%s|" "$@"; echo; if [[ "$1" == load-buffer ]]; then command cat; fi; } >> "%s/tmux.calls"\n' \
    "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  run "$TODOS/actions.sh" paste %7 'TODO.md:8 ☐  (P1) [bug] Urgent bug' 'TODO.md:7 ☐  (P3) [chore] Low thing'
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/tmux.calls")" = "load-buffer|-b|fzx-todos|-|
TODO.md:8 ☐  (P1) [bug] Urgent bug
TODO.md:7 ☐  (P3) [chore] Low thing
run-shell|-b|-d|0.3|tmux paste-buffer -p -d -b fzx-todos -t %7|" ]
  run "$TODOS/actions.sh" paste 'x; rm -rf /' line
  [ "$status" -eq 2 ]
}
