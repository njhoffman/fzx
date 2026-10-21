#!/usr/bin/env bash
# run: launch a module in a new session, resume an existing session, or run a module standalone.

# fzx::run_new <module[:mode]> <dry_run> <keep> <placement> [module args...]; the calling process becomes the
# owner. <placement> is "" (inline) or a FZX_PLACEMENTS entry (popup[:OPTS], split:DIR[,SIZE]).
fzx::run_new() {
  local target="$1" dry_run="$2" keep="$3" placement="$4" module mode="" dir
  shift 4
  module="${target%%:*}"
  [[ "$target" == *:* ]] && mode="${target#*:}"
  dir="$(fzx::module_find "$module")" || fzx::die 2 "module not found: $module (FZX_MODULE_PATH=$FZX_MODULE_PATH)"

  fzx::require gc
  fzx::gc --quiet

  fzx::session_create "$module" "$dir" "$@" || fzx::die 1 "cannot create session in $FZX_SESSIONS_DIR"
  _FZX_OWNER=1
  _FZX_ROOT_SESSION="$FZX_SESSION"
  if ((keep)); then
    fzx::meta_set keep 1
  else
    trap 'fzx::_owner_cleanup' EXIT
  fi
  [[ -n "$placement" ]] && fzx::state_set placement "$placement"
  # --query: the first launch restores it like a query saved before become()
  [[ -n "${_FZX_START_QUERY:-}" ]] && fzx::state_set query "$_FZX_START_QUERY"
  local rc current
  fzx::_launch "$dry_run" "$mode"
  rc=$?
  # a placement change that fzf cannot make with become() (into or out of a split pane) ends the fzf on
  # screen and leaves state/relaunch on the root: launch the screen the user was on again, placed anew
  while ((!dry_run)) && [[ -f "$FZX_SESSIONS_DIR/$_FZX_ROOT_SESSION/state/relaunch" ]]; do
    rm -f -- "$FZX_SESSIONS_DIR/$_FZX_ROOT_SESSION/state/relaunch"
    fzx::_kv_get "$FZX_SESSIONS_DIR/$_FZX_ROOT_SESSION/state/current" current || current="$_FZX_ROOT_SESSION"
    fzx::session_attach "$current" || fzx::session_attach "$_FZX_ROOT_SESSION"
    fzx::log info "relaunch for a placement change"
    fzx::_launch 0 ""
    rc=$?
  done
  ((dry_run)) || fzx::_stat_exit "$rc"
  return "$rc"
}

# exit row: duration of the whole run, attributed to the session the user was in when it ended
fzx::_stat_exit() {
  local rc="$1" started now current kind
  fzx::require stats
  fzx::session_attach "$_FZX_ROOT_SESSION" || return 0
  fzx::meta_get started_ms started || started=0
  fzx::now_ms now
  fzx::state_get current current && fzx::session_attach "$current" || current="$_FZX_ROOT_SESSION"
  fzx::meta_get module FZX_MODULE
  fzx::state_get mode FZX_MODE || FZX_MODE=-
  case "$rc" in
    0) kind=accept ;;
    1) kind=nomatch ;;
    2) kind=error ;;
    130) kind=abort ;;
    *) kind=rc ;;
  esac
  fzx::stat exit "$((now - started))" - "rc:$rc $kind"
  fzx::session_attach "$_FZX_ROOT_SESSION"
}

fzx::_owner_cleanup() {
  fzx::session_attach "$_FZX_ROOT_SESSION" && fzx::session_destroy
}

# fzx::run_resume <sid> <dry_run> [mode]; never cleans up, the owner does
fzx::run_resume() {
  local sid="$1" dry_run="$2" mode="${3:-}"
  fzx::session_attach "$sid" || fzx::die 2 "no such session: ${sid:-<FZX_SESSION unset>}"
  fzx::log info "session resumed${mode:+ mode=$mode}"
  fzx::_launch "$dry_run" "$mode"
}

# fzx::run_standalone <module_dir> [module args...]; no session, cache or navigation.
# The mode comes from $FZX_MODE (default: the first mode).
fzx::run_standalone() {
  FZX_STANDALONE=1
  FZX_MODULE_DIR="$1"
  FZX_MODULE="${1##*/}"
  shift
  FZX_ARGS=("$@")
  fzx::config_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  fzx::require components
  fzx::comp_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  local mode="${FZX_MODE:-$FZX_MODE_DEFAULT}"
  fzx::_mode_valid "$mode" || fzx::die 2 "unknown mode for $FZX_MODULE: $mode (modes: ${FZX_MODES[*]})"
  export FZX_MODE="$mode"
  fzx::comp_current
  fzx::opts_build "$FZX_MODULE" || fzx::die 1 "$FZX_MODULE::opts failed"
  fzx::_fzf
}

