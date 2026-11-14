#!/usr/bin/env bash
# run: launch a module in a new session, resume an existing session, or run a module standalone.

# fzx::run_new <module[:mode]> <dry_run> <keep> <placement> [module args...]; the calling process becomes the
# owner. <placement> is "" (inline) or a FZX_PLACEMENTS entry (popup[:OPTS], split:DIR[,SIZE], float[:OPTS]).
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
  ((keep)) && fzx::meta_set keep 1
  # the exit row and cleanup also run when the terminal goes away (SIGHUP) or the owner is killed
  # a dry run records no exit row
  _FZX_EXIT_STATED="$dry_run"
  trap 'fzx::_owner_exit $? '"$keep" EXIT
  # $? in the EXIT trap is the last command's status, not the signal's: exit with 128+N so the row says why
  trap 'exit 129' HUP
  trap 'exit 143' TERM
  [[ -n "$placement" ]] && fzx::state_set placement "$placement"
  # --query: the first launch restores it like a query saved before become()
  [[ -n "${_FZX_START_QUERY:-}" ]] && fzx::state_set query "$_FZX_START_QUERY"
  local rc current
  fzx::_launch "$dry_run" "$mode"
  rc=$?
  # a placement change that fzf cannot make with become() (into or out of a tmux pane) ends the fzf on
  # screen and leaves state/relaunch on the root: launch the screen the user was on again, placed anew.
  # The root is this tree's, or the one it adopted (a kept tree the sessions list resumed here)
  local relaunch_root
  while ((!dry_run)) && fzx::_relaunch_root relaunch_root; do
    rm -f -- "$FZX_SESSIONS_DIR/$relaunch_root/state/relaunch"
    fzx::_kv_get "$FZX_SESSIONS_DIR/$relaunch_root/state/current" current || current="$relaunch_root"
    fzx::session_attach "$current" || fzx::session_attach "$relaunch_root"
    fzx::log info "relaunch for a placement change"
    fzx::_launch 0 ""
    rc=$?
  done
  ((dry_run)) || fzx::_stat_exit "$rc"
  _FZX_EXIT_STATED=1
  return "$rc"
}

# fzx::_relaunch_root <var>: the root with a relaunch pending: this owner's tree's, else the tree it adopted
# (state/adopt on its root, set by the sessions list when it resumes a kept tree here); fails when none
fzx::_relaunch_root() {
  local _own="$FZX_SESSIONS_DIR/$_FZX_ROOT_SESSION" _a=""
  if [[ -f "$_own/state/relaunch" ]]; then
    printf -v "$1" '%s' "$_FZX_ROOT_SESSION"
    return 0
  fi
  fzx::_kv_get "$_own/state/adopt" _a && [[ -n "$_a" && -f "$FZX_SESSIONS_DIR/$_a/state/relaunch" ]] || return 1
  printf -v "$1" '%s' "$_a"
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
    129) kind=hangup ;;
    143) kind=term ;;
    *) kind=rc ;;
  esac
  fzx::stat exit "$((now - started))" - "rc:$rc $kind"
  fzx::session_attach "$_FZX_ROOT_SESSION"
}

