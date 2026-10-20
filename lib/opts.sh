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

# fzx::opts_build <module>; expects config loaded, module.sh sourced, FZX_MODES and FZX_MODE set
fzx::opts_build() {
  local module="$1" label hints query pos
  FZX_OPTS=("${FZX_FZF_OPTS[@]}")
  FZX_OPTS+=(
    --bind "start:reload:$(fzx::cb load)"
    --bind "${FZX_KEYS[reload_hard]}:reload:$(fzx::cb source)"
  )

  if fzx::in_session; then
    fzx::session_label label
    FZX_OPTS+=(
      "--listen=$FZX_SESSION_DIR/fzf.sock"
      "--border-label= $label "
      --bind "${FZX_KEYS[reload_soft]}:transform:$(fzx::cb nav resume)"
      --bind "${FZX_KEYS[back]}:transform:$(fzx::cb nav back)"
    )
    if ((${#FZX_MODES[@]} > 1)); then
      fzx::mode_hints hints "$FZX_MODE"
      FZX_OPTS+=(
        "--footer=$hints"
        --bind "${FZX_KEYS[mode_next]}:transform:$(fzx::cb mode next)"
        --bind "${FZX_KEYS[mode_prev]}:transform:$(fzx::cb mode prev)"
      )
    fi
    # restore what the previous interface of this session saved before become()
    fzx::state_get query query && [[ -n "$query" ]] && FZX_OPTS+=("--query=$query")
    fzx::state_get pos pos && [[ "$pos" =~ ^[0-9]+$ ]] && ((pos > 1)) &&
      FZX_OPTS+=(--bind "load:pos($pos)+unbind(load)")
  else
    FZX_OPTS+=("--border-label= $module${FZX_MODE:+:$FZX_MODE} ")
  fi

  if declare -F "$module::opts" > /dev/null; then
    "$module::opts" || return 1
  fi
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
