#!/usr/bin/env bash
# opts: build the fzf argument array (FZX_OPTS) from config, core bindings and the module hook.

# fzx::cb <verb> [args / fzf placeholders...]: shell command string for a bind or preview.
# Under fzx it routes through `fzx _cb`; standalone it calls the module scripts directly, and the
# session-only verbs (mode, nav) are unavailable.
# Arguments are appended unquoted so fzf can substitute placeholders ({1}, {+1}, {q}).
fzx::cb() {
  local verb="$1" cmd
  shift
  if [[ -n "${FZX_STANDALONE:-}" ]]; then
    case "$verb" in
      load | source) printf -v cmd '%q ' "$FZX_MODULE_DIR/source.sh" "${FZX_ARGS[@]}" ;;
      preview) printf -v cmd '%q ' "$FZX_MODULE_DIR/preview.sh" ;;
      action) printf -v cmd '%q ' "$FZX_MODULE_DIR/actions.sh" ;;
      *)
        printf 'fzx: callback verb not available standalone: %s\n' "$verb" >&2
        return 1
        ;;
    esac
  else
    printf -v cmd '%q _cb %s ' "$FZX_BIN" "$verb"
  fi
  cmd+="$*"
  printf '%s' "${cmd% }"
}

# fzx::mode_hints <var> <active mode>: mode names with the active one highlighted; expects FZX_MODES
# (locals are _-prefixed so they cannot shadow the caller's variable)
fzx::mode_hints() {
  local _m _hints="" _on=$'\e['"${FZX_COLORS[mode_active]}m" _off=$'\e['"${FZX_COLORS[mode_inactive]}m"
  for _m in "${FZX_MODES[@]}"; do
    if [[ "$_m" == "$2" ]]; then
      _hints+="${_hints:+  }$_on$_m"$'\e[0m'
    else
      _hints+="${_hints:+  }$_off$_m"$'\e[0m'
    fi
  done
  printf -v "$1" '%s' "$_hints"
}

# fzx::bind <key> <action> <description>: add a key binding and record it for the help key (f1).
# Bindings made while the module's opts hook runs are listed as the module's, the rest as fzx's.
fzx::bind() {
  local _e
  for _e in "${FZX_HELP[@]}"; do
    [[ "$_e" == *$'\t'"$1"$'\t'* ]] &&
      fzx::log warn "key $1 is bound twice (${_e##*$'\t'} / $3); the later binding wins"
  done
  FZX_OPTS+=(--bind "$1:$2")
  FZX_HELP+=("${_FZX_BIND_SCOPE:-fzx}"$'\t'"$1"$'\t'"$3")
}

# fzx::key_hints <var>: "key description" pairs of the module's bindings, for a header
fzx::key_hints() {
  local _entry _scope _key _desc _hints=""
  for _entry in "${FZX_HELP[@]}"; do
    IFS=$'\t' read -r _scope _key _desc <<< "$_entry"
    [[ "$_scope" == fzx ]] && continue
    _hints+="${_hints:+  }$_key $_desc"
  done
  printf -v "$1" '%s' "$_hints"
}

