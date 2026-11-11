#!/usr/bin/env bats
# lib/pretty.sh: prettypath in the files and dirs displays (a stub prettypath here; the "real prettypath"
# tests use the installed one)

load test_helper

setup() {
  setup_fzx
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/tree/sub"
  touch "$BATS_TEST_TMPDIR/tree/sub/a.txt"
  # stub: records its args; "path<TAB>[I] dir/name" with HOME as ~, like prettypath's %dir%%name%
  # (a --format=%path% run prints the path alone)
  cat > "$BATS_TEST_TMPDIR/bin/prettypath" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/pp.args"
# --version: PP_VERSION (default 0.5.0); PP_DEV=1 prints a dev version, PP_NOVERSION=1 has no --version
# (reads stdin like any run, printing nothing for the empty input fzx gives it)
if [[ "$*" == --version ]]; then
  if [[ -n "${PP_NOVERSION:-}" ]]; then cat > /dev/null; exit 0; fi
  if [[ -n "${PP_DEV:-}" ]]; then echo "prettypath dev-4"; else echo "prettypath ${PP_VERSION:-0.5.0}"; fi
  exit 0
fi
# --dirs, --base=DIR and --field=N (negative: from the end) as prettypath 0.2.0 has them; the format picks the output: "%path%<TAB>display", "display" or "%path%"
dirs="" base="" field="" format=""
for a in "$@"; do
  case "$a" in
    --dirs) dirs=1 ;;
    --base=*) base="${a#--base=}" base="${base%/}" ;;
    --field=*) field="${a#--field=}" ;;
    --format=*) format="${a#--format=}" ;;
  esac
