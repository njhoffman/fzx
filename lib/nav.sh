#!/usr/bin/env bash
# nav: mode switching inside a running fzf, and navigation between sessions through become().
# Both run as `transform` callbacks: they print fzf actions on stdout.

# fzx::nav_mode <next|prev|NAME>: switch mode in place (fzf keeps running and keeps the query),
# or restart fzf when the module asks for it
fzx::nav_mode() {
  local target="${1:-next}" current mode label hints i n idx=0
  fzx::require config opts
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

  # optional <module>::mode_restart <from> <to> in module.sh: return 0 when the new mode needs
  # options that cannot change while fzf runs (sorting, delimiter, header lines); fzf then restarts
  # through become() with the query kept
  # shellcheck source=/dev/null
  source "$FZX_MODULE_DIR/module.sh" || return 1
  if declare -F "$FZX_MODULE::mode_restart" > /dev/null && "$FZX_MODULE::mode_restart" "$current" "$mode"; then
    fzx::state_set query "${FZF_QUERY:-}"
    fzx::state_set pos 1
    fzx::log info "mode $current -> $mode (restart)"
    _FZX_STAT=(mode - "$current>$mode:restart" "$current")
    fzx::_nav_become "$FZX_SESSION" "$mode"
    return
  fi

  fzx::state_set mode "$mode"
  export FZX_MODE="$mode"
  fzx::config_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  fzx::session_label label
  fzx::mode_hints hints "$mode"

  fzx::log info "mode $current -> $mode"
  _FZX_STAT=(mode - "$current>$mode" "$current")
  printf 'change-border-label( %s )+change-footer(%s)+reload:%s' "$label" "$hints" "$(fzx::cb load)"
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
