#!/usr/bin/env bash
# nav: mode switching inside a running fzf, and navigation between sessions through become().
# Both run as `transform` callbacks: they print fzf actions on stdout.

# fzx::nav_mode <next|prev|NAME>: switch mode in place (fzf keeps running and keeps the query),
# or restart fzf when the module asks for it
fzx::nav_mode() {
  local target="${1:-next}" current mode i n idx=0
  fzx::require config opts components
  # the table first: session_modes (the modes recorded at launch) is what the switch cycles through
  fzx::comp_load_session
  fzx::session_modes
  n="${#FZX_MODES[@]}"
  ((n > 1)) || return 0
  fzx::session_mode current
  for ((i = 0; i < n; i++)); do
    [[ "${FZX_MODES[i]}" == "$current" ]] && idx="$i"
  done

  case "$target" in
    next) mode="${FZX_MODES[(idx + 1) % n]}" ;;
    prev) mode="${FZX_MODES[(idx - 1 + n) % n]}" ;;
    *)
      mode=""
      for ((i = 0; i < n; i++)); do
        [[ "${FZX_MODES[i]}" == "$target" ]] && mode="$target"
      done
      if [[ -z "$mode" ]]; then
        fzx::log error "unknown mode for $FZX_MODULE: $target (modes: ${FZX_MODES[*]})"
        printf 'fzx: unknown mode: %s\n' "$target" >&2
        return 2
      fi
      ;;
  esac

  # a mode row flagged "restart" needs options that cannot change while fzf runs (sorting, delimiter,
  # header lines): entering or leaving it restarts fzf through become() with the query kept
  if fzx::comp_flag mode "$current" restart || fzx::comp_flag mode "$mode" restart; then
    fzx::state_set query "${FZF_QUERY:-}"
    fzx::state_set pos 1
    fzx::log info "mode $current -> $mode (restart)"
    _FZX_STAT=(mode - "$current>$mode:restart" "$current")
    fzx::_nav_become "$FZX_SESSION" "$mode"
    return
  fi

  fzx::state_set mode "$mode"
  export FZX_MODE="$mode"
  fzx::log info "mode $current -> $mode"
  _FZX_STAT=(mode - "$current>$mode" "$current")
  fzx::_nav_refresh
}

# in place after a mode, toggle or sort change: new label and component line, reload from the cache
# of the new view (or the source when that view was never loaded)
fzx::_nav_refresh() {
  local label line
  fzx::config_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  fzx::comp_current
  fzx::session_label label
  fzx::component_line line
  printf 'change-border-label( %s )+change-footer(%s)+reload:%s' "$label" "$line" "$(fzx::cb load)"
}

# shared tail of toggle/sort changes: a row flagged "restart" restarts fzf, otherwise refresh in place
fzx::_nav_apply() {
  local kind="$1" name="$2"
  if fzx::comp_flag "$kind" "$name" restart; then
    fzx::state_set query "${FZF_QUERY:-}"
    fzx::state_set pos 1
    fzx::_nav_become "$FZX_SESSION"
    return
  fi
  fzx::_nav_refresh
}

# fzx::nav_toggle <name>: flip a toggle
fzx::nav_toggle() {
  local name="${1:-}" on=() t found=0
  fzx::require config opts components
  fzx::comp_load_session
  fzx::session_modes
  fzx::session_mode FZX_MODE
  if ! fzx::comp_field toggle "$name" key _; then
    fzx::log error "unknown toggle for $FZX_MODULE: $name"
    printf 'fzx: unknown toggle: %s\n' "$name" >&2
    return 2
  fi
  fzx::comp_current
  for t in $FZX_TOGGLES; do
    if [[ "$t" == "$name" ]]; then found=1; else on+=("$t"); fi
  done
  ((found)) || on+=("$name")
  fzx::state_set toggles "${on[*]}"
  fzx::log info "toggle $name $( ((found)) && echo off || echo on)"
  _FZX_STAT=(toggle - "$name:$( ((found)) && echo off || echo on)" "$FZX_MODE")
  fzx::_nav_apply toggle "$name"
}

# fzx::nav_sort <next|prev|name>
fzx::nav_sort() {
  local target="${1:-next}" names=() i n idx=0 sort
  fzx::require config opts components
  fzx::comp_load_session
  fzx::session_modes
  fzx::session_mode FZX_MODE
  fzx::comp_current
  mapfile -t names < <(fzx::comp_rows sort | cut -f2)
  n="${#names[@]}"
  ((n > 0)) || return 0
  for ((i = 0; i < n; i++)); do
    [[ "${names[i]}" == "$FZX_SORT" ]] && idx="$i"
  done
  case "$target" in
    next) sort="${names[(idx + 1) % n]}" ;;
    prev) sort="${names[(idx - 1 + n) % n]}" ;;
    *)
      if ! fzx::comp_field sort "$target" key _; then
        fzx::log error "unknown sort for $FZX_MODULE: $target"
        printf 'fzx: unknown sort: %s\n' "$target" >&2
        return 2
      fi
      sort="$target"
      ;;
  esac
  fzx::state_set sort "$sort"
  fzx::log info "sort $FZX_SORT -> $sort"
  _FZX_STAT=(sort - "$FZX_SORT>$sort" "$FZX_MODE")
  fzx::_nav_apply sort "$sort"
}

