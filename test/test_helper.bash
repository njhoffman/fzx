#!/usr/bin/env bash

# shellcheck disable=SC2034  # FZX, LOG and the helpers below are used by the .bats files
FZX_REPO="$(readlink -f "$BATS_TEST_DIRNAME/..")"
FZX="$FZX_REPO/bin/fzx"

# isolate every test from the user's runtime, state and config directories
setup_fzx() {
  unset FZX_ROOT FZX_SESSION FZX_SESSION_DIR FZX_LOG_FILE FZX_KEEP FZX_STATS FZX_STATS_FILE FZX_HISTORY TMUX ZELLIJ
  export FZX_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export FZX_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export FZX_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export FZX_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export FZX_MODULE_PATH="$BATS_TEST_DIRNAME/fixtures/modules:$FZX_REPO/modules"
  export FZX_LOG_LEVEL=debug
  export COUNTER_FILE="$BATS_TEST_TMPDIR/counter"
  LOG="$FZX_STATE_DIR/fzx.log"
}

# source the libraries into the test shell
load_libs() {
  # shellcheck source=../lib/core.sh
  source "$FZX_REPO/lib/core.sh"
  fzx::require "$@"
}

# stub fzf: records its args (NUL-separated), the session and mode it ran in and a listing of the
# session dir. Evaluates $STUB_FZF_RUN (to act like a callback), prints $STUB_FZF_OUT, exits $STUB_FZF_RC.
stub_fzf() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/fzf" << 'STUB'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$BATS_TEST_TMPDIR/fzf.args"
printf '%s' "${FZX_SESSION:-}" > "$BATS_TEST_TMPDIR/fzf.session"
printf '%s' "${FZX_MODE:-}" > "$BATS_TEST_TMPDIR/fzf.mode"
[[ -n "${FZX_SESSION_DIR:-}" ]] && ls "$FZX_SESSION_DIR" > "$BATS_TEST_TMPDIR/fzf.sessiondir"
[[ -n "${STUB_FZF_RUN:-}" ]] && eval "$STUB_FZF_RUN"
[[ -n "${STUB_FZF_OUT:-}" ]] && printf '%s\n' "$STUB_FZF_OUT"
exit "${STUB_FZF_RC:-0}"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/fzf"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# args the stub fzf received, into the FZF_ARGS array
read_fzf_args() {
  mapfile -d '' -t FZF_ARGS < "$BATS_TEST_TMPDIR/fzf.args"
}

# value following the first `--bind` whose value starts with "<key>:"
fzf_bind() {
  local i
  read_fzf_args
  for ((i = 0; i < ${#FZF_ARGS[@]} - 1; i++)); do
    if [[ "${FZF_ARGS[i]}" == --bind && "${FZF_ARGS[i + 1]}" == "$1:"* ]]; then
      printf '%s\n' "${FZF_ARGS[i + 1]}"
      return 0
    fi
  done
  return 1
}

# value following a flag given as a separate arg (e.g. --preview)
fzf_flag() {
  local i
  read_fzf_args
  for ((i = 0; i < ${#FZF_ARGS[@]} - 1; i++)); do
    if [[ "${FZF_ARGS[i]}" == "$1" ]]; then
      printf '%s\n' "${FZF_ARGS[i + 1]}"
      return 0
    fi
  done
  return 1
}

session_dirs() {
  find "$FZX_RUNTIME_DIR/sessions" -mindepth 1 -maxdepth 1 -type d 2> /dev/null
}
