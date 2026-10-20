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

# fzx::component_line <var>: modes (when there is more than one), toggles and the sort key as one line in
# FZX_HEADER_STYLE, active ones highlighted; empty when the module has none of them or the style is none
# (locals _-prefixed: they would shadow the caller's variable)
fzx::component_line() {
  local _items=() _m _k _n _line="" _style="${FZX_HEADER_STYLE:-minimal}"
  [[ "$_style" == none ]] && { printf -v "$1" '%s' ""; return; }
  # items as "group<TAB>state<TAB>kind<TAB>text"; state is on or off
  if ((${#FZX_MODES[@]} > 1)); then
    for _m in "${FZX_MODES[@]}"; do
      if [[ "$_m" == "$FZX_MODE" ]]; then _items+=($'1\ton\tmode\t'"$_m"); else _items+=($'1\toff\tmode\t'"$_m"); fi
    done
  fi
  while IFS=$'\t' read -r _k _n _ _ _; do
    if fzx::comp_on "$_n"; then _items+=($'2\ton\ttoggle\t'"$_n"); else _items+=($'2\toff\ttoggle\t'"$_n"); fi
  done < <(fzx::comp_rows toggle)
  [[ -n "${FZX_SORT:-}" ]] && _items+=($'3\ton\tsort\t↓'"$FZX_SORT")
  ((${#_items[@]})) || { printf -v "$1" '%s' ""; return; }
  case "$_style" in
    bubble | triangle) fzx::_component_pills _line "$_style" "${_items[@]}" ;;
    *) fzx::_component_minimal _line "${_items[@]}" ;;
  esac
  printf -v "$1" '%s' "$_line"
}

# minimal: colored text per kind, groups separated by a dim bar
fzx::_component_minimal() {
  local _out="" _prev="" _it _g _s _k _t _c _r=$'\e[0m'
  local _var="$1"
  shift
  for _it in "$@"; do
    IFS=$'\t' read -r _g _s _k _t <<< "$_it"
    case "$_k:$_s" in
      mode:on) _c="${FZX_COLORS[mode_active]}" ;;
      toggle:on) _c="${FZX_COLORS[toggle_on]}" ;;
      toggle:off) _c="${FZX_COLORS[toggle_off]}" ;;
      sort:*) _c="${FZX_COLORS[sort]}" ;;
      *) _c="${FZX_COLORS[mode_inactive]}" ;;
    esac
    if [[ -z "$_prev" ]]; then :
    elif [[ "$_g" != "$_prev" ]]; then _out+=$'\e['"${FZX_COLORS[mode_inactive]}m  |  $_r"
    else _out+="  "; fi
    _out+=$'\e['"${_c}m$_t$_r"
    _prev="$_g"
  done
  printf -v "$_var" '%s' "$_out"
}

