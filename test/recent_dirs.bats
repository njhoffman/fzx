#!/usr/bin/env bats
# the recent module's directory modes (zoxide, fasd), with zoxide and fasd stubbed

load test_helper

RECENT="$(readlink -f "$BATS_TEST_DIRNAME/../modules/recent")"

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
  # a real z.lua on this machine would add the zlua mode; test/jump.bats stubs one
  export FZX_RECENT_ZLUA=none FZX_RECENT_NVIM_DB=/nonexistent
}

src() { FZX_MODE="$1" "$RECENT/source.sh" "${@:2}"; }

@test "dirs: zoxide's order and rounded scores; missing directories dropped" {
  run bash -c "FZX_MODE=dirs '$RECENT/source.sh' | sed 's/\x1b\[[0-9;]*m//g'"
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "$T/alpha"$'\t'"    120  "*"/alpha" ]]
  [[ "${lines[1]}" == "$T/beta/deep"$'\t'"     40  "*"beta/deep" ]]
}

@test "dirs: words go to zoxide; no match is an empty list, not an error" {
  run src dirs foo bar
  grep -q "zoxide query --list --score -- foo bar" "$BATS_TEST_TMPDIR/calls"
  run src dirs zz
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "fasd-dirs and visited modes" {
  run bash -c "FZX_MODE=fasd-dirs '$RECENT/source.sh' | cut -f1"
  [ "$output" = "$T/beta/deep"$'\n'"$T/alpha" ]
  run bash -c "FZX_MODE=visited '$RECENT/source.sh' | cut -f1"
  [ "$output" = "$T/beta/deep"$'\n'"$T/alpha" ]
  grep -q "fasd -d -t -R -l" "$BATS_TEST_TMPDIR/calls"
}

@test "modes: files first, then the directory trackers that are installed" {
  stub_fzf
  run "$FZX" -m recent
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = fasd ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *"fasd"*"dirs"*"fasd-dirs"*"visited"* ]]
  rm "$BATS_TEST_TMPDIR/bin/fasd"
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run "$FZX" -m recent
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = dirs ]
}

@test "remove forgets in the mode's database; ctrl-o opens the files module" {
  FZX_MODE=dirs run "$RECENT/actions.sh" remove "$T/alpha" "$T/beta"
  FZX_MODE=visited run "$RECENT/actions.sh" remove "$T/alpha"
  run grep -E "remove|-D" "$BATS_TEST_TMPDIR/calls"
  [ "$output" = "zoxide remove -- $T/alpha"$'\n'"zoxide remove -- $T/beta"$'\n'"fasd -D $T/alpha" ]
  FZX_MODE=nvim run "$RECENT/actions.sh" remove "$T/alpha"
  [[ "$output" == *"telescope-frecency keeps its own database"* ]]
  stub_fzf
  run "$FZX" -m recent:dirs
  [ "$(fzf_bind ctrl-o)" = "ctrl-o:transform:$FZX _cb nav goto files {1}" ]
}

@test "preview: git branch for work trees, then the path header and the listing" {
  git -C "$T/alpha" init -q -b trunk 2> /dev/null
  run bash -c "'$RECENT/preview.sh' '$T/alpha' 2> /dev/null | sed 's/\x1b\[[0-9;]*m//g'"
  [ "${lines[0]}" = "git trunk  0 changes" ]
  [[ "${lines[1]}" == *"/alpha  "*"entr"* ]]
  run "$RECENT/preview.sh" "$T/nope"
  [ "$status" -eq 1 ]
}

@test "menu: the trackers are recent's entries, not dirs'" {
  run bash -c "'$BATS_TEST_DIRNAME/../modules/menu/source.sh' 2> /dev/null | cut -f2 | sed 's/\x1b\[[0-9;]*m//g'"
  [[ "$output" == *"recent:dirs "*"Frecent directories (zoxide)"* && "$output" == *"recent:visited "* ]]
  [[ "$output" != *"dirs:recent"* ]]
}
