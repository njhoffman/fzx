#!/usr/bin/env bash
# output: where the selection goes besides fzf's accept (docs/design.md, "Output: --to and --loop").
#   --to TARGET   enter sends the selection into a tmux pane (FZX_OUTPUT_PANE, a pane id resolved once at
#                 launch, so the pane is found again wherever it moves) as a bracketed paste; --submit
#                 (FZX_OUTPUT_SUBMIT=1) presses Enter after it
#   --loop        the list stays open (FZX_LOOP=1): enter sends the selection to the pane, or to fzx's
#                 output, then clears the selection and reloads; ctrl-] sends and closes
# Both make fzx a picker (FZX_PRINT=1). What goes out is what fzf's accept would print (--accept-nth), or
# what a default action flagged print prints (history's and snippets' insert), or what the action the
# module's opts hook names in FZX_OUTPUT_ACTION prints (tasks' command line for a pane). The text ends with
# a newline unless the opts hook sets FZX_OUTPUT_NEWLINE=0 (a command line; kept in meta/output_newline for
# the screen's callbacks) or --submit.

# fzx::output_resolve <target> <placement> <var>: the pane id (%N) TARGET names: left, right, up or down,
# the neighbour of the pane fzx starts in ($TMUX_PANE); anything else a tmux target (%N, SESSION:W.P,
# {last}). Inline (an empty placement) that pane itself is refused: the text would land in fzf.
fzx::output_resolve() {
  local _t="$1" _place="$2" _id=""
  if [[ -z "${TMUX:-}" ]]; then
    printf 'fzx: --to needs tmux\n' >&2
    return 2
  fi
  case "$_t" in
    left | right | up | down)
      if [[ -z "${TMUX_PANE:-}" ]]; then
        printf 'fzx: --to %s: TMUX_PANE is not set\n' "$_t" >&2
        return 2
      fi
      _id="$(fzx::_output_neighbour "$_t")"
      [[ -n "$_id" ]] || { printf 'fzx: --to %s: no pane %s of %s\n' "$_t" "$_t" "$TMUX_PANE" >&2 && return 2; }
      ;;
    *) _id="$(tmux display-message -p -t "$_t" '#{pane_id}' 2> /dev/null)" ;;
  esac
  if [[ ! "$_id" =~ ^%[0-9]+$ ]]; then
    printf 'fzx: --to %s: no such pane\n' "$_t" >&2
    return 2
  fi
  if [[ -z "$_place" && "$_id" == "${TMUX_PANE:-}" ]]; then
    printf 'fzx: --to %s: that is the pane fzf runs in\n' "$_t" >&2
    return 2
  fi
  printf -v "$3" '%s' "$_id"
}

# fzx::_output_neighbour <left|right|up|down>: the pane next to $TMUX_PANE that way: the nearest one that
# shares rows (left, right) or columns (up, down) with it, the one sharing the most when several are as
# near; floating panes are not in the layout and are left out
fzx::_output_neighbour() {
  tmux list-panes -t "$TMUX_PANE" -F '#{pane_id} #{pane_left} #{pane_top} #{pane_right} #{pane_bottom} #{pane_floating_flag}' 2> /dev/null |
    awk -v me="$TMUX_PANE" -v dir="$1" '
      { id[NR] = $1; l[NR] = $2; t[NR] = $3; r[NR] = $4; b[NR] = $5; fl[NR] = $6; if ($1 == me) m = NR }
      END {
        if (!m) exit 1
        best = 0
        for (i = 1; i <= NR; i++) {
          if (i == m || fl[i] == 1) continue
          if (dir == "left" || dir == "right") { lo = t[i] > t[m] ? t[i] : t[m]; hi = b[i] < b[m] ? b[i] : b[m] }
          else { lo = l[i] > l[m] ? l[i] : l[m]; hi = r[i] < r[m] ? r[i] : r[m] }
          ov = hi - lo + 1
          if (ov <= 0) continue
          if (dir == "left") { if (r[i] >= l[m]) continue; gap = l[m] - r[i] }
          else if (dir == "right") { if (l[i] <= r[m]) continue; gap = l[i] - r[m] }
          else if (dir == "up") { if (b[i] >= t[m]) continue; gap = t[m] - b[i] }
          else { if (t[i] <= b[m]) continue; gap = t[i] - b[m] }
          if (!best || gap < bgap || (gap == bgap && ov > bov)) { best = i; bgap = gap; bov = ov }
        }
        if (best) print id[best]
      }'
}