done
# one path -> its output in the format
pp_one() {
  local p="$1" icon='[I]' shown
  # like prettypath: a trailing "/" marks a directory ([D], the folder icon) and is dropped from the path
  [[ "$p" == ?*/ ]] && p="${p%/}" icon='[D]'
  [[ -n "$dirs" ]] && icon='[D]'
  # the display: relative to --base (the base itself by its name), else with HOME as ~
  shown="${p/#$HOME/\~}"
  if [[ -n "$base" && "$p" == "$base" ]]; then shown="${p##*/}"; elif [[ -n "$base" && "$p" == "$base"/* ]]; then shown="${p#"$base"/}"; fi
  case "$format" in
    %path%) printf '%s' "$p" ;;
    '%icon% %dir%%name%') printf '%s %s' "$icon" "$shown" ;;
    *) printf '%s\t%s %s' "$p" "$icon" "$shown" ;;
  esac
}
while IFS= read -r line; do
  if [[ -n "$field" ]]; then
    IFS=$'\t' read -r -a f <<< "$line"
    i=$field
    ((i < 0)) && i=$((${#f[@]} + i + 1))
    if ((i < 1 || i > ${#f[@]})); then printf '%s\n' "$line"; continue; fi
    f[i - 1]="$(pp_one "${f[i - 1]}")"
    (IFS=$'\t'; printf '%s\n' "${f[*]}")
    continue
  fi
  printf '%s\n' "$(pp_one "$line")"
done
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/prettypath"
  export FZX_PRETTY=auto
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  TREE="$(cd "$BATS_TEST_TMPDIR/tree" && pwd -P)"
  MODS="$FZX_REPO/modules"
}

@test "pretty_on: auto follows whether prettypath is installed; 0 turns it off" {
  load_libs log pretty
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
  # prettypath 0.1.0 stats only for size and date tokens, so fzx passes no --stat_file
  ! grep -q -- "--stat_file" "$BATS_TEST_TMPDIR/pp.args"
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

@test "pretty: every path goes through prettypath, % included; the version check is cached" {
  load_libs log pretty
  fzx::pretty_on
  run fzx::pretty "$TREE" <<< "$TREE/50%off.txt"
  [ "$output" = "$TREE/50%off.txt"$'\t'"[I] 50%off.txt" ]
  [ "$(cat "$FZX_CACHE_DIR"/prettypath/*)" = current ]
  [ "$(grep -c -- '^--version$' "$BATS_TEST_TMPDIR/pp.args")" -eq 1 ]
  fzx::pretty_on
  [ "$(grep -c -- '^--version$' "$BATS_TEST_TMPDIR/pp.args")" -eq 1 ]
}

@test "pretty_level: 0.2.0 and later current; older, dev and version-less builds legacy" {
  load_libs log pretty
  local v
  for v in 0.2.0 0.7.1 1.0.0 10.2.3; do
    rm -rf "$FZX_CACHE_DIR/prettypath"
    [ "$(PP_VERSION=$v fzx::pretty_level)" = current ]
  done
  for v in 0.1.0 0.1.9 0.0.9 "1.0"; do
    rm -rf "$FZX_CACHE_DIR/prettypath"
    [ "$(PP_VERSION=$v fzx::pretty_level)" = legacy ]
  done
  rm -rf "$FZX_CACHE_DIR/prettypath"
  [ "$(PP_DEV=1 fzx::pretty_level)" = legacy ]
  rm -rf "$FZX_CACHE_DIR/prettypath"
  # without --version the binary reads stdin; the check must not wait on it (stdin here stays open 10s)
  PP_NOVERSION=1 run timeout 5 bash -c 'source "$1/lib/core.sh"; fzx::require log pretty; fzx::pretty_level' _ \
    "$FZX_REPO" < <(sleep 10)
  [ "$status" -eq 0 ] && [ "$output" = legacy ]
}

@test "pretty_on: a prettypath older than 0.2.0 counts as absent, logged once; the lists keep plain displays" {
  load_libs log pretty
  export PP_VERSION=0.1.0
  ! fzx::pretty_on
  ! fzx::pretty_on
  [ "$(grep -c 'prettypath 0.1.0 at .* is older than 0.2.0' "$LOG")" -eq 1 ]
  command -v fd > /dev/null || command -v fdfind > /dev/null || skip "fd not installed"
  FZX_MODE=files run "$MODS/files/source.sh" "$TREE"
  [[ "$output" == "$TREE/sub/a.txt"$'\t'*"sub/"*"a.txt" && "$output" != *"[I]"* ]]
  ! grep -q -- "--format" "$BATS_TEST_TMPDIR/pp.args"
}

@test "pretty: prettypath gets --base and --dirs" {
  load_libs log pretty
  run fzx::pretty "$TREE" <<< "$TREE/sub/a.txt"
  [ "$output" = "$TREE/sub/a.txt"$'\t'"[I] sub/a.txt" ]
  grep -qx -- "--format=%path%"$'\t'"%icon% %dir%%name% --base=$TREE" "$BATS_TEST_TMPDIR/pp.args"
  run fzx::pretty --dirs <<< "$TREE/sub"
  [ "$output" = "$TREE/sub"$'\t'"[D] $TREE/sub" ]
  grep -qx -- "--format=%path%"$'\t'"%icon% %dir%%name% --dirs" "$BATS_TEST_TMPDIR/pp.args"
}

@test "pretty_field: the display of field N appended, rows and order kept" {
  load_libs log pretty
  local rows=$'12\t'"$TREE/sub/a.txt"$'\tx\n3\t'"$TREE/sub/"$'\ty'
  local want=$'12\t'"$TREE/sub/a.txt"$'\tx\t[I] sub/a.txt\n3\t'"$TREE/sub/"$'\ty\t[D] sub'
  run fzx::pretty_field 2 "$TREE" <<< "$rows"
  [ "$output" = "$want" ]
  # one prettypath run decorating a copy of the field, nothing joined
  grep -qx -- "--field=-1 --format=%icon% %dir%%name% --base=$TREE" "$BATS_TEST_TMPDIR/pp.args"
}

@test "pretty_field: --dirs and no input" {
  load_libs log pretty
  run fzx::pretty_field 1 --dirs <<< "$TREE/sub"
  [ "$output" = "$TREE/sub"$'\t'"[D] $TREE/sub" ]
  run fzx::pretty_field 1 < /dev/null
  [ -z "$output" ]
}

@test "github: trees get the folder display, blobs theirs; a 0.1.x prettypath gets the plain one" {
  load_libs log config
  source "$MODS/github/source.sh" || :
  local json="$BATS_TEST_TMPDIR/tree.json"
  printf '%s' '{"truncated":false,"tree":[{"path":"src","type":"tree","sha":"t1"},{"path":"src/a.lua","type":"blob","sha":"b1","size":3}]}' > "$json"
  github::resolve() { printf -v "$3" '%s' 0123456789012345678901234567890123456789; }
  github::tree_file() { printf -v "$3" '%s' "$json"; }
  GITHUB_REPO=o/r GITHUB_REF=main
  run github::tree_rows
  [ "${#lines[@]}" -eq 2 ]
  [ "$(cut -f2,5,6 <<< "${lines[0]}")" = $'tree\tsrc\t[D] src' ]
  [ "$(cut -f2,5,6 <<< "${lines[1]}")" = $'blob\tsrc/a.lua\t[I] src/a.lua' ]
  rm -rf "$FZX_CACHE_DIR/prettypath"
  PP_VERSION=0.1.0 run github::tree_rows
  [ "${#lines[@]}" -eq 2 ]
  [[ "$(cut -f6 <<< "${lines[0]}")" == *src/ && "$output" != *"[D]"* && "$output" != *"[I]"* ]]
}

@test "recent: ranks kept beside each path's display, files only; a 0.1.x prettypath gets the plain one" {
  load_libs log config
  source "$MODS/recent/source.sh" || :
  local rows=$'9\t'"$TREE/sub/a.txt"$'\n2\t/nonexistent/x.txt'
  FZX_SORT_HEADER=0 run recent::format files <<< "$rows"
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "$TREE/sub/a.txt"$'\t'*"9"*"[I] $TREE/sub/a.txt" ]]
  rm -rf "$FZX_CACHE_DIR/prettypath"
  PP_VERSION=0.1.0 FZX_SORT_HEADER=0 run recent::format files <<< "$rows"
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "$TREE/sub/a.txt"$'\t'*"9"*"a.txt"* && "${lines[0]}" != *"[I]"* ]]
}

# the installed prettypath (0.2.0 or later), not the stub: catches a change in prettypath, or a stub that
# drifts from it. Its icons are Nerd Font glyphs and its colors escapes, so the checks strip the escapes and
# compare the text after the icon.
real_prettypath() {
  rm -f "$BATS_TEST_TMPDIR/bin/prettypath" "$FZX_CACHE_DIR"/prettypath/*
  command -v prettypath > /dev/null || skip "prettypath not installed"
  load_libs log pretty
  [ "$(fzx::pretty_level)" = current ] || skip "prettypath older than 0.2.0"
}
plain() { sed 's/\x1b\[[0-9;]*m//g'; }
# the display after the icon (prettypath's %icon% carries a space of its own)
name() { sed 's/^[^ ]* *//'; }

@test "real prettypath: pretty with a base and --dirs; a trailing / is a directory" {
  real_prettypath
  local out icon_file icon_dir
  out="$(fzx::pretty "$TREE" <<< "$TREE/sub/"$'\n'"$TREE/sub/a.txt" | plain)"
  [ "$(wc -l <<< "$out")" -eq 2 ]
  [ "$(cut -f1 <<< "$out")" = "$TREE/sub"$'\n'"$TREE/sub/a.txt" ]
  [ "$(sed -n 1p <<< "$out" | cut -f2 | name)" = sub ]
  [ "$(sed -n 2p <<< "$out" | cut -f2 | name)" = sub/a.txt ]
  icon_dir="$(sed -n 1p <<< "$out" | cut -f2 | cut -d' ' -f1)"
  icon_file="$(sed -n 2p <<< "$out" | cut -f2 | cut -d' ' -f1)"
  [ -n "$icon_dir" ] && [ "$icon_dir" != "$icon_file" ]
  # --dirs: the folder icon without the slash
  out="$(fzx::pretty --dirs "$TREE" <<< "$TREE/sub" | plain)"
  [ "$(cut -f1 <<< "$out")" = "$TREE/sub" ] && [ "$(cut -f2 <<< "$out" | cut -d' ' -f1)" = "$icon_dir" ]
  [ "$(cut -f2 <<< "$out" | name)" = sub ]
}

@test "real prettypath: pretty_field on a row with a trailing-/ path" {
  real_prettypath
  local out
  out="$(fzx::pretty_field 2 "$TREE" <<< $'7\t'"$TREE/sub/"$'\tx' | plain)"
  [ "$(cut -f1-3 <<< "$out")" = $'7\t'"$TREE/sub/"$'\tx' ]
  [ "$(cut -f4 <<< "$out" | name)" = sub ]
  [ "$(cut -f4 <<< "$out")" = "$(fzx::pretty --dirs "$TREE" <<< "$TREE/sub" | plain | cut -f2)" ]
}
