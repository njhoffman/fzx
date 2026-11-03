#!/usr/bin/env bats
# the files module's listing (order, toggles, excludes, symbolic links), grep through ripgrep or grep, and
# the preview's header

load test_helper

bats_require_minimum_version 1.5.0

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
  # no rg on PATH: grep -E; it has no ignore files, so ign/ is searched too. A directory holding rg is
  # replaced by links to everything else in it (rg shares /usr/bin with bash on Debian)
  local norg="" d m n=0
  while read -r d; do
    if [[ -x "$d/rg" ]]; then
      m="$BATS_TEST_TMPDIR/norg/$((n++))"
      mkdir -p "$m"
      find "$d" -maxdepth 1 -mindepth 1 ! -name rg -exec ln -s -t "$m" {} + 2> /dev/null
      d="$m"
    fi
    norg+="$d:"
  done < <(tr : '\n' <<< "$PATH")
  run env PATH="${norg%:}" FZX_TOGGLES="" FZX_MODE=grep FZF_QUERY=NEEDLE bash -c "'$FILES/source.sh' '$B' | cut -f1,2"
  [ -z "$output" ]
  run env PATH="${norg%:}" FZX_TOGGLES="" FZX_MODE=grep FZF_QUERY=needle bash -c "'$FILES/source.sh' '$B' | cut -f1 | sed 's:^$B/::' | sort"
  [ "$output" = "$(printf '%s\n' a-b/y a/x ign/i top)" ]
}