# fzx::output_send_pane <pane> <delay> <line...>: the lines into the pane as a bracketed paste, so nothing
# runs; with FZX_OUTPUT_SUBMIT=1 Enter follows. The text has no newline at its end then, nor with
# FZX_OUTPUT_NEWLINE=0. A delay (seconds,
# 0: none) hands the paste to the tmux server for later: when fzf closes with it (a popup, a pane of its
# own in tmux 3.9), the target may still be running the command that opened it. Every send has a buffer
# of its own, so sends close together cannot overwrite one another before tmux pastes them.
fzx::output_send_pane() {
  local pane="$1" delay="$2" buf text cmd
  shift 2
  if [[ ! "$pane" =~ ^%[0-9]+$ ]]; then
    printf 'not a tmux pane id (%%N): %s\n' "$pane" >&2
    return 2
  fi
  (($#)) || return 0
  # display-message succeeds for a pane that is gone (empty output), so its answer is compared
  if [[ "$(tmux display-message -p -t "$pane" '#{pane_id}' 2> /dev/null)" != "$pane" ]]; then
    printf 'pane %s is gone\n' "$pane" >&2
    return 1
  fi
  buf="fzx-out-$BASHPID-$RANDOM"
  printf -v text '%s\n' "$@"
  [[ "${FZX_OUTPUT_SUBMIT:-0}" == 1 || "${FZX_OUTPUT_NEWLINE:-1}" == 0 ]] && text="${text%$'\n'}"
  printf '%s' "$text" | tmux load-buffer -b "$buf" - || return
  cmd="tmux paste-buffer -p -d -b $buf -t $pane"
  [[ "${FZX_OUTPUT_SUBMIT:-0}" == 1 ]] && cmd+=" && tmux send-keys -t $pane Enter"
  if [[ "$delay" == 0 ]]; then
    bash -c "$cmd"
  else
    tmux run-shell -b -d "$delay" "$cmd"
  fi
}

# fzx::output_file <var>: the root session's out file, where --loop without --to collects the output
fzx::output_file() {
  local _root=""
  fzx::meta_get root _root || _root="$FZX_SESSION"
  printf -v "$1" '%s/%s/out' "$FZX_SESSIONS_DIR" "$_root"
}

# fzx::_output_template <var>: what fzf's accept prints of a row, as an --accept-nth template: the module's
# own template ({1}:{2}), an index expression made one ({3}), or the whole row ({})
fzx::_output_template() {
  local _i _a=""
  for ((_i = 0; _i < ${#FZX_OPTS[@]}; _i++)); do
    case "${FZX_OPTS[_i]}" in
      --accept-nth) _a="${FZX_OPTS[_i + 1]:-}" ;;
      --accept-nth=*) _a="${FZX_OPTS[_i]#--accept-nth=}" ;;
    esac
  done
  if [[ -z "$_a" ]]; then
    _a='{}'
  elif [[ "$_a" != *'{'* ]]; then
    _a="{$_a}"
  fi
  printf -v "$1" '%s' "$_a"
}

# fzx::_output_exprs <template> <array var>: the template's field expressions in order ({n} left out: the
# rows' indexes come with every call)
fzx::_output_exprs() {
  local _rest="$1" _e
  local -n __oe="$2"
  __oe=()
  while [[ "$_rest" =~ \{([^{}]*)\} ]]; do
    _e="${BASH_REMATCH[1]}"
    _rest="${_rest#*"${BASH_REMATCH[0]}"}"
    [[ "$_e" == n ]] || __oe+=("$_e")
  done
}

# fzx::_output_placeholders <template> <var>: the callback's arguments for it: the selected rows' indexes,
# "--", then each expression's values for every row ({+n} -- {+3} or {+1} {+2})
fzx::_output_placeholders() {
  local _exprs=() _e _p='{+n} --'
  fzx::_output_exprs "$1" _exprs
  for _e in "${_exprs[@]}"; do _p+=" {+$_e}"; done
  printf -v "$2" '%s' "$_p"
}

# fzx::_output_items <array var> <template> <indexes...> -- <values...>: the rows as accept prints them,
# the template filled in for each (values come expression by expression, one per row)
fzx::_output_items() {
  local -n __oi="$1"
  local _tpl="$2" _idx=() _n _k _j _rest _out _e _v
  shift 2
  while (($#)) && [[ "$1" != -- ]]; do _idx+=("$1") && shift; done
  (($#)) && shift
  __oi=()
  _n="${#_idx[@]}"
  for ((_j = 0; _j < _n; _j++)); do
    _rest="$_tpl" _out="" _k=0
    while [[ "$_rest" =~ \{([^{}]*)\} ]]; do
      _e="${BASH_REMATCH[1]}"
      _out+="${_rest%%"${BASH_REMATCH[0]}"*}"
      _rest="${_rest#*"${BASH_REMATCH[0]}"}"
      if [[ "$_e" == n ]]; then
        _v="${_idx[_j]}"
      else
        _v="${*:$((_k * _n + _j + 1)):1}"
        _k=$((_k + 1))
      fi
      _out+="$_v"
    done
    __oi+=("$_out$_rest")
  done
}

# fzx::output_binds <module> <own enter>: with --to or --loop, enter (and FZX_KEYS[print]) send the selection
# through `fzx _cb output`. Not in the menus, whose ids mean nothing outside fzx, nor where the module's opts
# hook bound enter itself; standalone there is no callback.
fzx::output_binds() {
  local module="$1" own_enter="$2" pane="${FZX_OUTPUT_PANE:-}" loop=0 args="" tpl ph desc enter_act close_act
  local _k _n _key _desc _flags __ob_a
  [[ "${FZX_LOOP:-0}" == 1 ]] && loop=1
  fzx::in_session || return 0
  # a launch of this session before may have left marks; a screen that sends nothing shows none
  fzx::meta_set title_marks ""
  ((loop)) || [[ -n "$pane" ]] || return 0
  [[ "$module" == menu || "$module" == actions ]] && return 0
  if ((own_enter)); then
    fzx::log info "output: $module binds enter itself; --to/--loop leave it"
    return 0
  fi
  # the action the opts hook names, else a default action that prints a value: its output is what goes out
  if [[ -n "${FZX_OUTPUT_ACTION:-}" ]]; then
    fzx::action_args "$FZX_OUTPUT_ACTION" "" __ob_a
    args="action $FZX_OUTPUT_ACTION $__ob_a"
  fi
  [[ -n "$args" ]] || while IFS=$'\t' read -r _k _n _key _desc _flags; do
    if [[ ",$_flags," == *,default,* && ",$_flags," == *,print,* ]]; then
      fzx::action_args "$_n" "$_flags" __ob_a
      args="action $_n $__ob_a"
      break
    fi
  done < <(fzx::comp_rows action)
  if [[ -z "$args" ]]; then
    fzx::_output_template tpl
    fzx::meta_set accept "$tpl"
    fzx::_output_placeholders "$tpl" ph
    args="items $ph"
  fi
  if [[ -n "$pane" ]]; then
    desc="paste the selection into $pane"
    [[ "${FZX_OUTPUT_SUBMIT:-0}" == 1 ]] && desc="run the selection in $pane (paste and Enter)"
  else
    desc="print the selection"
  fi
  close_act="become($(fzx::cb output once "$args"))"
  if ((loop)); then
    enter_act="transform($(fzx::cb output loop "$args"))"
    desc+=", then reload and stay"
  else
    enter_act="$close_act"
  fi
  fzx::_help_drop "$module" enter
  fzx::_help_drop fzx enter
  _FZX_BIND_SCOPE="$module" fzx::bind enter "$enter_act" "$desc"
  if ((loop)) && [[ -n "${FZX_KEYS[print]:-}" ]]; then
    fzx::_help_drop fzx "${FZX_KEYS[print]}"
    fzx::bind "${FZX_KEYS[print]}" "$close_act" "${desc%, then*} and close"
  elif [[ -n "$pane" && -n "${FZX_KEYS[print]:-}" ]]; then
    fzx::_help_drop fzx "${FZX_KEYS[print]}"
    fzx::bind "${FZX_KEYS[print]}" "$close_act" "$desc and close"
  fi
  fzx::meta_set enter "$desc"
  # the screen's own, for its callbacks: not exported, so the next screen sets its own
  fzx::meta_set output_newline "${FZX_OUTPUT_NEWLINE:-1}"
  fzx::_output_title_set
}

# fzx::output_title <var>: the border title's mark with --loop: the loop icon (nf-md-infinity; FZX_ICONS=none:
# the word) in FZX_COLORS[title_loop]
fzx::output_title() {
  local _i="" _c="${FZX_COLORS[title_loop]:-}"
  [[ "${FZX_LOOP:-0}" == 1 ]] || { printf -v "$1" '%s' "" && return 0; }
  fzx::require icons
  fzx::icon loop _i
  _i="${_i:-loop}"
  [[ -n "$_c" && -z "${NO_COLOR:+x}" ]] && _i=$'\e['"${_c}m$_i"$'\e[0m'
  printf -v "$1" ' %s' "$_i"
}

# fzx::output_target <var>: the info line's mark with --to: the output icon (nf-md-console_line; none: "to") in
# FZX_COLORS[output_target], then the pane, subdued in FZX_COLORS[output_pane], with "(gone)" when tmux has
# no such pane any more
fzx::output_target() {
  local _i="" _id _p _c="${FZX_COLORS[output_target]:-}" _pc="${FZX_COLORS[output_pane]:-}"
  [[ -n "${FZX_OUTPUT_PANE:-}" ]] || { printf -v "$1" '%s' "" && return 0; }
  fzx::require icons
  fzx::icon output _i
  _i="${_i:-to}"
  _p="$FZX_OUTPUT_PANE"
  _id="$(tmux display-message -p -t "$FZX_OUTPUT_PANE" '#{pane_id}' 2> /dev/null)" || :
  [[ "$_id" == "$FZX_OUTPUT_PANE" ]] || _p+=" (gone)"
  if [[ -z "${NO_COLOR:+x}" ]]; then
    [[ -n "$_c" ]] && _i=$'\e['"${_c}m$_i"$'\e[0m'
    [[ -n "$_pc" ]] && _p=$'\e['"${_pc}m$_p"$'\e[0m'
  fi
  printf -v "$1" '%s %s' "$_i" "$_p"
}

# fzx::_output_title_set: the loop mark into meta/title_marks (fzx::session_title appends it, here and on
# the in-place refreshes after a mode or toggle change) and the launch's --border-label made again with it;
# the target into meta/output_target and an --info-command that puts it after fzf's info. The command runs
# on every info update, so it reads the file with builtins only: a failed send rewrites it (fzx::output_cb)
fzx::_output_title_set() {
  local _marks _label _i _target _cmd
  fzx::output_title _marks
  fzx::meta_set title_marks "$_marks"
  fzx::session_title _label
  for ((_i = 0; _i < ${#FZX_OPTS[@]}; _i++)); do
    [[ "${FZX_OPTS[_i]}" == --border-label=* ]] && FZX_OPTS[_i]="--border-label= $_label "
  done
  fzx::output_target _target
  fzx::meta_set output_target "$_target"
  [[ -n "$_target" ]] || return 0
  # shellcheck disable=SC2016  # $FZF_INFO and $m are the info command's, expanded when fzf runs it
  printf -v _cmd 'IFS= read -r m < %q; printf %%s "$FZF_INFO  $m"' "$FZX_SESSION_DIR/meta/output_target"
  FZX_OPTS+=("--info-command=$_cmd")
}

# fzx::output_cb <loop|once> <items TEMPLATE-ARGS... | action NAME ARGS...>: the callback behind those keys.
# items: the rows as accept prints them (meta/accept, fzx::_output_items); action: what the action prints.
# They go to FZX_OUTPUT_PANE, else to the root's out file (the owner prints it). loop prints fzf actions:
# a footer note, then, when it went out, clear-selection and a reload; once prints nothing (fzf is gone).
fzx::output_cb() {
  local how="${1:-}" kind="${2:-}" lines=() tpl="" err rc=0 msg color act reload f
  shift 2
  case "$kind" in
    items)
      fzx::meta_get accept tpl || tpl='{}'
      fzx::_output_items lines "$tpl" "$@"
      ;;
    action)
      fzx::require callback
      mapfile -t lines < <(fzx::_cb_action "$@" 2>> "$FZX_LOG_FILE")
      ;;
    *)
      printf 'fzx: output: unknown kind: %s\n' "$kind" >&2
      return 2
      ;;
  esac
  ((${#lines[@]})) || return 0
  err="$FZX_SESSION_DIR/output.$BASHPID"
  if [[ -n "${FZX_OUTPUT_PANE:-}" ]]; then
    local delay=0.3 FZX_OUTPUT_NEWLINE=1
    [[ "$how" == loop ]] && delay=0
    fzx::meta_get output_newline FZX_OUTPUT_NEWLINE || FZX_OUTPUT_NEWLINE=1
    fzx::output_send_pane "$FZX_OUTPUT_PANE" "$delay" "${lines[@]}" 2> "$err" || rc=$?
  else
    fzx::output_file f
    printf '%s\n' "${lines[@]}" >> "$f" 2> "$err" || rc=$?
  fi
  fzx::log info "output $how: ${#lines[@]} line(s) to ${FZX_OUTPUT_PANE:-out} rc=$rc"
  if [[ "$how" != loop ]]; then
    cat -- "$err" >&2 2> /dev/null
    rm -f -- "$err"
    return "$rc"
  fi
  fzx::require config
  [[ -n "${_FZX_CB_CONFIG:-}" ]] || fzx::config_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  if ((rc == 0)); then
    color="${FZX_COLORS[notify_ok]:-}"
    if [[ -n "${FZX_OUTPUT_PANE:-}" ]]; then msg="✓ sent to $FZX_OUTPUT_PANE"; else msg="✓ printed"; fi
    ((${#lines[@]} > 1)) && msg+=" (${#lines[@]})"
  else
    color="${FZX_COLORS[notify_fail]:-}"
    IFS= read -r msg < "$err" || msg="failed"
    msg="✗ $msg"
  fi
  cat -- "$err" >> "$FZX_LOG_FILE" 2> /dev/null || :
  rm -f -- "$err"
  fzx::footer_note "$msg" "$color" act
  if ((rc == 0)); then
    fzx::reload_action "$(fzx::cb source)" reload
    act+="+clear-selection+$reload"
  elif [[ -n "${FZX_OUTPUT_PANE:-}" ]]; then
    # the info line's mark is the launch's: say now that the pane is gone
    local target
    fzx::output_target target
    fzx::meta_set output_target "$target"
    # fzf has no action that redraws the info line; a selection change does, and toggling twice leaves it
    act+="+toggle+toggle"
  fi
  printf '%s' "$act"
}

# fzx::output_owner_start: the owner, before fzf: --loop without --to collects into the root's out file;
# when fzx's output is not a terminal it is streamed as it comes (tail follows the file until the owner is
# gone, then prints the rest and exits), else printed when fzf closes (fzx::output_owner_end), since lines
# on the terminal now would land on fzf's screen
fzx::output_owner_start() {
  [[ "${FZX_LOOP:-0}" == 1 && -z "${FZX_OUTPUT_PANE:-}" ]] || return 0
  local f="$FZX_SESSIONS_DIR/$_FZX_ROOT_SESSION/out"
  : > "$f" || return 0
  [[ -t 1 ]] && return 0
  tail -s 0.1 --pid="$$" -c +1 -f -- "$f" 2> /dev/null &
  disown
  _FZX_OUTPUT_STREAMED=1
}

# fzx::output_owner_end: the owner, after fzf: print what --loop collected, unless it was streamed
fzx::output_owner_end() {
  [[ "${FZX_LOOP:-0}" == 1 && -z "${FZX_OUTPUT_PANE:-}" && -z "${_FZX_OUTPUT_STREAMED:-}" ]] || return 0
  cat -- "$FZX_SESSIONS_DIR/$_FZX_ROOT_SESSION/out" 2> /dev/null || :
}
