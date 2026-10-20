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

# actions::source [menu args...]
actions::source() {
  local dir k n key desc d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  actions::parent dir || return
  while IFS=$'\t' read -r k n key desc _; do
    [[ "$k" == action ]] || continue
    actions::argv "$n" "$@" || continue
    [[ "$key" == - ]] && key=""
    [[ "$desc" == - ]] && desc=""
    printf '%s\t%-12s %s%-10s%s %s\n' "$n" "$n" "$d" "$key" "$r" "$desc"
  done < "$dir/meta/components"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log session
  FZX_STANDALONE=1
  actions::source "$@"
}