@test "preview: a header with the path under ~ and the size, a directory's entry count, a link's target" {
  run bash -c "HOME='$BATS_TEST_TMPDIR' '$FILES/preview.sh' '$B/top' 2> /dev/null | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "${lines[0]}" = '~/.base/top  11B' ]
  run bash -c "HOME='$BATS_TEST_TMPDIR' '$FILES/preview.sh' '$B/a' 2> /dev/null | sed 's/\x1b\[[0-9;:]*m//g' | head -1"
  [ "$output" = '~/.base/a  1 entry' ]
  run bash -c "HOME='$BATS_TEST_TMPDIR' '$FILES/preview.sh' '$B/linkfile' 2> /dev/null | sed 's/\x1b\[[0-9;:]*m//g' | head -1"
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

@test "grep: the multiline toggle matches across lines, each line its own row; without it no rows" {
  command -v rg > /dev/null || skip "ripgrep not installed"
  printf 'one\nfoo bar\nbaz qux\nend\n' > "$B/multi"
  run env FZX_TOGGLES="hidden multiline" FZX_MODE=grep FZF_QUERY='bar\nbaz' "$FILES/source.sh" "$B"
  [ "$status" -eq 0 ]
  [ "$(cut -f1,2 <<< "$output" | sed "s:^$B/::" | tr '\t' ':')" = "multi:2
multi:3" ]
  # without it ripgrep refuses \n in the term, as it refuses any half-typed regex: no rows
  run --separate-stderr env FZX_TOGGLES="hidden" FZX_MODE=grep FZF_QUERY='bar\nbaz' "$FILES/source.sh" "$B"
  [ -z "$output" ]
}

@test "grep: ctrl-t filters the matches with fzf, the term frozen for reloads; again greps the term" {
  load_libs log session
  fzx::session_create files "$FILES" "$B"
  fzx::state_set mode grep
  # the options: the key in grep mode only, and a filter left from an earlier visit dropped
  fzx::state_set files_grep_filter 1
  run "$FZX" -m files:grep --dry-run "$B"
  [[ "$output" == *"ctrl-t:transform:"*"_cb transform filter"* ]]
  run "$FZX" -m files --dry-run "$B"
  [[ "$output" != *"_cb transform filter"* ]]
  fzx::state_set files_grep_filter ""
  FZF_QUERY="needle" run "$FZX" _cb transform filter
  [ "$output" = "unbind(change)+enable-search+change-query()+change-header[~${B#"$HOME"}  grep: needle  (ctrl-t greps again)]" ] ||
    [ "$output" = "unbind(change)+enable-search+change-query()+change-header[$B  grep: needle  (ctrl-t greps again)]" ]
  [ "$(cat "$FZX_SESSION_DIR/state/files_grep_term")" = needle ]
  # filtering: the source greps the frozen term, whatever fzf's query
  run bash -c "source '$FZX_REPO/lib/core.sh'; fzx::require log session; source '$FILES/source.sh'; FZX_MODE=grep FZF_QUERY=x files::source '$B' | cut -f1 | sed 's:^$B/::' | sort"
  [ "${lines[0]}" = .dot ] && [[ "$output" == *top* ]]
  FZF_QUERY="top" run "$FZX" _cb transform filter
  [[ "$output" == "rebind(change)+disable-search+change-query(needle)+change-header("*")+"*"reload("*"_cb source)" ]]
  [ -z "$(cat "$FZX_SESSION_DIR/state/files_grep_filter")" ]
  # grepping again: fzf's query is the term
  run bash -c "source '$FZX_REPO/lib/core.sh'; fzx::require log session; source '$FILES/source.sh'; FZX_MODE=grep FZF_QUERY=nomatch files::source '$B'"
  [ -z "$output" ]
  # the header position: the text goes to meta/header, which the header callback draws under the components
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_HEADER_POSITION=header' > "$FZX_CONFIG_DIR/config.sh"
  FZF_QUERY="needle" run "$FZX" _cb transform filter
  [[ "$output" == "unbind(change)+enable-search+change-query()+transform-header("*"_cb header)" ]]
  [[ "$(cat "$FZX_SESSION_DIR/meta/header")" == *"  grep: needle  (ctrl-t greps again)" ]]
  run "$FZX" _cb header
  [[ "$output" == *"grep: needle  (ctrl-t greps again)" ]]
  run "$FZX" _cb transform filter
  [[ "$(cat "$FZX_SESSION_DIR/meta/header")" != *"grep: needle"* ]]
  rm "$FZX_CONFIG_DIR/config.sh"
  # other modes: nothing
  fzx::state_set mode files
  run "$FZX" _cb transform filter
  [ -z "$output" ]
}

# trash_stub <name> <body>: a trash tool on a PATH of its own (with bash and the tools the scripts use),
# recording its args in $BATS_TEST_TMPDIR/calls
trash_path() {
  local d="$BATS_TEST_TMPDIR/tbin" t
  mkdir -p "$d"
  for t in bash dirname readlink cat; do ln -sf "$(command -v "$t")" "$d/$t"; done
  printf '%s' "$d"
}
trash_stub() {
  local d
  d="$(trash_path)"
  printf '#!%s\nprintf "%%s\\n" "${0##*/} $*" >> "%s/calls"\n' "$(command -v bash)" "$BATS_TEST_TMPDIR" > "$d/$1"
  chmod +x "$d/$1"
}

@test "trash: trash-put first, else gio trash; each path once; / and ~ refused" {
  trash_stub trash-put
  trash_stub gio
  local p
  p="$(trash_path)"
  run env PATH="$p" "$FILES/actions.sh" trash "$B/top" "$B/a" "$B/top"
  [ "$status" -eq 0 ]
  rm "$p/trash-put"
  FZX_MODE=grep run env PATH="$p" "$FILES/actions.sh" trash "$B/top"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "$(printf '%s\n' "trash-put -- $B/top $B/a" "gio trash -- $B/top")" ]
  run --separate-stderr env PATH="$p" "$FILES/actions.sh" trash "$B/top" "$HOME/"
  [ "$status" -eq 2 ]
  [ "$stderr" = "files: trash: refusing $HOME/" ]
  run env PATH="$p" "$FILES/actions.sh" trash /
  [ "$status" -eq 2 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/calls")" -eq 2 ]
  rm "$p/gio"
  run --separate-stderr env PATH="$p" "$FILES/actions.sh" trash "$B/top"
  [ "$status" -eq 1 ]
  [ "$stderr" = "files: trash: neither trash-put nor gio is installed" ]
}

@test "trash: offered only with trash-put or gio; alt-x confirms, then reloads; grep passes every match's file" {
  local p
  p="$(trash_path)"
  run env PATH="$p" "$FILES/components.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" != *trash* && "$output" == *"action  edit"* ]]
  trash_stub gio
  run env PATH="$p" "$FILES/components.tsv"
  [[ "${lines[-1]}" == $'action\ttrash\talt-x\t'*$'\tconfirm,reload' ]]
  command -v trash-put > /dev/null || command -v gio > /dev/null || skip "no trash tool installed"
  stub_fzf
  run "$FZX" -m files "$B"
  [[ "$(fzf_bind alt-x)" == "alt-x:execute($FZX _cb action trash {+1})+change-prompt("*")+reload($FZX _cb source)" ]]
  command -v rg > /dev/null || skip "rg not installed"
  run "$FZX" -m files:grep "$B"
  [[ "$(fzf_bind alt-x)" == "alt-x:execute($FZX _cb action trash {+1})+"* ]]
}
