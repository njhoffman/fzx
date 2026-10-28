#!/usr/bin/env bats
# the recent module (telescope-frecency's database, fasd) and fzx jump --files (v)

load test_helper

RECENT="$(readlink -f "$BATS_TEST_DIRNAME/../modules/recent")"

setup() {
  command -v sqlite3 > /dev/null || skip "sqlite3 not installed"
  setup_fzx
  stub_fzf
  T="$(mkdir -p "$BATS_TEST_TMPDIR/f" && cd "$BATS_TEST_TMPDIR/f" && pwd -P)"
  mkdir -p "$T/proj/docs"
  touch "$T/proj/docs/a.md" "$T/proj/docs/b.md" "$T/proj/old.md" "$T/other.txt"
  # telescope-frecency's schema; timestamps are Julian days. a.md: opened twice in the last hours (high),
  # b.md: once 2 days ago, old.md: once 200 days ago (score 0), gone.md: no longer exists
  export FZX_RECENT_NVIM_DB="$BATS_TEST_TMPDIR/frecency.sqlite3"
  sqlite3 "$FZX_RECENT_NVIM_DB" "
    CREATE TABLE files(count INTEGER, id INTEGER PRIMARY KEY, path TEXT);
    CREATE TABLE timestamps(file_id INTEGER, id INTEGER PRIMARY KEY, timestamp REAL);
    INSERT INTO files VALUES (2, 1, '$T/proj/docs/a.md'), (1, 2, '$T/proj/docs/b.md'), (1, 3, '$T/proj/old.md'),
      (5, 4, '$T/gone.md'), (1, 5, '$T/other.txt');
    INSERT INTO timestamps (file_id, timestamp) VALUES (1, julianday('now') - 0.05), (1, julianday('now') - 0.1),
      (2, julianday('now') - 2), (3, julianday('now') - 200), (4, julianday('now')), (5, julianday('now') - 20);"
  cat > "$BATS_TEST_TMPDIR/bin/fasd" << STUB
#!/usr/bin/env bash
echo "fasd \$*" >> "$BATS_TEST_TMPDIR/calls"
printf '%-10s %s\n' 9.5 "$T/other.txt" 2 "$T/proj/old.md"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/fasd"
  cd "$T"
}

@test "nvim mode: telescope-frecency's score order, missing files dropped; it is the default" {
  run bash -c "'$RECENT/source.sh' | cut -f1"
  [ "$output" = "$T/proj/docs/a.md"$'\n'"$T/proj/docs/b.md"$'\n'"$T/other.txt"$'\n'"$T/proj/old.md" ]
  # sed 1!d reads it all: head would close the pipe early, and where SIGPIPE is ignored (GitHub's
  # runners) the source's printf reports the broken pipe on stderr
  run bash -c "'$RECENT/source.sh' | sed '1!d' | cut -f2 | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "$output" == "  200  "*"a.md" ]]
  run "$FZX" -m recent
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = nvim ]
}

@test "sort: the ranking (score underlined) or by path (path underlined)" {
  run bash -c "'$RECENT/source.sh' | sed '1!d' | cut -f2"
  [[ "$output" == *$'\e[4m200\e[0m'* ]]
  run bash -c "FZX_SORT=path '$RECENT/source.sh' | cut -f1"
  [ "$output" = "$T/other.txt"$'\n'"$T/proj/docs/a.md"$'\n'"$T/proj/docs/b.md"$'\n'"$T/proj/old.md" ]
  run bash -c "FZX_SORT=path '$RECENT/source.sh' | sed '1!d' | cut -f2"
  [[ "$output" == *$'\e[4m'*other.txt* && "$output" != *$'\e[4m'[0-9]* ]]
}

@test "words: each one, in order, anywhere in the path, ignoring case" {
  run bash -c "'$RECENT/source.sh' PROJ md | cut -f1"
  [ "$output" = "$T/proj/docs/a.md"$'\n'"$T/proj/docs/b.md"$'\n'"$T/proj/old.md" ]
  run bash -c "'$RECENT/source.sh' docs proj | cut -f1"
  [ -z "$output" ]
}

@test "fasd mode; without the database fasd is the default" {
  FZX_MODE=fasd run bash -c "'$RECENT/source.sh' | cut -f1"
  [ "$output" = "$T/other.txt"$'\n'"$T/proj/old.md" ]
  FZX_RECENT_NVIM_DB=/nonexistent run "$FZX" -m recent
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = fasd ]
}

@test "v: up to FZX_RECENT_JUMP_MAX matches are all printed, best first" {
  run "$FZX" jump --files docs
  [ "$output" = "$T/proj/docs/a.md"$'\n'"$T/proj/docs/b.md" ]
  [ ! -f "$BATS_TEST_TMPDIR/fzf.args" ]
}

@test "v: more than FZX_RECENT_JUMP_MAX opens the picker over them" {
  mkdir -p "$FZX_CONFIG_DIR/modules/recent"
  echo 'FZX_RECENT_JUMP_MAX=1' > "$FZX_CONFIG_DIR/modules/recent/config.sh"
  STUB_FZF_OUT="$T/proj/docs/b.md" run "$FZX" jump --files docs
  [ "$output" = "$T/proj/docs/b.md" ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = nvim ]
}

@test "v: a path given as is; no words or no match open pickers" {
  run "$FZX" jump --files proj/old.md
  [ "$output" = proj/old.md ]
  STUB_FZF_OUT="$T/other.txt" run "$FZX" jump --files
  [ "$output" = "$T/other.txt" ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = nvim ]
  STUB_FZF_OUT="$T/x" run "$FZX" jump --files nothing matches
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = files ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --query=nothing matches "* ]]
}

@test "--query starts any module with the query typed" {
  run "$FZX" -m counter --query "a b"
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --query=a b "* ]]
}

@test "zsh: v lists the files and opens them all in \$EDITOR" {
  command -v zsh > /dev/null || skip "zsh not installed"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/editor.args"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/ed"
  chmod +x "$BATS_TEST_TMPDIR/bin/ed"
  local zint
  zint="$(readlink -f "$BATS_TEST_DIRNAME/../shell/fzx.zsh")"
  run script -qec "zsh -f -i -c \"EDITOR=ed FZX_ZSH_BIN='$FZX'; source '$zint'; v docs\"" /dev/null
  [[ "$output" == *"(2 file(s) to edit)"* ]]
  [ "$(< "$BATS_TEST_TMPDIR/editor.args")" = "--"$'\n'"$T/proj/docs/a.md"$'\n'"$T/proj/docs/b.md" ]
}
