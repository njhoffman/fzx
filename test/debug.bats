#!/usr/bin/env bats
# fzx debug state/send/attach, against a stub curl standing in for fzf's --listen server

load test_helper

setup() {
  setup_fzx
  load_libs log session
  # stub curl: GET answers canned state, POST records the body and answers 200 (400 for "bogus")
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/curl" << 'STUB'
#!/usr/bin/env bash
sock="" data="" post=0 url=""
while (($#)); do
  case "$1" in
    --unix-socket) sock="$2"; shift ;;
    --data-binary) data="$2"; shift ;;
    -X) [[ "$2" == POST ]] && post=1; shift ;;
    -m | -w) shift ;;
    http*) url="$1" ;;
  esac
  shift
done
[[ -f "${sock%/fzf.sock}/dead" ]] && exit 7
echo "$sock $url" >> "$BATS_TEST_TMPDIR/curl.calls"
if ((post)); then
  printf '%s\n' "$data" >> "$BATS_TEST_TMPDIR/curl.posts"
  if [[ "$data" == bogus ]]; then printf 'unknown action: bogus\n\n400'; else printf '\n200'; fi
else
  printf '{"query":"q","position":1,"matchCount":2,"totalCount":5,"reading":false,"current":{"index":3,"text":"cur"},"selected":[{"index":4,"text":"sel"}],"matches":[{"index":3,"text":"cur"}]}'
fi
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# a session with a socket file (the stub only checks that it exists)
listening() {
  fzx::session_create counter /d
  fzx::meta_set started_ms "$1"
  python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$FZX_SESSION_DIR/fzf.sock"
  printf '%s' "$FZX_SESSION"
}

@test "state: the newest listening session by default, or the one given" {
  local old new
  old="$(listening 1000)"
  new="$(listening 2000)"
  run "$FZX" debug state
  [ "$status" -eq 0 ]
  [[ "$output" == *'"query":"q"'* ]]
  [[ "$(tail -n 1 "$BATS_TEST_TMPDIR/curl.calls")" == "$FZX_RUNTIME_DIR/sessions/$new/fzf.sock http://localhost?limit=10" ]]
  run "$FZX" debug state "$old" 3
  [[ "$(tail -n 1 "$BATS_TEST_TMPDIR/curl.calls")" == "$FZX_RUNTIME_DIR/sessions/$old/fzf.sock http://localhost?limit=3" ]]
}

@test "state: sessions whose fzf no longer answers are skipped" {
  local old new
  old="$(listening 1000)"
  new="$(listening 2000)"
  touch "$FZX_RUNTIME_DIR/sessions/$new/dead"
  run "$FZX" debug state
  [[ "$(tail -n 1 "$BATS_TEST_TMPDIR/curl.calls")" == "$FZX_RUNTIME_DIR/sessions/$old/fzf.sock "* ]]
}

@test "no listening session, or an unknown one, fails with 2" {
  run "$FZX" debug state
  [ "$status" -eq 2 ]
  [[ "$output" == *"no running fzx session is listening"* ]]
  run "$FZX" debug state nope
  [ "$status" -eq 2 ]
}

@test "send: posts the action; fzf's error is reported with status 1" {
  listening 1000 > /dev/null
  run "$FZX" debug send 'change-query(foo bar)'
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/curl.posts")" = "change-query(foo bar)" ]
  run "$FZX" debug send bogus
  [ "$status" -eq 1 ]
  [ "$output" = "fzf: unknown action: bogus" ]
  run "$FZX" debug send
  [ "$status" -eq 2 ]
}

@test "attach: state is summarised, other lines are sent as actions" {
  command -v jq > /dev/null || skip "jq not installed"
  listening 1000 > /dev/null
  run bash -c "printf 'state\nreload(seq 3)\nbogus\nquit\n' | '$FZX' debug attach"
  [[ "${lines[0]}" == "attached to "*" (counter)"* ]]
  [[ "$output" == *'query     "q"'* ]]
  [[ "$output" == *"position  1   matches 2/5   selected 1   reading false"* ]]
  [[ "$output" == *$'selected\n  4\tsel'* ]]
  [[ "$output" == *$'\nok\n'* ]]
  [[ "$output" == *"fzf: unknown action: bogus"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/curl.posts")" = $'reload(seq 3)\nbogus' ]
}

@test "debug without a subcommand prints usage with 2" {
  run "$FZX" debug
  [ "$status" -eq 2 ]
  [[ "$output" == *"fzx debug attach [SID]"* ]]
}

@test "f2: session state, data, FZF_* variables and the focused line" {
  stub_fzf
  "$FZX" --keep -m counter:two --x
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" "$FZX" _cb load > /dev/null
  echo "my query" > "$FZX_RUNTIME_DIR/sessions/$sid/state/query"
  FZX_SESSION="$sid" FZF_QUERY=abc FZF_POS=2 FZF_PREVIEW_COLUMNS=120 run "$FZX" _cb debug $'id\tshown'
  [ "$status" -eq 0 ]
  output="$(printf '%s' "$output" | sed 's/\x1b\[[0-9;]*m//g')"
  [[ "$output" == "session $sid"* ]]
  [[ "$output" == *"  path                   counter:two"* ]]
  [[ "$output" == *"  args                   --x"* ]]
  [[ "$output" == *"  modes                  one two three"* ]]
  [[ "$output" == *$'state/\n'*"  query                  my query"* ]]
  # two items plus the "args:--x" line the fixture prints when given args
  [[ "$output" == *"  two                    3 lines, "*"s old"* ]]
  [[ "$output" == *"  FZF_POS                2"* && "$output" == *"  FZF_QUERY              abc"* ]]
  # FZX_* with the config loaded: settings, and arrays one element per row
  [[ "$output" == *$'\nfzx (FZX_*'* && "$output" == *"  FZX_KEY_STYLE          full"* ]]
  [[ "$output" == *"  FZX_KEYS[help]         f1"* && "$output" == *"  FZX_MODULE             counter"* ]]
  [[ "$output" == *$'focused line'*$'\n  id⇥shown'* ]]
  [[ "$output" != *"persistent cache"* ]]
}

@test "f2: cache: modules show their persistent cache entry" {
  stub_fzf
  mkdir -p "$FZX_CONFIG_DIR/modules/counter"
  echo 'FZX_PERSIST=cache:1h' > "$FZX_CONFIG_DIR/modules/counter/config.sh"
  "$FZX" --keep -m counter
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" "$FZX" _cb load > /dev/null
  FZX_SESSION="$sid" run "$FZX" _cb debug
  [[ "$output" == *"persistent cache"*"cache:1h"* ]]
  [[ "$output" == *"$FZX_CACHE_DIR/counter/"* ]]
}

@test "f2 is bound under fzx and standalone, and listed in the help" {
  stub_fzf
  run "$FZX" -m ps
  [ "$(fzf_bind f2)" = "f2:show-preview+preview:$FZX _cb debug {}" ]
  local bind cmd
  bind="$(fzf_bind f1)"
  cmd="$(bash -c "${bind#f1:transform:}")"
  run bash -c "${cmd#show-preview+preview:}"
  [[ "$output" == *"f2"*"debug: session state, FZF_* and FZX_* variables"* ]]
  run "$BATS_TEST_DIRNAME/../modules/ps/module.sh"
  [ "$(fzf_bind f2)" = "f2:show-preview+preview:env | grep -E '^(FZX|FZF)_' | sort" ]
}