# fzx::_owner_exit <rc> <keep>: the EXIT trap; an owner ended by a signal never got its exit row
fzx::_owner_exit() {
  # only a run that got as far as its start row gets an exit row
  [[ -n "${_FZX_STARTED:-}" ]] && ((!_FZX_EXIT_STATED)) && fzx::_stat_exit "$1"
  fzx::_resize_hook_unset "$FZX_SESSIONS_DIR/$_FZX_ROOT_SESSION"
  # an adopted tree (kept) keeps its sessions but not the hook its launches here set on this window
  local _adopt=""
  fzx::_kv_get "$FZX_SESSIONS_DIR/$_FZX_ROOT_SESSION/state/adopt" _adopt && [[ -n "$_adopt" ]] &&
    fzx::_resize_hook_unset "$FZX_SESSIONS_DIR/$_adopt"
  (($2)) || { fzx::session_attach "$_FZX_ROOT_SESSION" && fzx::session_destroy; }
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
  [[ -n "${FZX_MODE:-}" ]] || fzx::_start_mode mode
  fzx::_mode_valid "$mode" || fzx::die 2 "unknown mode for $FZX_MODULE: $mode (modes: ${FZX_MODES[*]})"
  fzx::_mode_hidden "$mode" && FZX_MODES=("$mode")
  export FZX_MODE="$mode"
  fzx::comp_current
  fzx::opts_build "$FZX_MODULE" || fzx::die 1 "$FZX_MODULE::opts failed"
  fzx::_fzf
}

# fzx::_start_mode <var>: a launch that names no mode lets the module's <module>::start_mode <mode> <var>
# pick another (todos: all when there is no TODO.md here); an unknown answer keeps the mode
fzx::_start_mode() {
  local -n __sm_mode="$1"
  local __sm_new
  declare -F "$FZX_MODULE::start_mode" > /dev/null || return 0
  "$FZX_MODULE::start_mode" "$__sm_mode" __sm_new || return 0
  if [[ -n "$__sm_new" && "$__sm_new" != "$__sm_mode" ]]; then
    if fzx::_mode_valid "$__sm_new"; then
      fzx::log debug "$FZX_MODULE::start_mode: $__sm_mode -> $__sm_new"
      __sm_mode="$__sm_new"
    else
      fzx::log warn "$FZX_MODULE::start_mode picked an unknown mode: $__sm_new"
    fi
  fi
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
  if [[ -n "$requested" ]]; then
    fzx::_mode_valid "$requested" || fzx::die 2 "unknown mode for $FZX_MODULE: $requested (modes: ${FZX_MODES[*]})"
    mode="$requested"
  else
    fzx::state_get mode mode || mode="$FZX_MODE_DEFAULT"
    if ! fzx::_mode_valid "$mode"; then
      fzx::log warn "saved mode '$mode' no longer exists, using $FZX_MODE_DEFAULT"
      mode="$FZX_MODE_DEFAULT"
    fi
    fzx::_start_mode mode
  fi
  # a hidden mode is the session's only one: the mode keys and the component line leave it alone
  fzx::_mode_hidden "$mode" && FZX_MODES=("$mode")
  printf '%s\0' "${FZX_MODES[@]}" > "$FZX_SESSION_DIR/meta/modes"
  fzx::state_set mode "$mode"
  export FZX_MODE="$mode"
  fzx::comp_current
  fzx::comp_has toggle && fzx::state_set toggles "$FZX_TOGGLES"
  [[ -n "$FZX_SORT" ]] && fzx::state_set sort "$FZX_SORT"

  fzx::opts_build "$FZX_MODULE" || fzx::die 1 "$FZX_MODULE::opts failed"
  fzx::_placement "$dry_run"

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
    fzx::log warn "placement $_p is not available here (popup needs tmux or Zellij, split tmux, float tmux with new-pane), running inline"
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
    float | float:*) [[ -n "${TMUX:-}" ]] && tmux list-commands new-pane > /dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# fzx::placement_pane <placement>: it runs in a tmux pane the owner makes (moving into or out of one needs a
# relaunch, become() cannot do it)
fzx::placement_pane() {
  [[ "$1" == split:* || "$1" == float || "$1" == float:* ]]
}

