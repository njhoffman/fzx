#!/usr/bin/env bats
# the files module's listing (order, toggles, excludes, symbolic links), grep through ripgrep or grep, and
# the preview's header

load test_helper

FILES="$(readlink -f "$BATS_TEST_DIRNAME/../modules/files")"

setup() {
  setup_fzx
  command -v fd > /dev/null || command -v fdfind > /dev/null || skip "fd not installed"
  export FZX_PRETTY=0
  B="$BATS_TEST_TMPDIR/.base"
  mkdir -p "$B/a" "$B/a-b" "$B/.hid" "$B/.ruff_cache" "$B/ign" "$BATS_TEST_TMPDIR/elsewhere/deep"
  git init -q "$B"
  printf 'ign/\n' > "$B/.gitignore"
  for f in a/x a-b/y .hid/z .ruff_cache/c ign/i top .dot; do printf 'needle %s\n' "$f" > "$B/$f"; done
  printf 'needle far\n' > "$BATS_TEST_TMPDIR/elsewhere/deep/far"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$B/linkdir"
  ln -s "$B/top" "$B/linkfile"
  ln -s "$B/gone" "$B/broken"
  touch -d '2026-01-01' "$B/a/x"
  touch -d '2026-06-01' "$B/top"
}

# the listed paths relative to the base
rel() { (FZX_MODE="$1" "$FILES/source.sh" "$B") | cut -f1 | sed "s:^$B/::"; }

@test "files: sorted by path component by component; hidden on at start; caches and ignored files left out" {
  run rel files
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' .dot .gitignore .hid/z a/x a-b/y linkfile top)" ]
}

@test "toggles: hidden off drops dotfiles, ignored on adds what .gitignore excludes" {
  FZX_TOGGLES="" run rel files
  [ "$output" = "$(printf '%s\n' a/x a-b/y linkfile top)" ]
  FZX_TOGGLES="hidden ignored" run rel files
  [[ "$output" == *ign/i* && "$output" != *.ruff_cache* ]]
}

@test "symbolic links: listed by target kind, broken ones dropped, entered only with follow" {
  run rel dirs
  [ "$output" = "$(printf '%s\n' .hid a a-b linkdir)" ]
  FZX_TOGGLES="hidden follow" run rel dirs
  [[ "$output" == *linkdir/deep* ]]
  FZX_TOGGLES="hidden follow" run rel files
  [[ "$output" == *linkdir/deep/far* && "$output" != *broken* ]]
}

@test "recent sort: newest modification first" {
  touch -d '2026-12-01' "$B/a-b/y"
  FZX_SORT=recent FZX_TOGGLES="" run rel files
  [ "${lines[0]}" = a-b/y ]
  [ "${lines[$((${#lines[@]} - 1))]}" = a/x ]
}

@test "grep: ripgrep, else grep, with the same toggles; a dot-named base works without ripgrep" {
  command -v rg > /dev/null || skip "rg not installed"
  local want
  want="$(printf '%s\n' .dot .gitignore .hid/z a-b/y a/x top)"
  run bash -c "FZX_MODE=grep FZF_QUERY=needle '$FILES/source.sh' '$B' | cut -f1 | sed 's:^$B/::' | sort"
  [ "$output" = "$(sort <<< "${want/.gitignore$'\n'/}")" ]
  # no rg on PATH: grep -E; it has no ignore files, so ign/ is searched too
  local norg
  norg="$(tr : '\n' <<< "$PATH" | while read -r d; do [[ -x "$d/rg" ]] || printf '%s:' "$d"; done)"
  run env PATH="${norg%:}" FZX_TOGGLES="" FZX_MODE=grep FZF_QUERY=NEEDLE bash -c "'$FILES/source.sh' '$B' | cut -f1,2"
  [ -z "$output" ]
  run env PATH="${norg%:}" FZX_TOGGLES="" FZX_MODE=grep FZF_QUERY=needle bash -c "'$FILES/source.sh' '$B' | cut -f1 | sed 's:^$B/::' | sort"
  [ "$output" = "$(printf '%s\n' a-b/y a/x ign/i top)" ]
}

@test "preview: a header with the path under ~ and the size, a directory's entry count, a link's target" {
  run bash -c "HOME='$BATS_TEST_TMPDIR' '$FILES/preview.sh' '$B/top' 2> /dev/null | sed 's/\x1b\[[0-9;]*m//g'"
  [ "${lines[0]}" = '~/.base/top  11B' ]
  run bash -c "HOME='$BATS_TEST_TMPDIR' '$FILES/preview.sh' '$B/a' 2> /dev/null | sed 's/\x1b\[[0-9;]*m//g' | head -1"
  [ "$output" = '~/.base/a  1 entry' ]
  run bash -c "HOME='$BATS_TEST_TMPDIR' '$FILES/preview.sh' '$B/linkfile' 2> /dev/null | sed 's/\x1b\[[0-9;]*m//g' | head -1"
  [ "$output" = "~/.base/linkfile  11B  -> $B/top" ]
}

@test "preview: images go through chafa in the configured format" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "chafa %%s\\n" "$*"\n' > "$BATS_TEST_TMPDIR/bin/chafa"
  chmod +x "$BATS_TEST_TMPDIR/bin/chafa"
  printf 'x' > "$B/pic.PNG"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" FZF_PREVIEW_COLUMNS=40 FZF_PREVIEW_LINES=20 FZX_FILES_IMAGE_FORMAT=sixels \
    "$FILES/preview.sh" "$B/pic.PNG"
  [ "${lines[1]}" = "chafa --format=sixels --size=40x19 --animate=off -- $B/pic.PNG" ]
}

@test "under fzx: toggle keys and the sort are bound" {
  stub_fzf
  run "$FZX" -m files "$B"
  [ "$status" -eq 0 ]
  [[ "$(fzf_bind alt-h)" == *'_cb toggle hidden'* ]]
  [[ "$(fzf_bind alt-i)" == *'_cb toggle ignored'* ]]
  [[ "$(fzf_bind alt-l)" == *'_cb toggle follow'* ]]
}
