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

# fzx::prompt <loaded|loading> <var>: FZX_PROMPT / FZX_PROMPT_LOADING with the icon colored for that
# state; empty when the prompt is blank (fzf's own prompt is kept and no prompt actions are bound). The
# icon is the current mode's (FZX_ICON_MODES[$FZX_MODE]) when it has one, else FZX_ICON; a blank FZX_ICON
# keeps the prompt without one, mode icons included.
fzx::prompt() {
  local _t _c _icon="" _glyph="${FZX_ICON:-}"
  if [[ "$1" == loading ]]; then _t="${FZX_PROMPT_LOADING:-$FZX_PROMPT}" _c="${FZX_COLORS[prompt_loading]:-}"
  else _t="${FZX_PROMPT:-}" _c="${FZX_COLORS[prompt_loaded]:-}"; fi
  fzx::_has_mode_icons && [[ -n "$_glyph" && -n "${FZX_MODE:-}" ]] && _glyph="${FZX_ICON_MODES[$FZX_MODE]:-$_glyph}"
  [[ -n "$_glyph" ]] && _icon=$'\e['"${_c}m$_glyph"$'\e[0m'
  _t="${_t//\{icon\}/$_icon}"
  # ")" would end change-prompt(...) early
  _t="${_t//)/}"
  [[ "$_t" =~ [^[:space:]] ]] || _t=""
  printf -v "$2" '%s' "$_t"
}