# fzx::placement_from_fzf_tmux <var>: the starting placement FZF_TMUX asks for (fzf's shell integration
# setting), from FZF_TMUX_OPTS in fzf-tmux syntax: -p[W[,H]] (with -w W / -h H) a popup, -d/-u/-l/-r [SIZE]
# a split down/up/left/right; nothing recognised, or no options, a popup. Fails when FZF_TMUX is off or
# this is not inside tmux.
fzx::placement_from_fzf_tmux() {
  local _var="$1" _o _opts=() _p="" _w="" _h="" _i _val
  [[ -n "${FZF_TMUX:-}" && "${FZF_TMUX}" != 0 && -n "${TMUX:-}" ]] || return 1
  read -ra _opts <<< "${FZF_TMUX_OPTS:-}"
  for ((_i = 0; _i < ${#_opts[@]}; _i++)); do
    _o="${_opts[_i]}"
    _val="${_o:2}"
    # a value may follow as its own word: -d 40%, -p 80%,60%
    if [[ -z "$_val" && "${_opts[_i + 1]:-}" =~ ^[0-9] ]]; then
      _val="${_opts[_i + 1]}"
      ((_i++))
    fi
    case "$_o" in
      -p*)
        _p=popup _w="${_val%%,*}"
        [[ "$_val" == *,* ]] && _h="${_val#*,}"
        ;;
      -w*) _w="$_val" ;;
      -h*) _h="$_val" ;;
      -d*) _p="split:down,${_val:-50%}" ;;
      -u*) _p="split:up,${_val:-50%}" ;;
      -l*) _p="split:left,${_val:-50%}" ;;
      -r*) _p="split:right,${_val:-50%}" ;;
      *) fzx::log debug "FZF_TMUX_OPTS: $_o ignored" ;;
    esac
  done
  if [[ -z "$_p" || "$_p" == popup ]]; then
    _p=popup
    [[ -n "$_w" ]] && _p="popup:center,$_w${_h:+,$_h}"
  fi
  printf -v "$_var" '%s' "$_p"
}

# popups are fzf's own --popup, asked for on every launch: become() inside a popup runs in the caller's
# terminal, so a launch that did not ask again would drop back inline. Splits are made by the owner
# (fzx::_fzf_split); launches inside the split pane are not the owner and run inline there. A popup
# launch records its geometry (fzx::popup_geometry) and, in tmux, makes sure the window's resize hook is
# set (fzx::_resize_hook_set), so the popup follows the window. In a split or float pane fzf has the whole
# pane, so it is asked for all of it: a --height from the user's FZF_DEFAULT_OPTS(_FILE) (-1 keeps a shell
# line visible inline) would leave rows empty under its border. fzf's --popup sizes its own fzf already.
fzx::_placement() {
  local dry_run="${1:-0}" p spec geo
  fzx::placement p
  fzx::placement_pane "$p" && FZX_OPTS+=(--height=100%)
  case "$p" in
    popup | popup:*)
      if [[ "$p" == popup ]]; then fzx::popup_opts popup spec; else spec="${p#popup:}"; fi
      FZX_OPTS+=("--popup=$spec")
      if ((!dry_run)) && fzx::in_session; then
        fzx::popup_geometry "$spec" geo && fzx::state_set popup_geometry "$geo"
        fzx::_resize_hook_set
      fi
      ;;
  esac
}

# fzx::popup_geometry <spec> <var>: what a popup's size depends on, "SPEC WxH" (the spec and the window's
# size, fzx::window_size); a launch and a later resize compare it to tell whether the popup must change
fzx::popup_geometry() {
  local _ww _wh
  fzx::window_size _ww _wh || return 1
  printf -v "$2" '%s %sx%s' "$1" "$_ww" "$_wh"
}

