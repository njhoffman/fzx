#!/usr/bin/env bash
# actions: fzf bindings for the action rows of the components table (lib/components.sh).
#
# The flags of an action row say how it runs:
#   silent      execute-silent: the screen does not change (signals, database updates)
#   foreground  execute: the action gets the terminal (editors, sudo, followers); the default
#   become      fzf is replaced by the action, whose output is fzx's result
#   print       the same as become, for actions that print a value
#   reload      reload the list afterwards (the source runs again)
#   restart     restart the interface afterwards with fresh data (header and options are rebuilt)
#   confirm     ask on the terminal first (so it runs in the foreground)
#   asks        the action asks on the terminal itself (its own questions, e.g. one per kind of target):
#               listed as asking first, runs in the foreground, and fzx asks nothing
#   default     bound to enter as well (unless the module's opts hook binds enter itself); without one,
#               enter prints the selection
#   builtin     one of fzx's own (lib/builtin.sh, config/components.tsv), not the module's actions.sh
#   notify      silent, and under fzx a message in the footer says it ran (or why it failed); the copy
#               and copy-line built-ins always notify
#   background  under fzx, bg-transform: the list stays usable while it runs, the footer says when it is
#               done, and reload (or restart) reloads the list then (long ones: repos' rescan); standalone
#               it is silent
#   reload-key  set by lib/components.sh for a row whose key is "reload": bound to FZX_KEYS[reload_hard]
#               in place of fzx's plain reload, which leaves the help
# Arguments: the module's opts hook may set FZX_ACTION_ARGS (all of its actions, default {+1}) and
# FZX_ACTION_ARGS_FOR[name] (one action, built-ins included). Built-ins default to copy {+1},
# copy-line {+} and view the preview's own arguments.
# The actions menu says what enter does: the default action's row carries the mark, else an enter row
# (meta/enter) names the module's own enter binding or FZX_ENTER_DESC (set in the opts hook).

# separates the groups of the actions menu's arguments ("names args... SEP names args... SEP")
FZX_ACTIONS_SEP=--fzx--

# fzx::action_args <name> <flags> <var>: the placeholder string the action is called with
fzx::action_args() {
  local _a _def='{+1}'
  if [[ -n "${FZX_ACTION_ARGS_FOR[$1]:-}" ]]; then
    _a="${FZX_ACTION_ARGS_FOR[$1]}"
  elif [[ ",$2," == *,builtin,* ]]; then
    case "$1" in
      copy-line) _a='{+}' ;;
      view) fzx::_action_preview_args _a || _a="$_def" ;;
      *) _a="$_def" ;;
    esac
  else
    _a="${FZX_ACTION_ARGS:-$_def}"
  fi
  printf -v "$3" '%s' "$_a"
}

