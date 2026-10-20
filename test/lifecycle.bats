#!/usr/bin/env bats
# step 3: persist policies, the persistent cache, gc of dead sessions, and popout

load test_helper

COUNTER_DIR="$(readlink -f "$BATS_TEST_DIRNAME/fixtures/modules/counter")"

setup() {
  setup_fzx
  stub_fzf
}

# FZX_PERSIST for the counter module, through the user's per-module config layer
persist() {
  mkdir -p "$FZX_CONFIG_DIR/modules/counter"
  echo "FZX_PERSIST=$1" > "$FZX_CONFIG_DIR/modules/counter/config.sh"
}

# a root session whose owner has already exited
dead_tree() {
  bash -c 'source "$1/lib/core.sh"; fzx::require log session; fzx::session_create counter "$2" "${@:3}"; printf %s "$FZX_SESSION"' \
    _ "$FZX_REPO" "$COUNTER_DIR" "$@"
}

# run fzx with a stub fzf that performs one load callback, like start:reload
run_with_load() {
  STUB_FZF_RUN="'$FZX' _cb load > /dev/null" run "$FZX" "$@"
}

@test "an invalid FZX_PERSIST fails with 1" {
  persist forever
  run "$FZX" -m counter
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid FZX_PERSIST: 'forever'"* ]]
  [ -z "$(session_dirs)" ]
}

@test "the resolved policy is recorded in meta" {
  persist cache:5m
  "$FZX" --keep -m counter
  [ "$(< "$(session_dirs)/meta/persist")" = cache:5m ]
}

@test "persist=none: every load runs the source and nothing is cached" {
  persist none
  "$FZX" --keep -m counter
  local sid
  sid="$(basename "$(session_dirs)")"
  FZX_SESSION="$sid" "$FZX" _cb load > /dev/null
  FZX_SESSION="$sid" run "$FZX" _cb load
  [ "$output" = $'one:item-2-a\none:item-2-b' ]
  [ -z "$(ls "$FZX_RUNTIME_DIR/sessions/$sid/data")" ]
}

@test "persist=session (default): nothing is written to the persistent cache" {
  run_with_load -m counter
  [ "$(< "$COUNTER_FILE")" = 1 ]
  [ ! -d "$FZX_CACHE_DIR/counter" ]
}

@test "persist=cache: a later run with the same args and cwd reuses the data" {
  persist cache:1h
  run_with_load -m counter --x
  [ -z "$(session_dirs)" ]
  run_with_load -m counter --x
  [ "$(< "$COUNTER_FILE")" = 1 ]
  grep -q 'load: persistent cache hit' "$LOG"
}

@test "persist=cache: different args miss the cache" {
  persist cache:1h
  run_with_load -m counter --x
  run_with_load -m counter --y
  [ "$(< "$COUNTER_FILE")" = 2 ]
}

@test "persist=cache: each mode is cached separately" {
  persist cache:1h
  run_with_load -m counter:one
  run_with_load -m counter:two
  [ "$(< "$COUNTER_FILE")" = 2 ]
  run_with_load -m counter:two
  [ "$(< "$COUNTER_FILE")" = 2 ]
}

@test "persist=cache: an entry older than the ttl is refreshed" {
  persist cache:1h
  run_with_load -m counter
  local file
  file="$(find "$FZX_CACHE_DIR/counter" -type f)"
  touch -d '2 hours ago' "$file"
  run_with_load -m counter
  [ "$(< "$COUNTER_FILE")" = 2 ]
  [ "$(find "$FZX_CACHE_DIR/counter" -type f -mmin -1 | wc -l)" -eq 1 ]
}

@test "persist=cache: a failing source leaves the persistent cache alone" {
  persist cache:1h
  run_with_load -m counter
  local file before
  file="$(find "$FZX_CACHE_DIR/counter" -type f)"
  before="$(< "$file")"
  "$FZX" --keep -m counter
  COUNTER_FAIL=1 FZX_SESSION="$(basename "$(session_dirs)")" run "$FZX" _cb source
  [ "$status" -eq 3 ]
  [ "$(< "$file")" = "$before" ]
}

@test "gc on start: sweeps trees whose owner died, children included" {
  local root child
  root="$(dead_tree)"
  child="$(FZX_SESSION="$root" "$FZX" _cb nav goto counter --x)"
  [ "$(session_dirs | wc -l)" -eq 2 ]
  run "$FZX" -m counter
  [ -z "$(session_dirs)" ]
  grep -q 'gc: removed 1 trees' "$LOG"
}

@test "gc on start: keeps --keep trees; gc --all removes them" {
  "$FZX" --keep -m counter
  run "$FZX" -m counter
  [ "$(session_dirs | wc -l)" -eq 1 ]
  run "$FZX" gc
  [ "$output" = "removed 0 session trees, 0 orphaned sessions, 0 cache files" ]
  run "$FZX" gc --all
  [ "$output" = "removed 1 session trees, 0 orphaned sessions, 0 cache files" ]
  [ -z "$(session_dirs)" ]
}

