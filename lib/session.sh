#!/usr/bin/env bash
# session: create, attach to and destroy session directories; read and write meta/state keys.
# Sessions form a tree: navigating to another module creates a child linked to its parent; all
# sessions in a tree share the root's id in meta/root and are destroyed together by the owner.

FZX_SESSIONS_DIR="$FZX_RUNTIME_DIR/sessions"

# fzx::session_create <module> <module_dir> [args...]; creates a root session owned by this process.
# Sets and exports FZX_SESSION, FZX_SESSION_DIR.
fzx::session_create() {
  fzx::_session_new "$@" || return 1
  fzx::meta_set root "$FZX_SESSION"
  fzx::meta_set owner_pid "$$"
  fzx::log info "session created module=$1 args=${*:3} cwd=$PWD"
}

# fzx::session_create_child <module> <module_dir> [args...]; child of the attached session.
# Sets and exports FZX_SESSION, FZX_SESSION_DIR to the child.
fzx::session_create_child() {
  local parent="$FZX_SESSION" root owner
  fzx::meta_get root root || root="$parent"
  fzx::meta_get owner_pid owner || owner=""
  fzx::_session_new "$@" || return 1
  fzx::meta_set parent "$parent"
  fzx::meta_set root "$root"
  fzx::meta_set owner_pid "$owner"
  fzx::log info "session created module=$1 args=${*:3} parent=$parent"
}

fzx::_session_new() {
  local module="$1" module_dir="$2" now
  shift 2
  fzx::now_ms now
  FZX_SESSION="${EPOCHSECONDS}-$BASHPID-$RANDOM"
  FZX_SESSION_DIR="$FZX_SESSIONS_DIR/$FZX_SESSION"
  export FZX_SESSION FZX_SESSION_DIR

  mkdir -p "$FZX_SESSION_DIR"/{meta,state,data,children} || return 1
  fzx::meta_set module "$module"
  fzx::meta_set module_dir "$module_dir"
  fzx::meta_set cwd "$PWD"
  fzx::meta_set started_ms "$now"
  if (($#)); then
    printf '%s\0' "$@" > "$FZX_SESSION_DIR/meta/args"
  else
    : > "$FZX_SESSION_DIR/meta/args"
  fi
}

# fzx::session_attach [sid]; defaults to $FZX_SESSION
fzx::session_attach() {
  local sid="${1:-${FZX_SESSION:-}}"
  [[ -n "$sid" && "$sid" != */* && -d "$FZX_SESSIONS_DIR/$sid/meta" ]] || return 1
  FZX_SESSION="$sid"
  FZX_SESSION_DIR="$FZX_SESSIONS_DIR/$sid"
  export FZX_SESSION FZX_SESSION_DIR
}

# destroy the attached session and every session whose root it is
fzx::session_destroy() {
  [[ -n "${FZX_SESSION:-}" && "$FZX_SESSION_DIR" == "$FZX_SESSIONS_DIR/$FZX_SESSION" ]] || return 1
  [[ -d "$FZX_SESSION_DIR" ]] || return 0
  local dir root n=0
  for dir in "$FZX_SESSIONS_DIR"/*/; do
    dir="${dir%/}"
    [[ "$dir" == "$FZX_SESSION_DIR" ]] && continue
    root=""
    fzx::_kv_get "$dir/meta/root" root
    if [[ "$root" == "$FZX_SESSION" ]]; then
      rm -rf -- "$dir"
      n=$((n + 1))
    fi
  done
  rm -rf -- "$FZX_SESSION_DIR"
  fzx::log info "session destroyed (and $n children)"
}

# module arguments stored at creation, into the FZX_ARGS array
fzx::session_args() {
  FZX_ARGS=()
  [[ -s "$FZX_SESSION_DIR/meta/args" ]] && mapfile -d '' -t FZX_ARGS < "$FZX_SESSION_DIR/meta/args"
  return 0
}

# modes recorded at launch, into the FZX_MODES array; a module without modes has the single mode "main"
fzx::session_modes() {
  FZX_MODES=()
  [[ -s "$FZX_SESSION_DIR/meta/modes" ]] && mapfile -d '' -t FZX_MODES < "$FZX_SESSION_DIR/meta/modes"
  ((${#FZX_MODES[@]})) || FZX_MODES=(main)
}

# fzx::session_mode <var>: current mode (state/mode, else the first mode); expects FZX_MODES loaded
fzx::session_mode() {
  fzx::state_get mode "$1" && [[ -n "${!1}" ]] || printf -v "$1" '%s' "${FZX_MODES[0]}"
}

# fzx::session_label <var>: "module:mode" of every session from the root down to this one
# (locals are _-prefixed so they cannot shadow the caller's variable)
fzx::session_label() {
  local _dir="$FZX_SESSION_DIR" _sid _module _mode _label="" _depth=0
  while [[ -d "$_dir/meta" ]] && ((_depth++ < 32)); do
    _module="" _mode=""
    fzx::_kv_get "$_dir/meta/module" _module || :
    fzx::_kv_get "$_dir/state/mode" _mode || :
    _label="$_module${_mode:+:$_mode}${_label:+ > $_label}"
    _sid=""
    fzx::_kv_get "$_dir/meta/parent" _sid || break
    _dir="$FZX_SESSIONS_DIR/$_sid"
  done
  printf -v "$1" '%s' "$_label"
}

# fzx::_kv_get <file> <var>: whole file content into var; returns 1 when the file is missing
fzx::_kv_get() {
  [[ -f "$1" ]] || return 1
  IFS= read -r -d '' "$2" < "$1" || :
}

fzx::_kv_set() {
  local tmp="$1.$BASHPID"
  printf '%s' "$2" > "$tmp" && mv -f -- "$tmp" "$1"
}

# fzx::meta_get <key> <var> / fzx::meta_set <key> <value>
fzx::meta_get() { fzx::_kv_get "$FZX_SESSION_DIR/meta/$1" "$2"; }
fzx::meta_set() { fzx::_kv_set "$FZX_SESSION_DIR/meta/$1" "$2"; }

# fzx::state_get <key> <var> / fzx::state_set <key> <value>
fzx::state_get() { fzx::_kv_get "$FZX_SESSION_DIR/state/$1" "$2"; }
fzx::state_set() { fzx::_kv_set "$FZX_SESSION_DIR/state/$1" "$2"; }

# fzx::data_path <var> <mode>: path of the cached source output for a mode
fzx::data_path() { printf -v "$1" '%s/data/%s' "$FZX_SESSION_DIR" "$2"; }