# bubble: each item a rounded pill; triangle: one powerline, an arrow between items. Colors from
# FZX_COLORS[pill_on|pill_off] (background) and [pill_on_fg|pill_off_fg] (text), 256-color numbers.
fzx::_component_pills() {
  local _var="$1" _style="$2" _out="" _prev="" _it _g _s _k _t _bg _fg _pbg="" _r=$'\e[0m'
  local _left=$'' _right=$'' _arrow=$''
  shift 2
  for _it in "$@"; do
    IFS=$'\t' read -r _g _s _k _t <<< "$_it"
    _bg="${FZX_COLORS[pill_$_s]}" _fg="${FZX_COLORS[pill_${_s}_fg]}"
    if [[ "$_style" == bubble ]]; then
      if [[ -z "$_prev" ]]; then :; elif [[ "$_g" != "$_prev" ]]; then _out+="   "; else _out+=" "; fi
      _out+=$'\e[38;5;'"${_bg}m$_left"$'\e[48;5;'"$_bg;38;5;${_fg}m$_t$_r"$'\e[38;5;'"${_bg}m$_right$_r"
    else
      # the arrow takes the previous item's background as its color, over this item's background
      [[ -n "$_pbg" ]] && _out+=$'\e[38;5;'"$_pbg;48;5;${_bg}m$_arrow"
      _out+=$'\e[48;5;'"$_bg;38;5;${_fg}m $_t "
      _pbg="$_bg"
    fi
    _prev="$_g"
  done
  [[ "$_style" == triangle ]] && _out+="$_r"$'\e[38;5;'"${_pbg}m$_arrow$_r"
  printf -v "$_var" '%s' "$_out"
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
  local module="$1" label query pos
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
      fzx::bind "${FZX_KEYS[mode_next]}" "transform:$(fzx::cb mode next)" "next mode"
      fzx::bind "${FZX_KEYS[mode_prev]}" "transform:$(fzx::cb mode prev)" "previous mode"
      # a mode row with a key jumps straight to that mode
      local _row _k _n _key _desc _flags
      while IFS=$'\t' read -r _k _n _key _desc _flags; do
        [[ -n "$_key" && "$_key" != - ]] || continue
        _FZX_BIND_SCOPE="$module" fzx::bind "$_key" "transform:$(fzx::cb mode "$_n")" "mode: ${_desc:-$_n}"
      done < <(fzx::comp_rows mode)
    fi
    # toggles with a key flip in place; sort keys cycle (and a sort row with a key selects it)
    while IFS=$'\t' read -r _k _n _key _desc _flags; do
      [[ -n "$_key" && "$_key" != - ]] || continue
      _FZX_BIND_SCOPE="$module" fzx::bind "$_key" "transform:$(fzx::cb toggle "$_n")" "toggle: ${_desc:-$_n}"
    done < <(fzx::comp_rows toggle)
    if (($(fzx::comp_rows sort | wc -l) > 1)); then
      fzx::bind "${FZX_KEYS[sort_next]}" "transform:$(fzx::cb sort next)" "next sort order"
      fzx::bind "${FZX_KEYS[sort_prev]}" "transform:$(fzx::cb sort prev)" "previous sort order"
      while IFS=$'\t' read -r _k _n _key _desc _flags; do
        [[ -n "$_key" && "$_key" != - ]] || continue
        _FZX_BIND_SCOPE="$module" fzx::bind "$_key" "transform:$(fzx::cb sort "$_n")" "sort: ${_desc:-$_n}"
      done < <(fzx::comp_rows sort)
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
  fzx::_component_place
  # debug view in the preview; standalone has no session, so only the variables
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[debug]}" "show-preview+preview:$(fzx::cb debug {})" "debug: session state and FZF_* variables"
  else
    fzx::bind "${FZX_KEYS[debug]}" "show-preview+preview:env | grep -E '^(FZX|FZF)_' | sort" "debug: FZX_* and FZF_* variables"
  fi
  FZX_HELP+=("fzx"$'\t'"${FZX_KEYS[help]}"$'\t'"this help")
  fzx::_help_bind "$module"
}

# put the component line in the footer, or in the header above the module's own header (which is kept
# in meta/header for the in-place refreshes)
fzx::_component_place() {
  local line i h=""
  fzx::component_line line
  if [[ "${FZX_HEADER_POSITION:-footer}" == header ]]; then
    for ((i = ${#FZX_OPTS[@]} - 1; i >= 0; i--)); do
      if [[ "${FZX_OPTS[i]}" == --header=* ]]; then
        h="${FZX_OPTS[i]#--header=}"
        unset 'FZX_OPTS[i]'
        FZX_OPTS=("${FZX_OPTS[@]}")
        break
      fi
    done
    fzx::in_session && fzx::meta_set header "$h"
    [[ -n "$line$h" ]] && FZX_OPTS+=("--header=$line${line:+${h:+$'\n'}}$h")
  elif [[ -n "$line" ]]; then
    FZX_OPTS+=("--footer=$line")
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