@test "gc: leaves trees with a live owner alone" {
  load_libs log session
  fzx::session_create counter "$COUNTER_DIR"
  run "$FZX" gc --all
  [ "$(session_dirs | wc -l)" -eq 1 ]
}

@test "gc: a recycled owner pid does not keep a tree alive" {
  load_libs log session
  fzx::session_create counter "$COUNTER_DIR"
  printf '1' > "$FZX_SESSION_DIR/meta/owner_start"
  run "$FZX" gc
  [ -z "$(session_dirs)" ]
}

@test "gc: removes children whose root is gone" {
  local root
  root="$(dead_tree)"
  FZX_SESSION="$root" "$FZX" _cb nav goto counter --x > /dev/null
  rm -rf "$FZX_RUNTIME_DIR/sessions/$root/meta"
  run "$FZX" gc
  [ "$output" = "removed 0 session trees, 1 orphaned sessions, 0 cache files" ]
}

@test "gc: removes persistent cache entries older than FZX_CACHE_MAX_AGE_DAYS" {
  mkdir -p "$FZX_CACHE_DIR/m/k" "$FZX_CACHE_DIR/m/j"
  touch -d '8 days ago' "$FZX_CACHE_DIR/m/k/old"
  touch "$FZX_CACHE_DIR/m/j/new"
  run "$FZX" gc
  [ "$output" = "removed 0 session trees, 0 orphaned sessions, 1 cache files" ]
  [ ! -d "$FZX_CACHE_DIR/m/k" ]
  [ -f "$FZX_CACHE_DIR/m/j/new" ]
}

@test "gc: unknown option fails with 2" {
  run "$FZX" gc --bogus
  [ "$status" -eq 2 ]
}

@test "popout outside tmux/Zellij rings the bell and changes nothing" {
  "$FZX" --keep -m counter
  local sid
  sid="$(basename "$(session_dirs)")"
  unset TMUX ZELLIJ
  FZX_SESSION="$sid" run "$FZX" _cb nav popout
  [ "$output" = bell ]
  [ ! -f "$FZX_RUNTIME_DIR/sessions/$sid/state/relaunch" ]
}

@test "popout toggles the tree's placement and restarts the current session" {
  "$FZX" --keep -m counter
  local sid dir
  sid="$(basename "$(session_dirs)")"
  dir="$FZX_RUNTIME_DIR/sessions/$sid"
  TMUX=fake FZF_QUERY=abc FZX_SESSION="$sid" run "$FZX" _cb nav popout
  [ "$output" = "become:$FZX --resume $sid" ]
  [ "$(< "$dir/state/popup")" = default ]
  [ "$(< "$dir/state/query")" = abc ]
  TMUX=fake FZX_SESSION="$sid" run "$FZX" _cb nav popout
  [ ! -f "$dir/state/popup" ]
}

@test "popout from a child restarts the child; placement lives on the root" {
  "$FZX" --keep -m counter
  local root child
  root="$(basename "$(session_dirs)")"
  child="$(FZX_SESSION="$root" "$FZX" _cb nav goto counter --x)"
  child="${child##* }"
  TMUX=fake FZX_SESSION="$child" run "$FZX" _cb nav popout
  [ "$output" = "become:$FZX --resume $child" ]
  [ "$(< "$FZX_RUNTIME_DIR/sessions/$root/state/popup")" = default ]
  [ ! -f "$FZX_RUNTIME_DIR/sessions/$child/state/popup" ]
}

@test "every launch in a popped-out tree asks for the popup, children included" {
  "$FZX" --keep -m counter
  local root child
  root="$(basename "$(session_dirs)")"
  child="$(FZX_SESSION="$root" "$FZX" _cb nav goto counter --x)"
  child="${child##* }"
  TMUX=fake FZX_SESSION="$child" "$FZX" _cb nav popout > /dev/null
  TMUX=fake run "$FZX" --resume "$child"
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --popup=center,80% "* ]]
  TMUX=fake run "$FZX" --resume "$root"
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --popup=center,80% "* ]]
}

@test "--popup starts in a popup inside tmux; custom options are passed through" {
  TMUX=fake run "$FZX" -m counter --popup
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --popup=center,80% "* ]]
  TMUX=fake run "$FZX" -m counter --popup=top,40%
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --popup=top,40% "* ]]
}

@test "--popup outside tmux/Zellij runs inline and logs a warning" {
  unset TMUX ZELLIJ
  run "$FZX" -m counter --popup
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " != *" --popup"* ]]
  grep -q 'popup requested outside tmux/Zellij' "$LOG"
}

@test "FZX_POPUP_OPTS from config sets the default placement" {
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_POPUP_OPTS="right,50%"' > "$FZX_CONFIG_DIR/config.sh"
  TMUX=fake run "$FZX" -m counter --popup
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --popup=right,50% "* ]]
}

@test "the popout key is bound" {
  run "$FZX" -m counter
  [ "$(fzf_bind ctrl-space)" = "ctrl-space:transform:$FZX _cb nav popout" ]
}
