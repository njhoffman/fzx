#!/usr/bin/env bats
# the dirs module, with zoxide and fasd stubbed

load test_helper

DIRS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/dirs")"

setup() {
  setup_fzx
  T="$BATS_TEST_TMPDIR/d"
  mkdir -p "$T/alpha" "$T/beta/deep"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # zoxide query --list --score [words]; zoxide remove <dir>
  cat > "$BATS_TEST_TMPDIR/bin/zoxide" << STUB
#!/usr/bin/env bash
echo "zoxide \$*" >> "$BATS_TEST_TMPDIR/calls"
case "\$1" in
  query) [[ "\${*: -1}" == zz ]] && exit 1; printf '%6.1f %s\n' 120.5 "$T/alpha" 40 "$T/beta/deep" 3 "$T/gone" ;;
  remove) ;;
esac
STUB
  # fasd -d -R -s | -d -t -R -l | -D
  cat > "$BATS_TEST_TMPDIR/bin/fasd" << STUB
#!/usr/bin/env bash
echo "fasd \$*" >> "$BATS_TEST_TMPDIR/calls"
case "\$*" in
  *-t*) printf '%s\n' "$T/beta/deep" "$T/alpha" ;;
  *-s*) printf '%-10s %s\n' 9.5 "$T/beta/deep" 2 "$T/alpha" ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/zoxide" "$BATS_TEST_TMPDIR/bin/fasd"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

plain() { sed 's/\x1b\[[0-9;]*m//g'; }

@test "frecent: zoxide's order and rounded scores; missing directories dropped" {
  run bash -c "'$DIRS/source.sh' | sed 's/\x1b\[[0-9;]*m//g'"
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "$T/alpha"$'\t'"    120  "*"/alpha" ]]
  [[ "${lines[1]}" == "$T/beta/deep"$'\t'"     40  "*"beta/deep" ]]
}

@test "frecent: query words go to zoxide; no match is an empty list, not an error" {
  run "$DIRS/source.sh" foo bar
  grep -q "zoxide query --list --score -- foo bar" "$BATS_TEST_TMPDIR/calls"
  run "$DIRS/source.sh" zz
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "fasd and recent modes" {
  FZX_MODE=fasd run bash -c "'$DIRS/source.sh' | cut -f1"
  [ "$output" = "$T/beta/deep"$'\n'"$T/alpha" ]
  FZX_MODE=recent run bash -c "'$DIRS/source.sh' | cut -f1"
  [ "$output" = "$T/beta/deep"$'\n'"$T/alpha" ]
  grep -q "fasd -d -t -R -l" "$BATS_TEST_TMPDIR/calls"
}

@test "bookmarks come from config, ~ expanded" {
  mkdir -p "$FZX_CONFIG_DIR/modules/dirs"
  echo "FZX_DIRS_BOOKMARKS=([b]='$T/beta' [a]='$T/alpha')" > "$FZX_CONFIG_DIR/modules/dirs/config.sh"
  FZX_MODE=bookmarks run bash -c "'$DIRS/source.sh' | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "${lines[0]}" == "$T/alpha"$'\t'*"a  "*"alpha" ]]
  [[ "${lines[1]}" == "$T/beta"$'\t'*"b  "* ]]
}

@test "modes follow what is installed and configured" {
  stub_fzf
  run "$FZX" -m dirs
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = frecent ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *"frecent"*"fasd"*"recent"* ]]
  [[ " ${FZF_ARGS[*]} " != *bookmarks* ]]
  rm "$BATS_TEST_TMPDIR/bin/zoxide"
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run "$FZX" -m dirs
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = fasd ]
}

@test "query words make a single match jump without the picker" {
  stub_fzf
  run "$FZX" -m dirs foo
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --select-1 --exit-0 "* ]]
  run "$FZX" -m dirs
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --select-1 "* ]]
}

@test "remove forgets in the mode's database; ctrl-o opens the files module" {
  FZX_MODE=frecent run "$DIRS/actions.sh" remove "$T/alpha" "$T/beta"
  FZX_MODE=fasd run "$DIRS/actions.sh" remove "$T/alpha"
  run grep -E "remove|-D" "$BATS_TEST_TMPDIR/calls"
  [ "$output" = "zoxide remove -- $T/alpha"$'\n'"zoxide remove -- $T/beta"$'\n'"fasd -D $T/alpha" ]
  stub_fzf
  run "$FZX" -m dirs
  [ "$(fzf_bind ctrl-o)" = "ctrl-o:transform:$FZX _cb nav goto files {1}" ]
}

@test "preview: git branch for work trees, then the listing; missing dir fails" {
  git -C "$T/alpha" init -q -b trunk 2> /dev/null
  run bash -c "'$DIRS/preview.sh' '$T/alpha' | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "${lines[0]}" == "git trunk  0 changes" ]]
  run "$DIRS/preview.sh" "$T/nope"
  [ "$status" -eq 1 ]
}