# fzx::_has_mode_icons: the module gives some of its modes an icon of their own (FZX_ICON_MODES)
fzx::_has_mode_icons() {
  [[ "$(declare -p FZX_ICON_MODES 2> /dev/null)" == "declare -A"* ]] && ((${#FZX_ICON_MODES[@]}))
}

# fzx::_prompt_binds <loaded prompt>: what load switches the prompt to. With mode icons and a session, the
# loaded prompt of every mode goes into meta/prompt.<mode> and load asks `fzx _cb prompt` for the current
# one (an in-place mode switch cannot change a load bind); otherwise a fixed change-prompt.
fzx::_prompt_binds() {
  local _m _p _mode="${FZX_MODE:-}"
  [[ -n "$1" ]] || return 0
  if fzx::in_session && fzx::_has_mode_icons && ((${#FZX_MODES[@]} > 1)); then
    for _m in "${FZX_MODES[@]}"; do
      FZX_MODE="$_m"
      fzx::prompt loaded _p
      fzx::meta_set "prompt.$_m" "$_p"
    done
    FZX_MODE="$_mode"
    FZX_OPTS+=(--bind "load:transform-prompt:$(fzx::cb prompt)")
  else
    FZX_OPTS+=(--bind "load:change-prompt($1)")
  fi
}

# fzx::action_arg <action> <text> [var]: action(text) with a delimiter pair fzf accepts that the text does
# not close, into var when given, else printed; fails when the text holds every closing delimiter
fzx::action_arg() {
  local _d _out
  for _d in '()' '[]' '{}' '<>' '~~' '!!' '@@' '##' '$$' '%%' '^^' '&&' '**' ';;' '//' '||'; do
    [[ "$2" == *"${_d:1:1}"* ]] && continue
    _out="$1${_d:0:1}$2${_d:1:1}"
    if [[ -n "${3:-}" ]]; then printf -v "$3" '%s' "$_out"; else printf '%s' "$_out"; fi
    return 0
  done
  return 1
}

# fzx::reload_action <command> <var>: reload(command), switching the prompt to its loading form first
# (the load event switches it back)
fzx::reload_action() {
  local _p
  fzx::prompt loading _p
  printf -v "$2" '%sreload(%s)' "${_p:+change-prompt($_p)+}" "$1"
}

# fzx::_trace_binds: FZX_TRACE events log through a bg-transform callback, appended to the event's own
# binding with fzf's "event:+action" form
FZX_TRACE_EVENTS=(start load resize result result-final focus change one zero multi jump backward-eof)
fzx::_trace_binds() {
  local events=() ev
  [[ -n "${FZX_TRACE:-}" ]] && fzx::in_session || return 0
  if [[ "$FZX_TRACE" == all ]]; then events=("${FZX_TRACE_EVENTS[@]}"); else IFS=', ' read -ra events <<< "$FZX_TRACE"; fi
  for ev in "${events[@]}"; do
    [[ " ${FZX_TRACE_EVENTS[*]} " == *" $ev "* ]] || { fzx::log warn "FZX_TRACE: unknown event $ev"; continue; }
    FZX_OPTS+=(--bind "$ev:+bg-transform:$(fzx::cb trace "$ev")")
  done
}

# fzx::_layout_binds: FZX_PREVIEW_LAYOUTS into the session meta (the layout callback reads it there) and
# the start/resize callbacks that apply it; invalid entries are logged and skipped
fzx::_layout_binds() {
  local e valid=() joined
  fzx::in_session && ((${#FZX_PREVIEW_LAYOUTS[@]})) || return 0
  for e in "${FZX_PREVIEW_LAYOUTS[@]}"; do
    if [[ "$e" =~ ^[0-9]+: && "$e" != *$'\t'* ]]; then valid+=("$e"); else fzx::log warn "FZX_PREVIEW_LAYOUTS: bad entry ${e@Q} (want MINCOLS:SPEC)"; fi
  done
  ((${#valid[@]})) || return 0
  printf -v joined '%s\t' "${valid[@]}"
  fzx::meta_set preview_layouts "${joined%$'\t'}"
  FZX_OPTS+=(
    --bind "start:+transform:$(fzx::cb layout start)"
    --bind "resize:+transform:$(fzx::cb layout resize)"
  )
}

# fzx::component_style <var>: FZX_COMPONENT_STYLE, else the older FZX_HEADER_STYLE, else minimal; bubble
# is round's older name
fzx::component_style() {
  local _s="${FZX_COMPONENT_STYLE:-${FZX_HEADER_STYLE:-minimal}}"
  [[ "$_s" == bubble ]] && _s=round
  printf -v "$1" '%s' "$_s"
}

# fzx::component_line <var>: modes (when there is more than one), toggles and the sort key as one line in
# the component style, active ones highlighted; empty when the module has none of them or the style is none
# (locals _-prefixed: they would shadow the caller's variable)
fzx::component_line() {
  local _items=() _m _k _n _line="" _style _on="" _off="" _sort
  fzx::component_style _style
  [[ "$_style" == none ]] && { printf -v "$1" '%s' ""; return; }
  # the sort always carries its icon (lib/icons.sh; FZX_ICONS=none: ↓); toggles an on/off marker only in
  # the icon style, FZX_TOGGLE_ICONS picks it: switch (the icon set's) or dot
  fzx::require icons
  fzx::icon sort _sort
  if [[ "$_style" == icon && "${FZX_ICONS:-nerd}" != none ]]; then
    if [[ "${FZX_TOGGLE_ICONS:-switch}" == dot ]]; then _on="●" _off="○"
    else
      fzx::icon toggle_on _on
      fzx::icon toggle_off _off
    fi
  fi
  # items as "group<TAB>state<TAB>kind<TAB>text"; state is on or off
  if ((${#FZX_MODES[@]} > 1)); then
    for _m in "${FZX_MODES[@]}"; do
      if [[ "$_m" == "$FZX_MODE" ]]; then _items+=($'1\ton\tmode\t'"$_m"); else _items+=($'1\toff\tmode\t'"$_m"); fi
    done
  fi
  # the toggles this mode has (a row scoped to other modes does nothing here)
  local _toggles=()
  fzx::comp_toggle_names _toggles
  for _n in "${_toggles[@]}"; do
    if fzx::comp_on "$_n"; then _items+=($'2\ton\ttoggle\t'"${_on:+$_on }$_n"); else _items+=($'2\toff\ttoggle\t'"${_off:+$_off }$_n"); fi
  done
  [[ -n "${FZX_SORT:-}" ]] && _items+=($'3\ton\tsort\t'"${_sort:-↓} $FZX_SORT")
  ((${#_items[@]})) || { printf -v "$1" '%s' ""; return; }
  case "$_style" in
    round | triangle) fzx::_component_pills _line "$_style" "${_items[@]}" ;;
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

# round: each item a rounded pill; triangle: one powerline, an arrow between items. Colors from
# FZX_COLORS[pill_on|pill_off] (background) and [pill_on_fg|pill_off_fg] (text), 256-color numbers.
fzx::_component_pills() {
  local _var="$1" _style="$2" _out="" _prev="" _it _g _s _k _t _bg _fg _pbg="" _r=$'\e[0m'
  local _left=$'' _right=$'' _arrow=$''
  shift 2
  for _it in "$@"; do
    IFS=$'\t' read -r _g _s _k _t <<< "$_it"
    _bg="${FZX_COLORS[pill_$_s]}" _fg="${FZX_COLORS[pill_${_s}_fg]}"
    if [[ "$_style" == round ]]; then
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

# fzx::bind <key[,key...]> <action> <description>: add a key binding and record it for the help key (f1).
# Several keys (FZX_KEYS[back]="alt-left,ctrl-bspace") share the action; each is recorded and checked on
# its own. Bindings made while the module's opts hook runs are listed as the module's, the rest as fzx's.
# A module's binding on a key in FZX_RESERVED_KEYS is skipped (the other keys of the list are bound).
fzx::bind() {
  local _e _k _keys=() _ok=()
  fzx::split_keys "$1" _keys
  for _k in "${_keys[@]}"; do
    [[ -n "$_k" ]] || continue
    if [[ "${_FZX_BIND_SCOPE:-fzx}" != fzx && " ${FZX_RESERVED_KEYS[*]} " == *" $_k "* ]]; then
      fzx::log warn "key $_k is reserved (FZX_RESERVED_KEYS); not bound for ${_FZX_BIND_SCOPE}: $3"
      continue
    fi
    for _e in "${FZX_HELP[@]}"; do
      [[ "$_e" == *$'\t'"$_k"$'\t'* ]] &&
        fzx::log warn "key $_k is bound twice (${_e##*$'\t'} / $3); the later binding wins"
    done
    _ok+=("$_k")
  done
  # a --bind per key: fzf's own key lists cannot hold the comma key (alt-,)
  for _k in "${_ok[@]}"; do
    FZX_OPTS+=(--bind "$_k:$2")
    FZX_HELP+=("${_FZX_BIND_SCOPE:-fzx}"$'\t'"$_k"$'\t'"$3")
  done
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

# the help key: `fzx keys --toggle` with every recorded binding and component row as arguments answers
# show-preview and the page (lib/keys.sh draws it), or the grid when pressed again; no session needed, so
# help works standalone as well
fzx::_help_bind() {
  local module="$1"
  local entry args=("m:$module") seen=" " i key keys _k _n _key _desc _fl
  for entry in "${FZX_HELP[@]}"; do
    args+=("k:$entry")
    key="${entry#*$'\t'}"
    seen+="${key%%$'\t'*} "
  done
  # keys bound with a plain --bind (no fzx::bind, so no description) are the module's own
  for ((i = 1; i < ${#FZX_OPTS[@]}; i++)); do
    [[ "${FZX_OPTS[i - 1]}" == --bind ]] || continue
    local bkeys=()
    fzx::split_keys "${FZX_OPTS[i]%%:*}" bkeys
    for key in "${bkeys[@]}"; do
      [[ " ${FZX_TRACE_EVENTS[*]} " == *" $key "* || "$seen" == *" $key "* ]] && continue
      args+=("k:$module"$'\t'"$key"$'\t')
      seen+="$key "
    done
  done
  while IFS=$'\t' read -r _k _n _key _desc _fl; do
    args+=("c:$_k"$'\t'"$_n"$'\t'"$_key"$'\t'"${_desc#-}")
  done < <(fzx::comp_rows mode 2> /dev/null; fzx::comp_rows toggle 2> /dev/null; fzx::comp_rows sort 2> /dev/null
    fzx::comp_rows action 2> /dev/null)
  # pressed again while the page shows, the grid (`fzx keys --toggle` picks; lib/keys.sh)
  printf -v keys '%q ' "$FZX_BIN" keys --toggle "s:${FZX_KEY_STYLE:-full}" "${args[@]}"
  FZX_OPTS+=(--bind "${FZX_KEYS[help]}:transform:$keys")
}

# fzx::_taken_keys <var>: " key key ... " of every component row's keys and every FZX_KEYS value
fzx::_taken_keys() {
  local _row _k _n _key _rest _keys=() _all=" " _x
  for _row in "${FZX_COMP[@]}"; do
    IFS=$'\t' read -r _k _n _key _rest <<< "$_row"
    [[ -n "$_key" && "$_key" != - ]] || continue
    fzx::split_keys "$_key" _keys
    for _x in "${_keys[@]}"; do _all+="$_x "; done
  done
  for _key in "${FZX_KEYS[@]}"; do
    fzx::split_keys "$_key" _keys
    for _x in "${_keys[@]}"; do _all+="$_x "; done
  done
  printf -v "$1" '%s' "$_all"
}

# fzx::opts_build <module>; expects config loaded, module.sh sourced, FZX_MODES and FZX_MODE set
# fzx::title_paint <var> <module:mode>...: the border title of a path of screens, the last one the current:
# FZX_COLORS[title] for where it came from and the separator (FZX_ICONS' breadcrumb, else ">"),
# FZX_COLORS[title_current] for the current one. Empty colors leave fzf's label color alone.
fzx::title_paint() {
  local __tp_var="$1" __tp_sep="" __tp_out="" __tp_c __tp_n=$# __tp_i=1 __tp_r=$'\e[0m'
  shift
  fzx::require icons
  fzx::icon breadcrumb __tp_sep
  [[ -n "$__tp_sep" ]] || __tp_sep=">"
  local __tp_from="${FZX_COLORS[title]:-}" __tp_cur="${FZX_COLORS[title_current]:-}"
  [[ -n "${NO_COLOR:+x}" ]] && __tp_from="" __tp_cur=""
  [[ -n "$__tp_from" ]] && __tp_from=$'\e['"${__tp_from}m"
  [[ -n "$__tp_cur" ]] && __tp_cur=$'\e['"${__tp_cur}m"
  [[ -n "$__tp_from$__tp_cur" ]] || __tp_r=""
  for __tp_c; do
    __tp_i=$((__tp_i + 1))
    if ((__tp_i == __tp_n)); then
      __tp_out+="$__tp_cur$__tp_c$__tp_r"
    else
      __tp_out+="$__tp_from$__tp_c $__tp_sep $__tp_r"
    fi
  done
  printf -v "$__tp_var" '%s' "$__tp_out"
}

# fzx::session_title <var>: the session's path as the border title
fzx::session_title() {
  local _plain _parts=() _p
  fzx::session_label _plain
  while [[ "$_plain" == *" > "* ]]; do
    _parts+=("${_plain%% > *}")
    _plain="${_plain#* > }"
  done
  _parts+=("$_plain")
  fzx::title_paint "$1" "${_parts[@]}"
}

# fzx::_freeze_opts: --freeze-left, unless the module sets it. Where the display is a single field of
# --with-nth (id<TAB>display), the source's rows get it split (fzx::freeze_rows, recorded in meta/freeze):
# --with-nth=K,-1 shows the frozen part and the rest; --tabstop=1 makes the tab between them take the place of
# the space it replaced. Nothing moves in fields the bindings read. Multi-line items (--read0) and sessionless
# runs, whose rows do not pass through the callbacks, keep their fields.
fzx::_freeze_opts() {
  local _n="${FZX_FREEZE_LEFT:-1}" _i _at=-1 _k=""
  fzx::in_session && fzx::meta_set freeze ""
  [[ "$_n" != 0 ]] || return 0
  [[ " ${FZX_OPTS[*]} " == *" --freeze-left="* ]] || FZX_OPTS+=("--freeze-left=$_n")
  fzx::in_session && [[ "${FZX_READ0:-0}" != 1 ]] || return 0
  for ((_i = 0; _i < ${#FZX_OPTS[@]}; _i++)); do
    [[ "${FZX_OPTS[_i]}" =~ ^--with-nth=([0-9]+)(,[0-9,]+)?$ ]] && _at="$_i" _k="${BASH_REMATCH[1]}"
  done
  ((_at >= 0)) || return 0
  FZX_OPTS[_at]="--with-nth=$_k,-1${FZX_OPTS[_at]#--with-nth=$_k}"
  [[ " ${FZX_OPTS[*]} " == *" --tabstop="* ]] || FZX_OPTS+=(--tabstop=1)
  # a search limited to the display (the menu's) covers both parts of it
  for ((_i = 0; _i < ${#FZX_OPTS[@]}; _i++)); do
    [[ "${FZX_OPTS[_i]}" == --nth=1 ]] && FZX_OPTS[_i]=--nth=1,2
  done
  fzx::meta_set freeze "$_k"
}

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
  local prompt loading act
  fzx::prompt loaded prompt
  fzx::prompt loading loading
  # start in the loading form; load (every reload, not just the first) switches to the loaded one
  [[ -n "$loading" ]] && FZX_OPTS+=("--prompt=$loading")
  fzx::_prompt_binds "$prompt"
  FZX_OPTS+=(--bind "start:reload:$(fzx::cb load)")
  fzx::reload_action "$(fzx::cb source)" act
  fzx::bind "${FZX_KEYS[reload_hard]}" "$act" "reload: run the source again"
  fzx::bind "${FZX_KEYS[wrap]}" toggle-wrap-word "wrap the list's rows"
  fzx::bind "${FZX_KEYS[preview_wrap]}" toggle-preview-wrap "wrap the preview"

  if fzx::in_session; then
    fzx::session_title label
    FZX_OPTS+=(
      "--listen=$FZX_SESSION_DIR/fzf.sock"
      "--border-label= $label "
    )
    fzx::bind "${FZX_KEYS[reload_soft]}" "transform:$(fzx::cb nav resume)" "restart the interface, data from cache"
    fzx::bind "${FZX_KEYS[back]}" "transform:$(fzx::cb nav back)" "back to the previous screen"
    # the menu has nowhere to go from itself
    [[ "$module" == menu || -z "${FZX_KEYS[menu]:-}" ]] ||
      fzx::bind "${FZX_KEYS[menu]}" "transform:$(fzx::cb nav menu)" "the main menu"
    # at the root of a tree that is not kept, escape can only quit: fzf aborts without starting a callback
    # (fzx::nav escape would save the query, position and layout the owner's cleanup then removes; the exit
    # row records the abort). Child screens go back; a kept tree's root saves them for its resume.
    local _parent="" _keep=""
    if ! fzx::meta_get parent _parent && ! { fzx::meta_get keep _keep && [[ "$_keep" == 1 ]]; }; then
      fzx::bind "${FZX_KEYS[escape]}" abort "quit"
    else
      fzx::bind "${FZX_KEYS[escape]}" "transform:$(fzx::cb nav escape)" "back to the previous screen; quit at the root"
    fi
    fzx::bind "${FZX_KEYS[popout]}" "transform:$(fzx::cb nav placement next)" "next placement: ${FZX_PLACEMENTS[*]}"
    [[ -n "${FZX_KEYS[popup_toggle]:-}" ]] &&
      fzx::bind "${FZX_KEYS[popup_toggle]}" "transform:$(fzx::cb nav placement popup-toggle)" "popup or the plain terminal"
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
    local _taken _i=0 _digit
    fzx::_taken_keys _taken
    while IFS=$'\t' read -r _k _n _key _desc _flags; do
      _i=$((_i + 1))
      # alt-1 .. alt-8 by table order too (alt-9 and alt-0 switch modes), unless another row or an fzx
      # key has it; a toggle whose own key is its number is bound once
      _digit=""
      if [[ "${FZX_TOGGLE_DIGIT_KEYS:-1}" == 1 ]] && ((_i <= 8)); then
        _digit="alt-$_i"
        [[ "$_taken" == *" $_digit "* ]] && _digit=""
      fi
      [[ -n "$_key" && "$_key" != - ]] &&
        _FZX_BIND_SCOPE="$module" fzx::bind "$_key" "transform:$(fzx::cb toggle "$_n")" "toggle: ${_desc:-$_n}"
      [[ -n "$_digit" ]] &&
        _FZX_BIND_SCOPE="$module" fzx::bind "$_digit" "transform:$(fzx::cb toggle "$_n")" "toggle: ${_desc:-$_n}"
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
    # result-final: once the list is complete (load is the prompt's); then it unbinds itself
    fzx::state_get pos pos && [[ "$pos" =~ ^[0-9]+$ ]] && ((pos > 1)) &&
      FZX_OPTS+=(--bind "result-final:pos($pos)+unbind(result-final)")
  else
    fzx::title_paint label "$module${FZX_MODE:+:$FZX_MODE}"
    FZX_OPTS+=("--border-label= $label ")
  fi

  # the sort keys are always the sort's: with nothing to switch to they do nothing, rather than reach fzf's
  # own binding for the key (ctrl-/ and ctrl-_ wrap the list)
  if ! fzx::in_session || (($(fzx::comp_rows sort | wc -l) < 2)); then
    fzx::bind "${FZX_KEYS[sort_next]}" ignore "next sort order (none here)"
    fzx::bind "${FZX_KEYS[sort_prev]}" ignore "previous sort order (none here)"
  fi

  # the module's opts hook may set these for its action bindings (lib/actions.sh)
  # shellcheck disable=SC2034
  FZX_ACTION_ARGS='{+1}'
  # shellcheck disable=SC2034
  declare -gA FZX_ACTION_ARGS_FOR=()
  if declare -F "$module::opts" > /dev/null; then
    _FZX_BIND_SCOPE="$module"
    "$module::opts" || return 1
    _FZX_BIND_SCOPE=fzx
  fi
  # a view with a header row (lib/header.sh) shows the source's first line as fzf's header, unless the
  # module always has one
  if [[ "${FZX_SORT_HEADER:-0}" == 1 && " ${FZX_OPTS[*]} " != *" --header-lines="* ]]; then
    FZX_OPTS+=(--header-lines=1)
  fi
  # FZX_READ0=1 (a module's opts hook may set it): items end with NUL and may span lines; the callbacks
  # count them by NUL (meta/read0)
  [[ "${FZX_READ0:-0}" == 1 ]] && FZX_OPTS+=(--read0 --highlight-line)
  fzx::in_session && fzx::meta_set read0 "${FZX_READ0:-0}"
  fzx::_freeze_opts
  fzx::require actions
  fzx::actions_bind "$module"
  # the menus have no actions, but the yank keys still report in the footer rather than reach fzfrc's, which
  # copy hidden fields and report by notify-send
  if fzx::in_session; then
    local _copy_args='{+1}'
    [[ -n "${FZX_ACTION_ARGS_FOR[copy]:-}" ]] && _copy_args="${FZX_ACTION_ARGS_FOR[copy]}"
    fzx::comp_field action copy key _ ||
      fzx::bind ctrl-y "transform($(fzx::cb notify copy "$_copy_args"))" "copy the selection"
    fzx::comp_field action copy-line key _ ||
      fzx::bind alt-y "transform($(fzx::cb notify copy-line '{+}'))" "copy the whole lines"
  fi
  fzx::_component_place
  # debug view in the preview; standalone has no session, so only the variables
  if fzx::in_session; then
    fzx::bind "${FZX_KEYS[debug]}" "show-preview+preview:$(fzx::cb debug {})" "debug: session state, FZF_* and FZX_* variables"
  else
    fzx::bind "${FZX_KEYS[debug]}" "show-preview+preview:env | grep -E '^(FZX|FZF)_' | sort" "debug: FZX_* and FZF_* variables"
  fi
  local hk help_keys=()
  fzx::split_keys "${FZX_KEYS[help]}" help_keys
  for hk in "${help_keys[@]}"; do FZX_HELP+=("fzx"$'\t'"$hk"$'\t'"this help"); done
  fzx::_help_bind "$module"
  fzx::_layout_binds
  fzx::_trace_binds
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