# fzx::_resize_hook_set: once per session tree, on the root's first popup launch in tmux: a window-resized
# hook on the calling pane's window that runs `fzx _resized ROOT_DIR INDEX PANE` (fzx::resized). The
# index (from the root's id) keeps other hooks and other fzx trees in the same window apart. Recorded in
# the root's state/resize_hook ("INDEX PANE"); the owner removes it on exit (fzx::_resize_hook_unset).
fzx::_resize_hook_set() {
  [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || return 0
  local root root_dir idx cmd
  fzx::meta_get root root || root="$FZX_SESSION"
  root_dir="$FZX_SESSIONS_DIR/$root"
  [[ -f "$root_dir/state/resize_hook" ]] && return 0
  idx="$(cksum <<< "$root")"
  idx=$((${idx%% *} % 1000000 + 1000))
  if [[ "$FZX_BIN$root_dir$TMUX_PANE" == *[\'\"\\\;]* ]]; then
    fzx::log warn "resize hook: a quote or ; in $FZX_BIN or $root_dir, the popup will not follow the window"
    return 0
  fi
  printf -v cmd '%q _resized %q %q %q' "$FZX_BIN" "$root_dir" "$idx" "$TMUX_PANE"
  if tmux set-hook -w -t "$TMUX_PANE" "window-resized[$idx]" "run-shell -b '$cmd'" 2>> "$FZX_LOG_FILE"; then
    fzx::_kv_set "$root_dir/state/resize_hook" "$idx $TMUX_PANE"
    fzx::log info "resize hook window-resized[$idx] set on $TMUX_PANE's window"
  else
    fzx::log warn "resize hook: tmux set-hook failed, the popup will not follow the window"
  fi
}

# fzx::_resize_hook_unset <root dir>: remove the tree's resize hook, if it set one
fzx::_resize_hook_unset() {
  local hook=""
  fzx::_kv_get "$1/state/resize_hook" hook || return 0
  tmux set-hook -uw -t "${hook#* }" "window-resized[${hook%% *}]" 2> /dev/null || :
  rm -f -- "$1/state/resize_hook"
}

# fzx::resized <root dir> <index> <pane>: the window-resized hook (tmux runs it, outside any session's
# environment). A tree that is gone removes its hook. While the window keeps changing (a drag) only the last
# event acts: the size is read twice, FZX_RESIZE_SETTLE_MS apart. Then the fzf on screen (the root's
# state/current) is sent `transform(fzx _cb nav relayout)` on its --listen socket, which restarts it in a
# popup sized for the window when its geometry changed.
fzx::resized() {
  local root_dir="$1" idx="$2" pane="$3" current="" sock w1 h1 w2 h2 cmd
  if [[ ! -d "$root_dir" ]]; then
    tmux set-hook -uw -t "$pane" "window-resized[$idx]" 2> /dev/null || :
    return 0
  fi
  read -r w1 h1 < <(tmux display-message -p -t "$pane" '#{window_width} #{window_height}' 2> /dev/null) || return 0
  sleep "$(printf '%d.%03d' $((${FZX_RESIZE_SETTLE_MS:-300} / 1000)) $((${FZX_RESIZE_SETTLE_MS:-300} % 1000)))"
  read -r w2 h2 < <(tmux display-message -p -t "$pane" '#{window_width} #{window_height}' 2> /dev/null) || return 0
  [[ "${w1}x$h1" == "${w2}x$h2" ]] || return 0
  fzx::_kv_get "$root_dir/state/current" current || return 0
  sock="${root_dir%/*}/$current/fzf.sock"
  [[ -S "$sock" ]] || return 0
  printf -v cmd 'transform:%q _cb nav relayout' "$FZX_BIN"
  command curl -s -m 2 --unix-socket "$sock" -X POST http://localhost --data-binary "$cmd" > /dev/null 2>&1 || :
}

fzx::_mode_valid() {
  local m
  for m in "${FZX_MODES[@]}"; do
    [[ "$m" == "$1" ]] && return 0
  done
  fzx::_mode_hidden "$1"
}

# fzx::_mode_hidden <mode>: a mode row flagged hidden (lib/components.sh)
fzx::_mode_hidden() {
  local m
  for m in "${FZX_MODES_HIDDEN[@]}"; do
    [[ "$m" == "$1" ]] && return 0
  done
  return 1
}

# fzx::_escdelay: export FZX_ESCDELAY as ESCDELAY, how long fzf waits after esc for the rest of an alt key or
# arrow sequence (its default, 100ms, is the delay before esc acts); empty leaves fzf's own
fzx::_escdelay() {
  [[ "${FZX_ESCDELAY:-}" =~ ^[0-9]+$ ]] && export ESCDELAY="$FZX_ESCDELAY"
  return 0
}

# The owner runs fzf as a child so it can clean up when the become() chain ends. Every other launch
# (resume, mode restart, navigation) execs fzf: otherwise each become() would leave one more waiting
# bash process behind it and the process chain would grow with every navigation.
fzx::_fzf() {
  local start end rc
  if [[ -z "${_FZX_OWNER:-}" && -z "${FZX_STANDALONE:-}" ]]; then
    fzx::log info "fzf exec module=$FZX_MODULE mode=$FZX_MODE opts=${#FZX_OPTS[@]}"
    fzx::_escdelay
    exec fzf "${FZX_OPTS[@]}" < /dev/null
  fi
  fzx::now_ms start
  local p=inline
  [[ -z "${FZX_STANDALONE:-}" ]] && fzx::placement p
  if [[ "$p" == split:* ]]; then
    fzx::log info "fzf start in a split ($p) module=$FZX_MODULE mode=$FZX_MODE"
    fzx::_fzf_split "${p#split:}"
  elif [[ "$p" == float || "$p" == float:* ]]; then
    fzx::log info "fzf start in a floating pane ($p) module=$FZX_MODULE mode=$FZX_MODE"
    fzx::_fzf_float "${p#float}"
  else
    fzx::log info "fzf start module=$FZX_MODULE mode=$FZX_MODE opts=${#FZX_OPTS[@]}"
    fzx::_escdelay
    fzf "${FZX_OPTS[@]}" < /dev/null
  fi
  rc=$?
  fzx::now_ms end
  fzx::log info "fzf exit rc=$rc $((end - start))ms"
  return "$rc"
}

# fzx::_fzf_split <DIR[,SIZE]>: run the current session in a new tmux split pane (fzx::_fzf_pane)
fzx::_fzf_split() {
  local spec="$1" dir size flags=()
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
  fzx::_fzf_pane split-window "${flags[@]}"
}

# fzx::window_size <wvar> <hvar>: the size popups and floats are measured against: the tmux window (they
# cover its split panes, so the calling pane's size would undersize them), else the terminal. Fails when
# neither is known.
fzx::window_size() {
  local _w="" _h=""
  if [[ -n "${TMUX:-}" ]]; then
    read -r _w _h < <(tmux display-message -p '#{window_width} #{window_height}' 2> /dev/null) || :
  fi
  if ! [[ "$_w" =~ ^[0-9]+$ && "$_h" =~ ^[0-9]+$ ]]; then
    _w="${COLUMNS:-}" _h="${LINES:-}"
    [[ "$_w" =~ ^[0-9]+$ ]] || _w="$(tput cols 2> /dev/null)"
    [[ "$_h" =~ ^[0-9]+$ ]] || _h="$(tput lines 2> /dev/null)"
  fi
  [[ "$_w" =~ ^[0-9]+$ && "$_h" =~ ^[0-9]+$ ]] || return 1
  printf -v "$1" '%s' "$_w"
  printf -v "$2" '%s' "$_h"
}

# fzx::popup_opts <popup|float> <var>: the --popup spec for a plain popup or float: FZX_POPUP_OPTS /
# FZX_FLOAT_OPTS when set (one fixed spec, the user's override), else the FZX_POPUP_LAYOUTS entry for the
# window's width (fzx::window_size), else center,80% (no layouts, an unknown width or no entry fits). An
# explicit popup:OPTS / float:OPTS skips this.
fzx::popup_opts() {
  local _kind="$1" _var="$2" _ww _wh _entry _spec=center,80% _fixed
  if [[ "$_kind" == float ]]; then _fixed="${FZX_FLOAT_OPTS:-}"; else _fixed="${FZX_POPUP_OPTS:-}"; fi
  if [[ -n "$_fixed" ]]; then
    _spec="$_fixed"
  elif ((${#FZX_POPUP_LAYOUTS[@]})) && fzx::window_size _ww _wh; then
    fzx::require layout
    if fzx::breakpoint_pick "$_ww" _entry "${FZX_POPUP_LAYOUTS[@]}"; then
      _spec="${_entry#*:}"
      fzx::log debug "popup layout for a ${_ww}-column window: $_entry"
    fi
  fi
  printf -v "$_var" '%s' "$_spec"
}

# fzx::_fzf_float <:OPTS|"">: run the current session in a new floating tmux pane (tmux new-pane), placed
# like fzf's --popup: [center|top|bottom|left|right][,W[%]][,H[%]], default fzx::popup_opts
fzx::_fzf_float() {
  local spec="${1#:}" geo ww wh
  [[ -n "$spec" ]] || fzx::popup_opts float spec
  if ! read -r ww wh < <(tmux display-message -p '#{window_width} #{window_height}' 2> /dev/null) ||
    ! fzx::float_geometry "$spec" "$ww" "$wh" geo; then
    fzx::log error "bad float options or no window size: $spec"
    printf 'fzx: bad float options: %s\n' "$spec" >&2
    return 2
  fi
  # the float follows the window: the resize hook, and what its geometry was made for (fzx::_nav_relayout
  # resizes and moves the pane in place when that changes); on the root, since the pane is the tree's
  local root_dir
  fzx::_root_dir root_dir
  fzx::_kv_set "$root_dir/state/float_geometry" "$spec ${ww}x$wh"
  fzx::_resize_hook_set
  # shellcheck disable=SC2086  # geo is "-x W -y H -X X -Y Y", numbers only
  fzx::_fzf_pane new-pane $geo
  local rc=$?
  rm -f -- "$root_dir/state/float_pane" "$root_dir/state/float_geometry"
  return "$rc"
}

# fzx::_root_dir <var>: the session tree's root directory
fzx::_root_dir() {
  local _r
  fzx::meta_get root _r || _r="$FZX_SESSION"
  printf -v "$1" '%s' "$FZX_SESSIONS_DIR/$_r"
}

# fzx::float_follow <spec>: in a float (the root's state/float_pane), resize and move the pane for the
# window's size now, when that differs from what it was made for; fzf redraws on the resize. Fails when
# this tree has no float
fzx::float_follow() {
  local spec="$1" root_dir pane old="" ww wh geo w h x y
  fzx::_root_dir root_dir
  fzx::_kv_get "$root_dir/state/float_pane" pane || return 1
  fzx::window_size ww wh || return 1
  fzx::_kv_get "$root_dir/state/float_geometry" old || :
  [[ "$old" == "$spec ${ww}x$wh" ]] && return 0
  fzx::float_geometry "$spec" "$ww" "$wh" geo || return 1
  read -r _ w _ h _ x _ y <<< "$geo"
  fzx::log info "float follows the window: ${old:-?} -> $spec ${ww}x$wh ($geo)"
  tmux resize-pane -t "$pane" -x "$w" -y "$h" 2>> "$FZX_LOG_FILE" &&
    tmux move-pane -t "$pane" -X "$x" -Y "$y" 2>> "$FZX_LOG_FILE" || return 1
  fzx::_kv_set "$root_dir/state/float_geometry" "$spec ${ww}x$wh"
}

# fzx::float_geometry <spec> <window width> <window height> <var>: new-pane's "-x W -y H -X X -Y Y" in cells
# for a spec in fzf's --popup syntax, border included. One size is both sides at the center, the width on the left or
# right (full height) and the height at the top or bottom (full width).
fzx::float_geometry() {
  local _spec="$1" _ww="$2" _wh="$3" _pos=center _sizes=() _t _w _h _x _y
  local IFS=,
  for _t in $_spec; do
    case "$_t" in
      center | top | bottom | left | right) _pos="$_t" ;;
      border-native | "") ;;
      *[0-9] | *[0-9]%) _sizes+=("$_t") ;;
      *) return 1 ;;
    esac
  done
  unset IFS
  case "$_pos:${#_sizes[@]}" in
    *:0) _w=50% _h=50% ;;
    center:1) _w="${_sizes[0]}" _h="${_sizes[0]}" ;;
    left:1 | right:1) _w="${_sizes[0]}" _h=100% ;;
    top:1 | bottom:1) _w=100% _h="${_sizes[0]}" ;;
    *) _w="${_sizes[0]}" _h="${_sizes[1]}" ;;
  esac
  [[ "$_w" == *% ]] && _w=$((_ww * ${_w%\%} / 100))
  [[ "$_h" == *% ]] && _h=$((_wh * ${_h%\%} / 100))
  # the spec sizes what is inside, as fzf's popup does; new-pane's border takes a cell on each side
  _w=$((_w + 2)) _h=$((_h + 2))
  ((_w > _ww)) && _w="$_ww"
  ((_h > _wh)) && _h="$_wh"
  _x=$(((_ww - _w) / 2)) _y=$(((_wh - _h) / 2))
  case "$_pos" in
    left) _x=0 ;;
    right) _x=$((_ww - _w)) ;;
    top) _y=0 ;;
    bottom) _y=$((_wh - _h)) ;;
  esac
  printf -v "$4" -- '-x %s -y %s -X %s -Y %s' "$_w" "$_h" "$_x" "$_y"
}

