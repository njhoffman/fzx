#!/usr/bin/env bash
# actions source: the action rows of the screen the menu was opened from, "name<TAB>display".

# actions::parent <var>: session directory of the screen the menu acts on
actions::parent() {
  local _p=""
  if ! fzx::in_session || ! fzx::meta_get parent _p || [[ ! -f "$FZX_SESSIONS_DIR/$_p/meta/components" ]]; then
    printf 'actions: the actions menu only runs as a child of an fzx screen\n' >&2
    return 2
  fi
  printf -v "$1" '%s' "$FZX_SESSIONS_DIR/$_p"
}

# actions::row <name> <var>: the parent's row for an action ("action<TAB>name<TAB>key<TAB>desc<TAB>flags")
actions::row() {
  local _dir _r
  actions::parent _dir || return
  while IFS= read -r _r; do
    [[ "$_r" == action$'\t'"$1"$'\t'* ]] && { printf -v "$2" '%s' "$_r"; return 0; }
  done < "$_dir/meta/components"
  return 1
}

# actions::argv <name> [menu args...]: the arguments the action runs with, into ACTIONS_ARGV
actions::argv() {
  local name="$1" names="" a in_group=0 found=0
  shift
  fzx::require actions
  ACTIONS_ARGV=()
  for a in "$@"; do
    if ((!in_group)); then
      names="$a" in_group=1 found=0
      [[ ",$names," == *",$name,"* ]] && found=1
    elif [[ "$a" == "$FZX_ACTIONS_SEP" ]]; then
      ((found)) && return 0
      in_group=0
    elif ((found)); then
      ACTIONS_ARGV+=("$a")
    fi
  done
  ((found))
}

# actions::sgr <color name> <default> <text> <var>: the text in FZX_COLORS[name] (plain with NO_COLOR)
actions::sgr() {
  local _c="${FZX_COLORS[$1]:-$2}"
  if [[ -n "${NO_COLOR+x}" || -z "$_c" || -z "$3" ]]; then
    printf -v "$4" '%s' "$3"
  else
    printf -v "$4" '\e[%sm%s\e[0m' "$_c" "$3"
  fi
}

# actions::how <flags> <var>: how the action runs, from its flags: confirm (asks first), become (replaces
# fzf; print too), silent (in the background; notify too), else run (in the terminal)
actions::how() {
  local _f=",$1,"
  if [[ "$_f" == *,confirm,* ]]; then printf -v "$2" confirm
  elif [[ "$_f" == *,become,* || "$_f" == *,print,* ]]; then printf -v "$2" become
  elif [[ "$_f" == *,silent,* || "$_f" == *,notify,* ]]; then printf -v "$2" silent
  else printf -v "$2" run; fi
}

# actions::how_icon <flags> <var>: the colored icon of how the action runs, then the reload mark or a
# blank, a space apart (Nerd Font glyphs draw wider than their cell), then a space; none with
# FZX_ICONS=none
actions::how_icon() {
  local _how _g _r _out="" _f=",$1,"
  fzx::require icons
  actions::how "$1" _how
  fzx::icon "action_$_how" _g
  [[ -n "$_g" ]] || { printf -v "$2" '%s' ""; return 0; }
  actions::sgr "actions_$_how" "" "$_g" _out
  if [[ "$_f" == *,reload,* || "$_f" == *,restart,* ]]; then
    fzx::icon action_reload _r
    actions::sgr actions_reload "" "$_r" _r
    _out+=" $_r"
  else
    _out+="  "
  fi
  printf -v "$2" '%s ' "$_out"
}

# actions::source [menu args...]: "name<TAB>display" per action: how it runs, the name (fzx's own
# built-ins dimmer), the key as a keycap, a mark on the default (enter) one, the description
# an action whose description is scoped by mode (lib/components.sh, fzx::mode_desc) is listed with the
# parent's mode's part, and left out when no part names that mode
actions::source() {
  local dir k n key desc flags mode="" modes=() rows=() w=0 nw=12 i icon name cap def dsc
  actions::parent dir || return
  fzx::require components
  [[ -f "$dir/state/mode" ]] && mode="$(< "$dir/state/mode")"
  while IFS=$'\t' read -r k n _; do
    [[ "$k" == mode ]] && modes+=("$n")
  done < "$dir/meta/components"
  while IFS=$'\t' read -r k n key desc flags; do
    [[ "$k" == action ]] || continue
    actions::argv "$n" "$@" || continue
    [[ "$desc" == - ]] && desc=""
    if ((${#modes[@]})); then
      fzx::mode_desc "$desc" "$mode" desc "${modes[@]}" || continue
    fi
    # "-" for empty fields: tab is whitespace to read, so an empty field would shift the others
    rows+=("$n"$'\t'"${key:--}"$'\t'"${desc:--}"$'\t'"${flags:--}")
    [[ "$key" != - ]] && ((${#key} > w)) && w=${#key}
    ((${#n} > nw)) && nw=${#n}
  done < "$dir/meta/components"
  for i in "${rows[@]}"; do
    IFS=$'\t' read -r n key desc flags <<< "$i"
    [[ "$key" == - ]] && key=""
    [[ "$desc" == - ]] && desc=""
    actions::how_icon "$flags" icon
    printf -v name "%-${nw}s" "$n"
    if [[ ",$flags," == *,builtin,* ]]; then
      actions::sgr actions_builtin '38;5;248' "$name" name
    else
      actions::sgr actions_name '1' "$name" name
    fi
    # the keycap is padded inside, so every cap is as wide as the widest
    if ((w)); then
      if [[ -n "$key" ]]; then
        printf -v cap " %-${w}s " "$key"
        actions::sgr actions_key '38;5;180;48;5;236' "$cap" cap
      else
        printf -v cap "%$((w + 2))s" ""
      fi
    else
      cap=""
    fi
    def=" "
    [[ ",$flags," == *,default,* ]] && actions::sgr actions_default '38;5;114' "⏎" def
    actions::sgr dim '38;5;244' "$desc" dsc
    printf '%s\t%s%s %s %s %s\n' "$n" "$icon" "$name" "$cap" "$def" "$dsc"
  done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log session
  FZX_STANDALONE=1
  actions::source "$@"
}