# fzx::nav <resume | back | popout | goto <module[:mode]> [module args...] | entry <module>#<n>>
# Saves the query and cursor position of the current session, then prints become() into the target.
fzx::nav() {
  local action="${1:-}"
  shift
  fzx::state_set query "${FZF_QUERY:-}"
  fzx::state_set pos "${FZF_POS:-1}"

  case "$action" in
    resume)
      _FZX_STAT=(nav - resume)
      fzx::_nav_become "$FZX_SESSION"
      ;;
    back) fzx::_nav_back ;;
    popout) fzx::_nav_popout ;;
    goto) fzx::_nav_goto "$@" ;;
    entry) fzx::_nav_entry "$@" ;;
    *)
      fzx::log error "unknown nav action: $action"
      printf 'fzx: unknown nav action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

# fzx::_nav_become <sid> [mode]
fzx::_nav_become() {
  local cmd
  printf -v cmd '%q --resume %q' "$FZX_BIN" "$1"
  [[ -n "${2:-}" ]] && printf -v cmd '%s -m %q' "$cmd" ":$2"
  printf 'become:%s' "$cmd"
}

# resume the parent session; at the root there is nowhere to go
fzx::_nav_back() {
  local parent
  if fzx::meta_get parent parent && [[ -d "$FZX_SESSIONS_DIR/$parent/meta" ]]; then
    fzx::log info "nav back -> $parent"
    _FZX_STAT=(nav - back)
    fzx::_nav_become "$parent"
  else
    _FZX_STAT=(nav - back:none)
    printf 'bell'
  fi
}

# toggle the session tree between inline and a tmux/Zellij floating pane, then restart into it
fzx::_nav_popout() {
  local root root_dir popup=""
  if [[ -z "${TMUX:-}" && -z "${ZELLIJ:-}" ]]; then
    fzx::log info "nav popout: not inside tmux or Zellij"
    printf 'bell'
    return 0
  fi
  fzx::meta_get root root || root="$FZX_SESSION"
  root_dir="$FZX_SESSIONS_DIR/$root"
  fzx::_kv_get "$root_dir/state/popup" popup || :
  if [[ -n "$popup" ]]; then
    rm -f -- "$root_dir/state/popup"
    fzx::log info "nav popout: back inline"
    _FZX_STAT=(nav - popout:in)
  else
    fzx::_kv_set "$root_dir/state/popup" default
    fzx::log info "nav popout: into a popup"
    _FZX_STAT=(nav - popout:out)
  fi
  fzx::_nav_become "$FZX_SESSION"
}

# go to the n-th entry of a module's manifest (what the menu opens)
fzx::_nav_entry() {
  local id="${1:-}" module n dir
  module="${id%%#*}"
  n="${id#*#}"
  if [[ "$id" != *#* || ! "$n" =~ ^[0-9]+$ ]] || ! dir="$(fzx::module_find "$module")"; then
    fzx::log error "nav entry: bad entry id: $id"
    printf 'fzx: bad entry id: %s\n' "$id" >&2
    return 2
  fi
  fzx::require menu
  if ! fzx::menu_entries "$module" "$dir" 2>> "$FZX_LOG_FILE" || ((n >= ${#FZX_ENTRY_TARGETS[@]})); then
    fzx::log error "nav entry: no entry $id"
    printf 'fzx: no entry %s\n' "$id" >&2
    return 2
  fi
  fzx::menu_entry_args "$n"
  fzx::_nav_goto "${FZX_ENTRY_TARGETS[n]}" "${FZX_ARGS[@]}"
}

# go to a child session for <module> with these args, reusing it when one already exists
fzx::_nav_goto() {
  local target="${1:-}" module mode="" dir key child="" parent="$FZX_SESSION"
  shift
  module="${target%%:*}"
  [[ "$target" == *:* ]] && mode="${target#*:}"
  if ! dir="$(fzx::module_find "$module")"; then
    fzx::log error "nav goto: module not found: $module"
    printf 'fzx: module not found: %s\n' "$module" >&2
    return 2
  fi

  key="$(printf '%s\0' "$module" "$@" | md5sum)"
  key="${key%% *}"
  local index="$FZX_SESSION_DIR/children/$key"
  if fzx::_kv_get "$index" child && [[ -d "$FZX_SESSIONS_DIR/$child/meta" ]]; then
    fzx::log info "nav goto $target $* -> existing $child"
  else
    fzx::session_create_child "$module" "$dir" "$@" || return 1
    child="$FZX_SESSION"
    fzx::_kv_set "$index" "$child"
    # the stats row and log belong to the session the user navigated from
    fzx::session_attach "$parent"
  fi
  _FZX_STAT=(nav - "goto:$target")
  fzx::_nav_become "$child" "$mode"
}
