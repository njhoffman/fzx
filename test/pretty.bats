#!/usr/bin/env bats
# lib/pretty.sh: prettypath in the files and dirs displays (a stub prettypath here)

load test_helper

setup() {
  setup_fzx
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/tree/sub"
  touch "$BATS_TEST_TMPDIR/tree/sub/a.txt"
  # stub: records its args; "path<TAB>[I] dir/name" with HOME as ~, like prettypath's %dir%%name%
  # (the probe's --format=%path% prints the path alone)
  cat > "$BATS_TEST_TMPDIR/bin/prettypath" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/pp.args"
# PP_LEGACY=1 acts like prettypath before the fixes: "%" stripped, paths right under / dropped
while IFS= read -r p; do
  if [[ -n "${PP_LEGACY:-}" ]]; then
    [[ "$p" =~ ^/[^/]*$ ]] && continue
    p="${p//%/}"
  fi
  # like prettypath: a trailing "/" marks a directory ([D], the folder icon) and is dropped from the path
  icon='[I]'
  [[ "$p" == ?*/ ]] && p="${p%/}" icon='[D]'
  if [[ "$*" == *"--format=%path%" ]]; then printf '%s\n' "$p"; else printf '%s\t%s %s\n' "$p" "$icon" "${p/#$HOME/\~}"; fi
done
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

@test "pretty: ids stay the paths; the base directory is dropped from the display; a trailing / is a directory" {
  load_libs pretty
  run fzx::pretty "$TREE" <<< "$TREE/sub/"$'\n'"$TREE/sub/a.txt"
  [ "${lines[0]}" = "$TREE/sub"$'\t'"[D] sub" ]
  [ "${lines[1]}" = "$TREE/sub/a.txt"$'\t'"[I] sub/a.txt" ]
  # --dirs: every path is a directory (zoxide lists them without the slash)
  run fzx::pretty --dirs "$TREE" <<< "$TREE/sub"
  [ "$output" = "$TREE/sub"$'\t'"[D] sub" ]
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
  [[ "${lines[0]}" == "$TREE/sub"$'\t'*"     12"*"  [D] $TREE/sub" ]]
}

@test "sound prettypath: every path goes through it, % included; the probe is cached" {
  load_libs log pretty
  run fzx::pretty "$TREE" <<< "$TREE/50%off.txt"
  [ "$output" = "$TREE/50%off.txt"$'\t'"[I] 50%off.txt" ]
  [ "$(cat "$FZX_CACHE_DIR"/prettypath/*)" = sound ]
  local calls
  calls="$(grep -c -- '--format=%path%$' "$BATS_TEST_TMPDIR/pp.args")"
  fzx::pretty "$TREE" <<< "$TREE/a" > /dev/null
  [ "$(grep -c -- '--format=%path%$' "$BATS_TEST_TMPDIR/pp.args")" -eq "$calls" ]
}

@test "legacy prettypath: paths it would mangle or drop get a plain display, ids intact" {
  load_libs log pretty
  export PP_LEGACY=1
  run fzx::pretty "$TREE" <<< "$TREE/50%off.txt"$'\n'"$TREE/sub/a.txt"$'\n'"/top"
  [ "$(cat "$FZX_CACHE_DIR"/prettypath/*)" = legacy ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *"$TREE/50%off.txt"$'\t'"  "*"50%off.txt"* ]]
  [[ "$output" == *"$TREE/sub/a.txt"$'\t'"[I] sub/a.txt"* ]]
  [[ "$output" == *"/top"$'\t'"  /top"* ]]
  grep -q 'prettypath mangles or drops some paths' "$LOG"
}

@test "dirs: a path prettypath does not return keeps a plain display" {
  load_libs log config
  source "$MODS/dirs/source.sh" || :
  mkdir -p "$BATS_TEST_TMPDIR/tree/50%"
  PP_LEGACY=1 run dirs::format <<< $'5\t'"$TREE/50%"
  [[ "${lines[0]}" == "$TREE/50%"$'\t'*"      5"*"  $TREE/50%" ]]
}