# fzx::_launch <dry_run> <requested mode or "">
fzx::_launch() {
  local dry_run="$1" requested="$2" mode
  fzx::meta_get module FZX_MODULE
  fzx::meta_get module_dir FZX_MODULE_DIR
  fzx::session_args

  fzx::config_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  # shellcheck source=/dev/null
  source "$FZX_MODULE_DIR/module.sh" || fzx::die 1 "cannot load $FZX_MODULE_DIR/module.sh"

  # only validated here; the ttl itself is read again by the callbacks
  # shellcheck disable=SC2034
  local ttl
  fzx::persist_ttl "$FZX_PERSIST" ttl || fzx::die 1 "$FZX_MODULE: invalid FZX_PERSIST: '$FZX_PERSIST' (none, session or cache:<ttl>)"
  fzx::meta_set persist "$FZX_PERSIST"

  fzx::require components
  fzx::comp_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  fzx::comp_save
  printf '%s\0' "${FZX_MODES[@]}" > "$FZX_SESSION_DIR/meta/modes"
  if [[ -n "$requested" ]]; then
    fzx::_mode_valid "$requested" || fzx::die 2 "unknown mode for $FZX_MODULE: $requested (modes: ${FZX_MODES[*]})"
    mode="$requested"
  else
    fzx::state_get mode mode || mode="$FZX_MODE_DEFAULT"
    if ! fzx::_mode_valid "$mode"; then
      fzx::log warn "saved mode '$mode' no longer exists, using $FZX_MODE_DEFAULT"
      mode="$FZX_MODE_DEFAULT"
    fi
  fi
  fzx::state_set mode "$mode"
  export FZX_MODE="$mode"
  fzx::comp_current
  fzx::comp_has toggle && fzx::state_set toggles "$FZX_TOGGLES"
  [[ -n "$FZX_SORT" ]] && fzx::state_set sort "$FZX_SORT"

  fzx::opts_build "$FZX_MODULE" || fzx::die 1 "$FZX_MODULE::opts failed"
  fzx::_placement

  fzx::require stats
  export FZX_STATS FZX_STATS_FILE
  if ((!dry_run)); then
    local root
    fzx::meta_get root root || root="$FZX_SESSION"
    fzx::_kv_set "$FZX_SESSIONS_DIR/$root/state/current" "$FZX_SESSION"
    if [[ -n "${_FZX_OWNER:-}" && -z "${_FZX_STARTED:-}" ]]; then
      _FZX_STARTED=1
      fzx::stat start 0 - "$FZX_MODULE${FZX_ARGS[*]:+ ${FZX_ARGS[*]}}"
    fi
  fi

  if ((dry_run)); then
    printf '# module  %s:%s (%s)\n# session %s (%s)\n' \
      "$FZX_MODULE" "$FZX_MODE" "$FZX_MODULE_DIR" "$FZX_SESSION" "$FZX_SESSION_DIR"
    fzx::opts_print
    return 0
  fi
  fzx::_fzf
}

# placement is per session tree (the root's state/popup) and applied on every launch: fzf runs become()
# from a popup in the original terminal, not inside the popup, so each launch has to ask for the popup
# again to stay in it (observed with fzf 0.74; see docs/design.md)
# fzx::placement <var>: the tree's placement (root state/placement), "inline" when unset or when it cannot
# run here
fzx::placement() {
  local _p="" _root
  fzx::meta_get root _root || _root="$FZX_SESSION"
  fzx::_kv_get "$FZX_SESSIONS_DIR/$_root/state/placement" _p || _p=inline
  if ! fzx::placement_ok "$_p"; then
    fzx::log warn "placement $_p is not available here (popup needs tmux or Zellij, split tmux), running inline"
    _p=inline
  fi
  printf -v "$1" '%s' "$_p"
}

# fzx::placement_ok <placement>: it can run in this terminal
fzx::placement_ok() {
  case "$1" in
    inline) return 0 ;;
    popup | popup:*) [[ -n "${TMUX:-}" || -n "${ZELLIJ:-}" ]] ;;
    split:*) [[ -n "${TMUX:-}" ]] && command -v tmux > /dev/null ;;
    *) return 1 ;;
  esac
}

