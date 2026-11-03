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

@test "locate: plocate's paths under the directory, every word; hidden, excluded and gone ones left out; everywhere" {
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  # plocate: its words logged, the database a fixed list (the gone path is in it but not on disk)
  cat > "$BATS_TEST_TMPDIR/stub/plocate" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/plocate.calls"
printf '%s\n' "$B/a/x" "$B/.hid/z" "$B/.ruff_cache/c" "$B/gone" "$B/top" "$BATS_TEST_TMPDIR/elsewhere/deep/far" "$B-sibling/x"
STUB
  chmod +x "$BATS_TEST_TMPDIR/stub/plocate"
  export PATH="$BATS_TEST_TMPDIR/stub:$PATH"
  run env FZX_TOGGLES="" FZX_MODE=locate FZF_QUERY="x  far" "$FILES/source.sh" "$B"
  [ "$status" -eq 0 ]
  [ "$(cut -f1 <<< "$output" | sed "s:^$B/::" | tr '\n' ' ')" = "a/x top " ]
  # every word, then the base, case-insensitive
  [ "$(< "$BATS_TEST_TMPDIR/plocate.calls")" = "-i -- x far $B/" ]
  run env FZX_TOGGLES="hidden" FZX_MODE=locate FZF_QUERY=x "$FILES/source.sh" "$B"
  [ "$(cut -f1 <<< "$output" | sed "s:^$B/::" | tr '\n' ' ')" = ".hid/z a/x top " ]
  # everywhere: outside the base too (a home path shown under ~ when it is one)
  run env FZX_TOGGLES="everywhere" FZX_MODE=locate FZF_QUERY=x "$FILES/source.sh" "$B"
  [[ "$(cut -f1 <<< "$output" | tr '\n' ' ')" == *"$BATS_TEST_TMPDIR/elsewhere/deep/far "* ]]
  [[ "$(tail -1 "$BATS_TEST_TMPDIR/plocate.calls")" == "-i -- x" ]]
  # no query: nothing asked
  run env FZX_MODE=locate FZF_QUERY="" "$FILES/source.sh" "$B"
  [ -z "$output" ]
  FZX_FILES_LOCATE_LIMIT=1 run env FZX_TOGGLES="" FZX_MODE=locate FZF_QUERY=x "$FILES/source.sh" "$B"
  [ "${#lines[@]}" -eq 1 ]
}

