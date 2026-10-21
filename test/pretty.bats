#!/usr/bin/env bats
# lib/pretty.sh: prettypath in the files and dirs displays (a stub prettypath here)

load test_helper

setup() {
  setup_fzx
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/tree/sub"
  touch "$BATS_TEST_TMPDIR/tree/sub/a.txt"
  # stub: records its args; "path<TAB>[I] dir/name" with HOME as ~, like prettypath's %dir%%name%
  cat > "$BATS_TEST_TMPDIR/bin/prettypath" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$BATS_TEST_TMPDIR/pp.args"
while IFS= read -r p; do printf '%s\t[I] %s\n' "$p" "${p/#$HOME/\~}"; done
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/prettypath"
  export FZX_PRETTY=auto
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  TREE="$(cd "$BATS_TEST_TMPDIR/tree" && pwd -P)"
  MODS="$FZX_REPO/modules"
}

@test "pretty_on: auto follows whether prettypath is installed; 0 turns it off" {
  load_libs pretty
  FZX_PRETTY=auto fzx::pretty_on
  ! FZX_PRETTY=0 fzx::pretty_on
  rm "$BATS_TEST_TMPDIR/bin/prettypath"
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" FZX_PRETTY=auto run fzx::pretty_on
  [ "$status" -eq 1 ]
}

@test "pretty: ids stay the paths; the base directory is dropped from the display; trailing / removed" {
  load_libs pretty
  run fzx::pretty "$TREE" <<< "$TREE/sub/"
  [ "$output" = "$TREE/sub"$'\t'"[I] sub" ]
  grep -q -- "--stat_file=false" "$BATS_TEST_TMPDIR/pp.args"
}

@test "files: the listing goes through prettypath unless FZX_PRETTY=0" {
  command -v fd > /dev/null || command -v fdfind > /dev/null || skip "fd not installed"
  FZX_MODE=files run "$MODS/files/source.sh" "$TREE"
  [ "$output" = "$TREE/sub/a.txt"$'\t'"[I] sub/a.txt" ]
  FZX_PRETTY=0 FZX_MODE=files run "$MODS/files/source.sh" "$TREE"
  [[ "$output" == "$TREE/sub/a.txt"$'\t'*"sub/"*"a.txt" && "$output" != *"[I]"* ]]
}

@test "dirs: scores kept, joined back by path, missing directories dropped" {
  load_libs log config
  # the script's run-directly guard is false when sourced
  source "$MODS/dirs/source.sh" || :
  run dirs::format <<< $'12\t'"$TREE/sub"$'\n3\t/nonexistent/dir'
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "$TREE/sub"$'\t'*"     12"*"  [I] $TREE/sub" ]]
}
