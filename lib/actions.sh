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
#   default     bound to enter as well; without one, enter prints the selection
#   builtin     one of fzx's own (lib/builtin.sh, config/components.tsv), not the module's actions.sh
# Arguments: the module's opts hook may set FZX_ACTION_ARGS (all of its actions, default {+1}) and
# FZX_ACTION_ARGS_FOR[name] (one action, built-ins included). Built-ins default to copy {+1},
# copy-line {+} and view the preview's own arguments.

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

# fzx::_action_bind_string <name> <flags> <var>: the fzf action list for one action row
fzx::_action_bind_string() {
  local _name="$1" _flags=",$2," _args _cmd _act
  fzx::action_args "$_name" "$2" _args
  fzx::_action_cmd "$_name" "$2" "$_args" _cmd
  if [[ "$_flags" == *,become,* || "$_flags" == *,print,* ]]; then
    printf -v "$3" 'become(%s)' "$_cmd"
    return
  fi
  if [[ "$_flags" == *,silent,* && "$_flags" != *,confirm,* ]]; then
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

# fzx::actions_bind <module>: bind the action rows (their keys, enter for the default one) and, under fzx,
# the actions menu key; expects the module's opts hook to have run (arguments, preview)
fzx::actions_bind() {
  local module="$1" _k _n _key _desc _flags act args menu=() names
  local -A groups=() order=()
  local -a templates=()
  fzx::comp_has action || return 0
  while IFS=$'\t' read -r _k _n _key _desc _flags; do
    [[ "$_desc" == - ]] && _desc=""
    fzx::_action_bind_string "$_n" "$_flags" act
    [[ -n "$_key" && "$_key" != - ]] &&
      _FZX_BIND_SCOPE="$module" fzx::bind "$_key" "$act" "action: ${_desc:-$_n}"
    [[ ",$_flags," == *,default,* ]] &&
      _FZX_BIND_SCOPE="$module" fzx::bind enter "$act" "default action: ${_desc:-$_n}"
    # group the actions by their arguments for the menu, in table order
    fzx::action_args "$_n" "$_flags" args
    [[ -n "${order[$args]:-}" ]] || { order[$args]=1; templates+=("$args"); }
    groups[$args]+="${groups[$args]:+,}$_n"
  done < <(fzx::comp_rows action)

  fzx::in_session || return 0
  for args in "${templates[@]}"; do
    names="${groups[$args]}"
    menu+=("$names" "$args" "$FZX_ACTIONS_SEP")
  done
  fzx::bind "${FZX_KEYS[actions]}" "transform:$(fzx::cb nav goto actions "${menu[@]}")" "actions menu for the selection"
}