@test "locate: listed only with plocate or locate; typing asks the database; the header says how old it is" {
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/stub/plocate"
  chmod +x "$BATS_TEST_TMPDIR/stub/plocate"
  touch -d '-3 hours' "$BATS_TEST_TMPDIR/db"
  PATH="$BATS_TEST_TMPDIR/stub:$PATH" FZX_FILES_LOCATE_DB="$BATS_TEST_TMPDIR/db" run "$FZX" -m files:locate --dry-run "$B"
  [[ "$output" == *"--disabled"* && "$output" == *"change:reload:sleep 0.1; "*"_cb source"* ]]
  [[ "$output" == *"locate (database 3h old: updatedb refreshes it)"* ]]
  # the menu: listed where locate is; the summary is the database's age
  load_libs log config menu
  PATH="$BATS_TEST_TMPDIR/stub:$PATH" fzx::menu_entries files "$FILES"
  PATH="$BATS_TEST_TMPDIR/stub:$PATH" files::applicable files:locate
  [ "$(PATH="$BATS_TEST_TMPDIR/stub:$PATH" FZX_FILES_LOCATE_DB="$BATS_TEST_TMPDIR/db" files::summary files:locate)" = "database 3h old" ]
  # a PATH with cat alone (/bin is /usr/bin on merged systems)
  mkdir -p "$BATS_TEST_TMPDIR/onlycat"
  ln -s "$(command -v cat)" "$BATS_TEST_TMPDIR/onlycat/cat"
  run env PATH="$BATS_TEST_TMPDIR/onlycat" "$BASH" "$FILES/components.tsv"
  [[ "$output" == *"mode  grep"* && "$output" != *locate* && "$output" != *everywhere* ]]
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

# a replace session over $B for the term (its arguments as alt-s makes them)
replace_session() {
  load_libs log session
  fzx::session_create files "$FILES" "$B" --term "$1"
  fzx::state_set mode replace
  export FZX_MODE=replace
}

@test "replace: rows show each match as the replacement leaves it; capture groups; no query: the matches as they are" {
  command -v rg > /dev/null || skip "ripgrep not installed"
  export NO_COLOR=1
  run env FZX_TOGGLES="" FZX_MODE=replace FZF_QUERY='pin' "$FILES/source.sh" "$B" --term needle
  [ "$status" -eq 0 ]
  [ "$(cut -f1,2 <<< "$output" | sed "s:^$B/::" | sort | tr '\t' ':' | tr '\n' ' ')" = "a-b/y:1 a/x:1 top:1 " ]
  [[ "$output" == *$'\ta/x:1: pin a/x'* ]]
  run env FZX_TOGGLES="" FZX_MODE=replace FZF_QUERY='<$1>' "$FILES/source.sh" "$B" --term 'need(le)'
  [[ "$output" == *$'\ttop:1: <le> top'* ]]
  run env FZX_TOGGLES="" FZX_MODE=replace FZF_QUERY= "$FILES/source.sh" "$B" --term needle
  [[ "$output" == *$'\ttop:1: needle top'* ]]
  run env FZX_MODE=replace "$FILES/source.sh" "$B"
  [ "$status" -eq 2 ]
}

@test "replace: the preview shows the line before and after, with context; an empty replacement says it deletes" {
  command -v rg > /dev/null || skip "ripgrep not installed"
  export NO_COLOR=1
  printf 'one\ntwo needle\nthree\n' > "$B/ctx"
  replace_session needle
  run "$FZX" _cb preview "$B/ctx" 2 pin
  [[ "$output" == *"    1   one"* && "$output" == *"    2 - two needle"* && "$output" == *"      + two pin"* && "$output" == *"    3   three"* ]]
  run "$FZX" _cb preview "$B/ctx" 2 ""
  [[ "$output" == *"the replacement is empty"* && "$output" == *"      + two "* ]]
}

@test "replace: apply asks, then changes only the selected lines (every match when none is selected), keeping mode and a missing last newline; undo puts them back" {
  command -v rg > /dev/null || skip "ripgrep not installed"
  printf 'needle 1\nkeep\nneedle 2\n' > "$B/m"
  printf 'needle end' > "$B/nonl"
  chmod 750 "$B/m"
  replace_session needle
  export FZX_TOGGLES="" FZX_TTY="$BATS_TEST_TMPDIR/tty"
  # the selected match only: line 3 of m
  printf 'y' > "$FZX_TTY"
  FZF_SELECT_COUNT=1 run "$FZX" _cb action apply pin "$B/m" -- 3
  [ "$status" -eq 0 ]
  [ "$(< "$B/m")" = $'needle 1\nkeep\npin 2' ]
  [ "$(stat -c %a "$B/m")" = 750 ]
  # nothing selected: every match; a no at the question changes nothing
  printf 'n' > "$FZX_TTY"
  FZF_SELECT_COUNT=0 run "$FZX" _cb action apply pin x -- 1
  [ "$(< "$B/top")" = "needle top" ]
  printf 'y' > "$FZX_TTY"
  FZF_SELECT_COUNT=0 run "$FZX" _cb action apply 'P$0' x -- 1
  [ "$(< "$B/top")" = "Pneedle top" ]
  [ "$(< "$B/m")" = $'Pneedle 1\nkeep\npin 2' ]
  [ "$(head -c 50 "$B/nonl" | od -c | head -1)" = "$(printf 'Pneedle end' | od -c | head -1)" ]
  [[ "$output" == *"replaced "*" lines in "*" files"* ]]
  # undo: the last replacement's files back; then the one before
  printf 'yy' > "$FZX_TTY"
  run "$FZX" _cb action undo
  [ "$(< "$B/top")" = "needle top" ]
  [ "$(< "$B/m")" = $'needle 1\nkeep\npin 2' ]
  [ "$(cat "$B/nonl")" = "needle end" ]
  run "$FZX" _cb action undo
  [ "$(< "$B/m")" = $'needle 1\nkeep\nneedle 2' ]
  run "$FZX" _cb action undo
  [[ "$output" == *"no replacement to undo"* ]]
}

@test "replace: undo leaves a file changed since alone; apply is refused outside the replace screen" {
  command -v rg > /dev/null || skip "ripgrep not installed"
  replace_session needle
  export FZX_TOGGLES="" FZX_TTY="$BATS_TEST_TMPDIR/tty"
  printf 'y' > "$FZX_TTY"
  FZF_SELECT_COUNT=0 run "$FZX" _cb action apply pin x -- 1
  echo edited >> "$B/top"
  printf 'y' > "$FZX_TTY"
  run "$FZX" _cb action undo
  [[ "$output" == *"top changed since the replacement: left as it is"* && "$output" == *"put back 2 files, 1 changed since and left alone"* ]]
  [ "$(< "$B/a/x")" = "needle a/x" ]
  [ "$(head -1 "$B/top")" = "pin top" ]
  fzx::state_set mode files
  run env FZX_MODE=files "$FZX" _cb action apply pin x -- 1
  [ "$status" -eq 2 ]
}

@test "replace: alt-s in grep opens the replace screen for the query (or the frozen term) as a child; enter applies there" {
  command -v rg > /dev/null || skip "ripgrep not installed"
  load_libs log session
  fzx::session_create files "$FILES" "$B"
  fzx::state_set mode grep
  FZX_MODE=grep FZF_QUERY=needle run "$FZX" _cb transform replace
  [[ "$output" == "become:$FZX --resume "*" -m :replace" ]]
  local child="${output##*--resume }" args=()
  child="${child%% *}"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${args[*]}" = "$B --term needle" ]
  FZX_MODE=grep FZF_QUERY= run "$FZX" _cb transform replace
  [ "$output" = bell ]
  stub_fzf
  run "$FZX" -m files:grep "$B"
  [[ "$(fzf_bind alt-s)" == "alt-s:transform:$FZX _cb transform replace" ]]
  FZX_SESSION="" run "$FZX" -m files:replace "$B" --term needle
  [[ "$(fzf_bind enter)" == "enter:execute($FZX _cb action apply {q} {+1} -- {+2})+transform("*"nav restart)" ]]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --disabled "* && " ${FZF_ARGS[*]} " == *"replace: needle  (type the replacement"* ]]
}