# fzx::_action_preview_args <var>: the arguments of the module's --preview command, when it is a
# preview callback (what the view built-in passes on)
fzx::_action_preview_args() {
  local _i _p="" _prefix
  for ((_i = 0; _i < ${#FZX_OPTS[@]}; _i++)); do
    case "${FZX_OPTS[_i]}" in
      --preview) _p="${FZX_OPTS[_i + 1]:-}" ;;
      --preview=*) _p="${FZX_OPTS[_i]#--preview=}" ;;
    esac
  done
  _prefix="$(fzx::cb preview)"
  [[ -n "$_p" && "$_p" == "$_prefix"* ]] || return 1
  _p="${_p#"$_prefix"}"
  printf -v "$1" '%s' "${_p# }"
}

# fzx::_action_cmd <name> <flags> <args> <var>: the shell command an action binding runs
# (locals __ac_: the caller passes _cmd)
fzx::_action_cmd() {
  local __ac_name="$1" __ac_flags=",$2," __ac_args="$3" __ac_cmd
  if fzx::in_session; then
    __ac_cmd="$(fzx::cb action "$__ac_name" "$__ac_args")"
  elif [[ "$__ac_flags" == *,builtin,* ]]; then
    printf -v __ac_cmd 'FZX_MODULE_DIR=%q %q builtin %s %s' "$FZX_MODULE_DIR" "$FZX_BIN" "$__ac_name" "$__ac_args"
  else
    __ac_cmd="$(fzx::cb action "$__ac_name" "$__ac_args")"
  fi
  # under fzx the callback asks; standalone there is no callback, so the binding does
  if [[ "$__ac_flags" == *,confirm,* ]] && ! fzx::in_session; then
    printf -v __ac_cmd '%q builtin confirm %s %s && %s' "$FZX_BIN" "$__ac_name" "$__ac_args" "$__ac_cmd"
  fi
  printf -v "$4" '%s' "$__ac_cmd"
}

# fzx::_action_notifies <name> <flags>: the action reports in the footer (flag notify, or the copy built-ins)
fzx::_action_notifies() {
  [[ ",$2," == *,notify,* ]] && return 0
  [[ ",$2," == *,builtin,* && ("$1" == copy || "$1" == copy-line) ]]
}

# fzx::_action_bind_string <name> <flags> <var>: the fzf action list for one action row
fzx::_action_bind_string() {
  local _name="$1" _flags=",$2," _args _cmd _act
  fzx::action_args "$_name" "$2" _args
  fzx::_action_cmd "$_name" "$2" "$_args" _cmd
  if [[ "$_flags" == *,become,* || "$_flags" == *,print,* ]]; then
    printf -v "$3" 'become(%s)' "$_cmd"
    return
  fi
  # an action that asks needs the terminal
  local _asks=0
  [[ "$_flags" == *,confirm,* || "$_flags" == *,asks,* ]] && _asks=1
  # the notify callback runs it and, with reload or restart, reloads the list when it is done
  if [[ "$_flags" == *,background,* ]] && fzx::in_session && ((!_asks)); then
    local _p=""
    [[ "$_flags" == *,reload,* || "$_flags" == *,restart,* ]] && fzx::prompt loading _p
    printf -v "$3" '%sbg-transform(%s)' "${_p:+change-prompt($_p)+}" "$(fzx::cb notify "$_name" "$_args")"
    return
  fi
  if fzx::_action_notifies "$_name" "$2" && fzx::in_session && ((!_asks)); then
    _act="transform($(fzx::cb notify "$_name" "$_args"))"
  elif [[ "$_flags" == *,silent,* || "$_flags" == *,notify,* || "$_flags" == *,background,* ]] && ((!_asks)); then
    _act="execute-silent($_cmd)"
  else
    _act="execute($_cmd)"
  fi
  if [[ "$_flags" == *,restart,* ]] && fzx::in_session; then
    _act+="+transform($(fzx::cb nav restart))"
  elif [[ "$_flags" == *,reload,* || "$_flags" == *,restart,* ]]; then
    local _reload
    fzx::reload_action "$(fzx::cb source)" _reload
    _act+="+$_reload"
  fi
  printf -v "$3" '%s' "$_act"
}

# fzx::_help_drop <scope> <key>: forget the scope's help entries for the key (a module row took it)
fzx::_help_drop() {
  local _e _keep=()
  for _e in "${FZX_HELP[@]}"; do
    [[ "$_e" == "$1"$'\t'"$2"$'\t'* ]] || _keep+=("$_e")
  done
  FZX_HELP=("${_keep[@]}")
}

# fzx::_enter_desc <var>: what enter does on this screen without a default action: the help description of
# the module's own enter binding (todos --paste), else FZX_ENTER_DESC (the module's opts hook: what fzf's
# accept prints there), else "print the selection"
fzx::_enter_desc() {
  local _e _d=""
  for _e in "${FZX_HELP[@]}"; do
    [[ "$_e" == *$'\t'enter$'\t'* ]] && _d="${_e##*$'\t'}"
  done
  printf -v "$1" '%s' "${_d:-${FZX_ENTER_DESC:-print the selection}}"
}

# fzx::_module_bound <module> <key>: the module's opts hook bound the key (FZX_HELP)
fzx::_module_bound() {
  local _e
  for _e in "${FZX_HELP[@]}"; do
    [[ "$_e" == "$1"$'\t'"$2"$'\t'* ]] && return 0
  done
  return 1
}

# fzx::actions_bind <module>: bind the action rows (their keys, enter for the default one) and, under fzx,
# the actions menu key; expects the module's opts hook to have run (arguments, preview)
fzx::actions_bind() {
  local module="$1" _k _n _key _desc _flags act args menu=() names enter_default=0 enter_desc
  local -A groups=() order=()
  local -a templates=()
  # in the actions menu itself the key closes it: back to the screen it was opened from
  if [[ "$module" == actions ]]; then
    fzx::in_session && fzx::bind "${FZX_KEYS[actions]}" "transform:$(fzx::cb nav back)" "back to the screen the menu was opened from"
    return 0
  fi
  fzx::comp_has action || return 0
  while IFS=$'\t' read -r _k _n _key _desc _flags; do
    [[ "$_desc" == - ]] && _desc=""
    fzx::_action_bind_string "$_n" "$_flags" act
    # fzf takes the later --bind of a key, so the row wins over fzx's reload; the help lists it once
    if [[ ",$_flags," == *,reload-key,* ]]; then
      local _rk _rks=()
      fzx::split_keys "$_key" _rks
      for _rk in "${_rks[@]}"; do fzx::_help_drop fzx "$_rk"; done
    fi
    [[ -n "$_key" && "$_key" != - ]] &&
      _FZX_BIND_SCOPE="$module" fzx::bind "$_key" "$act" "action: ${_desc:-$_n}"
    # a module whose opts hook bound enter itself keeps it (tasks --paste); the session records that, so
    # the actions menu does not mark the default action as enter's
    if [[ ",$_flags," == *,default,* ]] && ! fzx::_module_bound "$module" enter; then
      _FZX_BIND_SCOPE="$module" fzx::bind enter "$act" "default action: ${_desc:-$_n}"
      enter_default=1
    fi
    # group the actions by their arguments for the menu, in table order
    fzx::action_args "$_n" "$_flags" args
    [[ -n "${order[$args]:-}" ]] || { order[$args]=1; templates+=("$args"); }
    groups[$args]+="${groups[$args]:+,}$_n"
  done < <(fzx::comp_rows action)

  fzx::in_session || return 0
  # what enter does when it is not a default action row, for the menu's enter row (actions/source.sh)
  if ((enter_default)); then
    rm -f -- "$FZX_SESSION_DIR/meta/enter"
  else
    fzx::_enter_desc enter_desc
    fzx::meta_set enter "$enter_desc"
  fi
  for args in "${templates[@]}"; do
    names="${groups[$args]}"
    menu+=("$names" "$args" "$FZX_ACTIONS_SEP")
  done
  fzx::bind "${FZX_KEYS[actions]}" "transform:$(fzx::cb nav goto actions "${menu[@]}")" "actions menu for the selection"
}