# the help key: show-preview, then a preview command that prints every recorded binding. The text is
# part of the binding itself, so help needs no callback and works standalone as well.
fzx::_help_bind() {
  local module="$1" entry scope _s key desc last="" lines=() cmd b=$'\e[1m' r=$'\e[0m'
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m"
  for scope in "$module" fzx; do
    last=""
    for entry in "${FZX_HELP[@]}"; do
      IFS=$'\t' read -r _s key desc <<< "$entry"
      [[ "$_s" == "$scope" ]] || continue
      [[ -n "$last" ]] || lines+=("" "$b$scope keys$r")
      last=1
      lines+=("$(printf '  %-12s %s' "$key" "$desc")")
    done
  done
  # components from the table: modes (and, as they are added, toggles, sort keys, actions)
  local _kind _row _k _n _key _desc _fl _title
  for _kind in mode toggle sort action; do
    _title=""
    while IFS=$'\t' read -r _k _n _key _desc _fl; do
      [[ -n "$_title" ]] || { _title=1; lines+=("" "$b${_kind}s$r"); }
      [[ "$_key" == - ]] && _key=""
      lines+=("$(printf '  %-12s %-12s %s' "$_n" "$_key" "${_desc#-}")")
    done < <(fzx::comp_rows "$_kind" 2> /dev/null)
  done
  lines+=("" "${d}any cursor movement returns to the normal preview$r")
  printf -v cmd '%q ' "${lines[@]:1}"
  FZX_OPTS+=(--bind "${FZX_KEYS[help]}:show-preview+preview:printf '%s\\n' $cmd")
}

# fzx::opts_build <module>; expects config loaded, module.sh sourced, FZX_MODES and FZX_MODE set
fzx::opts_build() {
  local module="$1" label hints query pos
  FZX_OPTS=("${FZX_FZF_OPTS[@]}")
  FZX_HELP=()
  _FZX_BIND_SCOPE=fzx
  [[ -n "${FZX_FZF_COLORS:-}" ]] && FZX_OPTS+=("--color=$FZX_FZF_COLORS")
  if [[ "${FZX_HISTORY:-1}" == 1 ]]; then
    mkdir -p -- "$FZX_STATE_DIR/history"
    FZX_OPTS+=("--history=$FZX_STATE_DIR/history/$module")
  fi
  FZX_OPTS+=(--bind "start:reload:$(fzx::cb load)")
  fzx::bind "${FZX_KEYS[reload_hard]}" "reload:$(fzx::cb source)" "reload: run the source again"

  if fzx::in_session; then
    fzx::session_label label
    FZX_OPTS+=(
      "--listen=$FZX_SESSION_DIR/fzf.sock"
      "--border-label= $label "
    )
    fzx::bind "${FZX_KEYS[reload_soft]}" "transform:$(fzx::cb nav resume)" "restart the interface, data from cache"
    fzx::bind "${FZX_KEYS[back]}" "transform:$(fzx::cb nav back)" "back to the previous screen"
    fzx::bind "${FZX_KEYS[popout]}" "transform:$(fzx::cb nav popout)" "move into / out of a tmux popup"
    if ((${#FZX_MODES[@]} > 1)); then
      fzx::mode_hints hints "$FZX_MODE"
      FZX_OPTS+=("--footer=$hints")
      fzx::bind "${FZX_KEYS[mode_next]}" "transform:$(fzx::cb mode next)" "next mode"
      fzx::bind "${FZX_KEYS[mode_prev]}" "transform:$(fzx::cb mode prev)" "previous mode"
      # a mode row with a key jumps straight to that mode
      local _row _k _n _key _desc _flags
      while IFS=$'\t' read -r _k _n _key _desc _flags; do
        [[ -n "$_key" && "$_key" != - ]] || continue
        _FZX_BIND_SCOPE="$module" fzx::bind "$_key" "transform:$(fzx::cb mode "$_n")" "mode: ${_desc:-$_n}"
      done < <(fzx::comp_rows mode)
    fi
    # restore what the previous interface of this session saved before become()
    fzx::state_get query query && [[ -n "$query" ]] && FZX_OPTS+=("--query=$query")
    fzx::state_get pos pos && [[ "$pos" =~ ^[0-9]+$ ]] && ((pos > 1)) &&
      FZX_OPTS+=(--bind "load:pos($pos)+unbind(load)")
  else
    FZX_OPTS+=("--border-label= $module${FZX_MODE:+:$FZX_MODE} ")
  fi

  if declare -F "$module::opts" > /dev/null; then
    _FZX_BIND_SCOPE="$module"
    "$module::opts" || return 1
    _FZX_BIND_SCOPE=fzx
  fi
  # debug view in the preview; standalone has no session, so only the variables
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[debug]}" "show-preview+preview:$(fzx::cb debug {})" "debug: session state and FZF_* variables"
  else
    fzx::bind "${FZX_KEYS[debug]}" "show-preview+preview:env | grep -E '^(FZX|FZF)_' | sort" "debug: FZX_* and FZF_* variables"
  fi
  FZX_HELP+=("fzx"$'\t'"${FZX_KEYS[help]}"$'\t'"this help")
  fzx::_help_bind "$module"
}

# print FZX_OPTS as a readable, copy-pastable fzf command; a flag and its separate value share a line
fzx::opts_print() {
  local i opt sep
  printf 'fzf'
  for ((i = 0; i < ${#FZX_OPTS[@]}; i++)); do
    opt="${FZX_OPTS[i]}"
    sep=' \\\n  '
    ((i > 0)) && [[ "${FZX_OPTS[i - 1]}" == --* && "${FZX_OPTS[i - 1]}" != *=* && "$opt" != -* ]] && sep=' '
    if [[ "$opt" =~ ^[A-Za-z0-9_./=:,%+-]+$ ]]; then
      printf '%b%s' "$sep" "$opt"
    else
      printf '%b%s' "$sep" "${opt@Q}"
    fi
  done
  printf ' \\\n  < /dev/null\n'
}