# popups are fzf's own --popup, asked for on every launch: become() inside a popup runs in the caller's
# terminal, so a launch that did not ask again would drop back inline. Splits are made by the owner
# (fzx::_fzf_split); launches inside the split pane are not the owner and run inline there.
fzx::_placement() {
  local p
  fzx::placement p
  case "$p" in
    popup) FZX_OPTS+=("--popup=$FZX_POPUP_OPTS") ;;
    popup:*) FZX_OPTS+=("--popup=${p#popup:}") ;;
  esac
}

fzx::_mode_valid() {
  local m
  for m in "${FZX_MODES[@]}"; do
    [[ "$m" == "$1" ]] && return 0
  done
  return 1
}

# The owner runs fzf as a child so it can clean up when the become() chain ends. Every other launch
# (resume, mode restart, navigation) execs fzf: otherwise each become() would leave one more waiting
# bash process behind it and the process chain would grow with every navigation.
fzx::_fzf() {
  local start end rc
  if [[ -z "${_FZX_OWNER:-}" && -z "${FZX_STANDALONE:-}" ]]; then
    fzx::log info "fzf exec module=$FZX_MODULE mode=$FZX_MODE opts=${#FZX_OPTS[@]}"
    exec fzf "${FZX_OPTS[@]}" < /dev/null
  fi
  fzx::now_ms start
  local p=inline
  [[ -z "${FZX_STANDALONE:-}" ]] && fzx::placement p
  if [[ "$p" == split:* ]]; then
    fzx::log info "fzf start in a split ($p) module=$FZX_MODULE mode=$FZX_MODE"
    fzx::_fzf_split "${p#split:}"
  else
    fzx::log info "fzf start module=$FZX_MODULE mode=$FZX_MODE opts=${#FZX_OPTS[@]}"
    fzf "${FZX_OPTS[@]}" < /dev/null
  fi
  rc=$?
  fzx::now_ms end
  fzx::log info "fzf exit rc=$rc $((end - start))ms"
  return "$rc"
}

# fzx::_fzf_split <DIR[,SIZE]>: run the current session in a new tmux split pane and wait for it; its output
# becomes ours. fzf-tmux is not used: it passes only TERM and the FZF_* options into the pane, and the
# callbacks need the whole environment (FZX_SESSION, the directories, module settings). The pane runs
# `fzx --resume` (not the owner, so it execs fzf, and become() keeps working inside the pane).
fzx::_fzf_split() {
  local spec="$1" dir size flags=() pane rc=130 base="$FZX_SESSION_DIR/split" cmd
  dir="${spec%%,*}"
  size=""
  [[ "$spec" == *,* ]] && size="${spec#*,}"
  case "$dir" in
    down) flags=(-v) ;;
    up) flags=(-v -b) ;;
    right) flags=(-h) ;;
    left) flags=(-h -b) ;;
    *)
      fzx::log error "bad split direction: $dir (up, down, left or right)"
      printf 'fzx: bad split direction: %s\n' "$dir" >&2
      return 2
      ;;
  esac
  [[ -n "$size" ]] && flags+=(-l "$size")
  rm -f -- "$base".out "$base".rc
  # the pane inherits tmux's environment, not ours: replay our exported variables there
  export -p | grep -vE '^declare -x (PWD|OLDPWD|SHLVL|TMUX_PANE|_)=' > "$base.env"
  printf -v cmd 'source %q; export FZX_SPLIT_PANE=1; %q --resume %q > %q; echo $? > %q' \
    "$base.env" "$FZX_BIN" "$FZX_SESSION" "$base.out" "$base.rc"
  if ! pane="$(tmux split-window -P -F '#{pane_id}' -c "$PWD" "${flags[@]}" "bash -c $(printf '%q' "$cmd")")"; then
    fzx::log error "tmux split-window failed, running inline"
    fzf "${FZX_OPTS[@]}" < /dev/null
    return
  fi
  fzx::log info "split pane $pane"
  # until the pane reports, or disappears (closed by hand)
  while [[ ! -s "$base.rc" ]] && tmux list-panes -a -F '#{pane_id}' 2> /dev/null | grep -qxF -- "$pane"; do
    sleep 0.1
  done
  [[ -s "$base.rc" ]] && rc="$(< "$base.rc")"
  [[ -f "$base.out" ]] && cat -- "$base.out"
  rm -f -- "$base".out "$base".rc "$base".env
  return "$rc"
}
