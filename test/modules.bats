#!/usr/bin/env bats
# the files module, and the menu entries of the step-6 modules (logs and systemd: test/logs.bats, test/systemd.bats)

load test_helper

bats_require_minimum_version 1.5.0

MODS="$(readlink -f "$BATS_TEST_DIRNAME/../modules")"

setup() {
  setup_fzx
  TREE="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$TREE/src/deep" "$TREE/docs" "$TREE/.git"
  printf 'alpha\nneedle here\n' > "$TREE/src/a.txt"
  printf 'needle again\n' > "$TREE/src/deep/b.txt"
  printf 'nothing\n' > "$TREE/docs/c.md"
  printf 'needle in git\n' > "$TREE/.git/HEAD"
}

# stub_cmd <name> <body>: an executable on PATH that runs <body> with its args in "$@"
stub_cmd() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0 $*" >> "$BATS_TEST_TMPDIR/calls"\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

plain() { sed 's/\x1b\[[0-9;:]*m//g'; }

need() { command -v "$1" > /dev/null || skip "$1 not installed"; }

# ---- files

@test "files: lists files with absolute path and relative display, skipping .git" {
  need fd
  run --separate-stderr "$MODS/files/source.sh" "$TREE"
  [ "$status" -eq 0 ]
  local real
  real="$(cd "$TREE" && pwd -P)"
  [ "$(printf '%s\n' "${lines[@]}" | plain | sort)" = "$(printf '%s\t%s\n' "$real/docs/c.md" docs/c.md "$real/src/a.txt" src/a.txt "$real/src/deep/b.txt" src/deep/b.txt)" ]
}

@test "files: dirs mode lists directories" {
  need fd
  FZX_MODE=dirs run "$MODS/files/source.sh" "$TREE"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f2 | plain | sort | tr '\n' ' ')" = "docs src src/deep " ]
}

@test "files: a symlinked or file argument resolves to the real directory" {
  need fd
  ln -s "$TREE" "$BATS_TEST_TMPDIR/link"
  run "$MODS/files/source.sh" "$BATS_TEST_TMPDIR/link/src/a.txt"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f2 | plain | sort | tr '\n' ' ')" = "a.txt deep/b.txt " ]
  cd "$TREE/src"
  run "$MODS/files/source.sh" a.txt
  [ "${#lines[@]}" -eq 2 ]
}

@test "files: bad arguments fail with 2" {
  run "$MODS/files/source.sh" /no/such/dir
  [ "$status" -eq 2 ]
  run "$MODS/files/source.sh" a b
  [ "$status" -eq 2 ]
  FZX_MODE=nine run "$MODS/files/source.sh" "$TREE"
  [ "$status" -eq 2 ]
}

@test "files: grep searches FZF_QUERY; empty query or no match is an empty list" {
  need rg
  FZX_MODE=grep FZF_QUERY=needle run "$MODS/files/source.sh" "$TREE"
  [ "$status" -eq 0 ]
  local real
  real="$(cd "$TREE" && pwd -P)"
  [ "$(printf '%s\n' "${lines[@]}" | plain | sort)" = "$(printf '%s\t2\tsrc/a.txt:2: needle here\n%s\t1\tsrc/deep/b.txt:1: needle again' "$real/src/a.txt" "$real/src/deep/b.txt")" ]
  FZX_MODE=grep FZF_QUERY= run "$MODS/files/source.sh" "$TREE"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  FZX_MODE=grep FZF_QUERY=zzzz run "$MODS/files/source.sh" "$TREE"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "files: preview shows files, directories, and a grep hit's line" {
  run "$MODS/files/preview.sh" "$TREE/src/a.txt"
  [[ "$(printf '%s' "$output" | plain)" == *"needle here"* ]]
  run "$MODS/files/preview.sh" "$TREE/src"
  [[ "$(printf '%s' "$output" | plain)" == *a.txt* ]]
  run "$MODS/files/preview.sh" "$TREE/nope"
  [ "$status" -eq 1 ]
}

@test "files: opts per mode; grep searches as you type and restarts on mode change" {
  stub_fzf
  cd "$TREE"
  run "$FZX" -m files
  [ "$(fzf_bind ctrl-e)" = "ctrl-e:execute($FZX _cb action edit {+1})" ]
  [ "$(fzf_bind alt-up)" = "alt-up:transform:$FZX _cb nav goto --ancestor files:files $(cd "$BATS_TEST_TMPDIR" && pwd -P)" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=1 "* && " ${FZF_ARGS[*]} " == *" --scheme=path "* ]]
  run "$FZX" -m files:grep
  [ "$(fzf_bind ctrl-e)" = "ctrl-e:execute($FZX _cb action edit {1} {2})" ]
  [ "$(fzf_bind change)" = "change:reload:sleep 0.1; $FZX _cb search" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --disabled "* && " ${FZF_ARGS[*]} " == *" --accept-nth={1}:{2} "* ]]
  load_libs log session
  fzx::session_create files "$MODS/files"
  printf '%s\0' files dirs grep > "$FZX_SESSION_DIR/meta/modes"
  run "$FZX" _cb mode next
  [[ "$output" == change-border-label* ]]
  run "$FZX" _cb mode next
  [[ "$output" == "become:"*"-m :grep" ]]
}

@test "files: action keys come from the table and can be rebound" {
  stub_fzf
  mkdir -p "$FZX_CONFIG_DIR/modules/files"
  echo 'action  edit  f4  =  =' > "$FZX_CONFIG_DIR/modules/files/components.tsv"
  cd "$TREE"
  run "$FZX" -m files
  [ "$(fzf_bind f4)" = "f4:execute($FZX _cb action edit {+1})" ]
  run fzf_bind ctrl-e
  [ "$status" -eq 1 ]
}

@test "files: edit opens \$EDITOR, at the line in grep mode" {
  EDITOR="echo" run "$MODS/files/actions.sh" edit a b
  [ "$output" = "-- a b" ]
  FZX_MODE=grep EDITOR="echo" run "$MODS/files/actions.sh" edit a 12
  [ "$output" = "+12 -- a" ]
  run "$MODS/files/actions.sh" bogus
  [ "$status" -eq 2 ]
}

# ---- manifests

@test "menu: entries from the new modules apply on this machine" {
  # what applies, not how fast: under the parallel suite a manifest can pass the 2s menu timeout
  export FZX_APPLICABLE_TIMEOUT=20
  load_libs log session menu
  fzx::session_create menu "$MODS/menu"
  run "$FZX" _cb source
  local ids
  ids="$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')"
  [[ "$ids" == *"logs#0 "* && "$ids" == *"ps#0 "* ]]
  if command -v fd > /dev/null; then [[ "$ids" == *"files#0 "* ]]; fi
}

