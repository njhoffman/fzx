#!/usr/bin/env bats
# step 6: the files, logs and systemd modules (system tools stubbed where output must be fixed)

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

plain() { sed 's/\x1b\[[0-9;]*m//g'; }

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
  [ "$(fzf_bind alt-up)" = "alt-up:transform:$FZX _cb nav goto files:files $(cd "$BATS_TEST_TMPDIR" && pwd -P)" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=1 "* && " ${FZF_ARGS[*]} " == *" --scheme=path "* ]]
  run "$FZX" -m files:grep
  [ "$(fzf_bind ctrl-e)" = "ctrl-e:execute($FZX _cb action edit {1} {2})" ]
  [ "$(fzf_bind change)" = "change:reload:sleep 0.1; $FZX _cb source" ]
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

# ---- logs

@test "logs: files from config and globs, newest first, missing ones skipped" {
  mkdir -p "$FZX_CONFIG_DIR/modules/logs" "$BATS_TEST_TMPDIR/logs"
  echo old > "$BATS_TEST_TMPDIR/logs/old.log"
  touch -d '2 days ago' "$BATS_TEST_TMPDIR/logs/old.log"
  echo new > "$BATS_TEST_TMPDIR/logs/new.log"
  echo named > "$BATS_TEST_TMPDIR/named.txt"
  cat > "$FZX_CONFIG_DIR/modules/logs/config.sh" << CFG
FZX_LOGS_FILES=([named]="$BATS_TEST_TMPDIR/named.txt" [missing]=/no/such.log)
FZX_LOGS_GLOBS=("$BATS_TEST_TMPDIR/logs/*.log")
CFG
  touch -d '1 hour ago' "$BATS_TEST_TMPDIR/named.txt"
  run "$MODS/logs/source.sh"
  [ "${#lines[@]}" -eq 3 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1,2 | tr '\t\n' ' |')" = "file $BATS_TEST_TMPDIR/logs/new.log|file $BATS_TEST_TMPDIR/named.txt|file $BATS_TEST_TMPDIR/logs/old.log|" ]
  [[ "$(printf '%s' "${lines[2]}" | plain)" == *"  2d  old "* ]]
}

@test "logs: units mode lists running and failed services of both managers" {
  stub_cmd systemctl 'case "$*" in --user*) printf "a.service loaded active running User thing\n" ;; *) printf "b.service loaded failed failed System thing\n" ;; esac'
  FZX_MODE=units run "$MODS/logs/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1,2 | tr '\t\n' ' |')" = "unit-user a.service|unit-system b.service|" ]
  [[ "$(printf '%s' "${lines[1]}" | plain)" == *"system b.service"*"System thing"* ]]
}

@test "logs: docker mode, and nothing when docker is unavailable" {
  stub_cmd docker 'printf "abc123\tweb\tnginx:1\tUp 2 hours\n"'
  FZX_MODE=docker run "$MODS/logs/source.sh"
  [ "$(printf '%s' "$output" | cut -f1,2)" = $'docker\tabc123' ]
  stub_cmd docker 'echo "Cannot connect" >&2; exit 1'
  FZX_MODE=docker run --separate-stderr "$MODS/logs/source.sh"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "logs: preview and follow use the right tool per kind" {
  stub_cmd journalctl 'echo journal'
  stub_cmd docker 'echo docker'
  printf 'l1\nl2\n' > "$BATS_TEST_TMPDIR/x.log"
  run "$MODS/logs/preview.sh" file "$BATS_TEST_TMPDIR/x.log"
  [[ "$(printf '%s' "$output" | plain)" == *l2* ]]
  run "$MODS/logs/preview.sh" unit-system foo.service
  run "$MODS/logs/preview.sh" docker abc
  run "$MODS/logs/actions.sh" follow unit-user bar.service
  [ "$(cut -d' ' -f2- "$BATS_TEST_TMPDIR/calls" | tr '\n' '|')" = "--system -u foo.service -n 200 --no-pager|logs --tail 200 abc|--user -u bar.service -n 200 --no-pager -f|" ]
  run "$MODS/logs/preview.sh" bogus x
  [ "$status" -eq 2 ]
}

@test "logs: opts bind follow and accept the target" {
  stub_fzf
  run "$FZX" -m logs:units
  [ "$(fzf_bind ctrl-f)" = "ctrl-f:execute($FZX _cb action follow {1} {2})" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=2 "* ]]
}

# ---- systemd

stub_systemctl() {
  stub_cmd systemctl 'case "$*" in
    *--user*list-units*failed*) ;;
    *--user*list-units*) printf "u1.service loaded active running One\nu2.service loaded inactive dead Two\nghost.service not-found inactive dead ghost\n" ;;
    *list-units*failed*) printf "s1.service loaded failed failed Broken thing\n" ;;
    *list-units*) printf "s1.service loaded failed failed Broken thing\ns2.service loaded active exited Done\n" ;;
    *) echo "systemctl $*" ;;
  esac'
}

@test "systemd: user and system modes; not-found units are dropped" {
  stub_systemctl
  run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "user:u1.service user:u2.service " ]
  FZX_MODE=system run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "system:s1.service system:s2.service " ]
  [[ "$(printf '%s' "${lines[0]}" | plain)" == *"s1.service"*"failed"*"Broken thing"* ]]
}

@test "systemd: failed mode collects failed units of both managers" {
  stub_systemctl
  FZX_MODE=failed run "$MODS/systemd/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "system:s1.service " ]
}

@test "systemd: actions use sudo only for system units" {
  stub_systemctl
  stub_cmd sudo '"$@"'
  run "$MODS/systemd/actions.sh" restart user:u1.service system:s1.service
  [ "$status" -eq 0 ]
  run cut -d' ' -f2- "$BATS_TEST_TMPDIR/calls"
  [ "${lines[0]}" = "--user restart -- u1.service" ]
  [ "${lines[1]}" = "systemctl --system restart -- s1.service" ]
  [ "${lines[2]}" = "--system restart -- s1.service" ]
}

@test "systemd: bad ids and unknown actions fail with 2" {
  run "$MODS/systemd/actions.sh" start
  [ "$status" -eq 2 ]
  run "$MODS/systemd/actions.sh" start nginx.service
  [ "$status" -eq 2 ]
  run "$MODS/systemd/actions.sh" explode user:u1.service
  [ "$status" -eq 2 ]
  run "$MODS/systemd/preview.sh" nginx.service
  [ "$status" -eq 1 ]
}

@test "systemd: every action key is bound and listed in the header" {
  stub_fzf
  run "$FZX" -m systemd
  [ "$(fzf_bind alt-R)" = "alt-R:execute($FZX _cb action restart {+1})+reload($FZX _cb source)" ]
  [ "$(fzf_bind ctrl-l)" = "ctrl-l:execute($FZX _cb action journal {+1})" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=alt-s start  ctrl-x stop  alt-R restart  alt-e enable  alt-d disable  ctrl-l journal  ctrl-e edit "* ]]
}

# ---- manifests

@test "menu: entries from the new modules apply on this machine" {
  load_libs log session menu
  fzx::session_create menu "$MODS/menu"
  run "$FZX" _cb source
  local ids
  ids="$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')"
  [[ "$ids" == *"logs#0 "* && "$ids" == *"ps#0 "* ]]
  if command -v fd > /dev/null; then [[ "$ids" == *"files#0 "* ]]; fi
}