# fzx::_fzf_pane <tmux command> [flags...]: run the current session in the tmux pane that command makes
# (split-window, new-pane) and wait for it; its output becomes ours. fzf-tmux is not used: it passes only
# TERM and the FZF_* options into the pane, and the callbacks need the whole environment (FZX_SESSION, the
# directories, module settings). The pane runs `fzx --resume` (not the owner, so it execs fzf, and become()
# keeps working inside the pane).
fzx::_fzf_pane() {
  local tmux_cmd="$1" pane rc=130 base="$FZX_SESSION_DIR/split" cmd
  shift
  rm -f -- "$base".out "$base".rc
  # the pane inherits tmux's environment, not ours: replay our exported variables there
  export -p | grep -vE '^declare -x (PWD|OLDPWD|SHLVL|TMUX_PANE|_)=' > "$base.env"
  printf -v cmd 'source %q; %q --resume %q > %q; echo $? > %q' \
    "$base.env" "$FZX_BIN" "$FZX_SESSION" "$base.out" "$base.rc"
  if ! pane="$(tmux "$tmux_cmd" -P -F '#{pane_id}' -c "$PWD" "$@" "bash -c $(printf '%q' "$cmd")")"; then
    fzx::log error "tmux $tmux_cmd failed, running inline"
    fzf "${FZX_OPTS[@]}" < /dev/null
    return
  fi
  fzx::log info "$tmux_cmd pane $pane"
  if [[ "$tmux_cmd" == new-pane ]]; then
    local _rd
    fzx::_root_dir _rd
    fzx::_kv_set "$_rd/state/float_pane" "$pane"
  fi
  # until the pane reports, or disappears (closed by hand)
  while [[ ! -s "$base.rc" ]] && tmux list-panes -a -F '#{pane_id}' 2> /dev/null | grep -qxF -- "$pane"; do
    sleep 0.1
  done
  [[ -s "$base.rc" ]] && rc="$(< "$base.rc")"
  [[ -f "$base.out" ]] && cat -- "$base.out"
  rm -f -- "$base".out "$base".rc "$base".env
  return "$rc"
}
