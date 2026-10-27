#!/usr/bin/env bash
# menu preview: the entry (icon, target, description and its summary here), the module's modes, toggles,
# sort orders and actions with their keys, how the module has been used, and the command it runs.

[[ -n "${_FZX_CORE_LOADED:-}" ]] || source "${FZX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/core.sh"
fzx::require log session menu

# menu::preview <module>#<n>
menu::preview() {
  local id="${1:-}" module n dir file
  module="${id%%#*}"
  n="${id#*#}"
  if [[ "$id" != *#* ]] || ! dir="$(fzx::module_find "$module")" || ! fzx::menu_entries "$module" "$dir" ||
    [[ ! "$n" =~ ^[0-9]+$ ]] || ((n >= ${#FZX_ENTRY_TARGETS[@]})); then
    printf 'no such entry: %s\n' "$id"
    return 1
  fi
  local target="${FZX_ENTRY_TARGETS[n]}" mode="" icon="" color width
  local r=$'\e[0m' b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m"
  local cap=$'\e['"${FZX_COLORS[help_key]:-1;38;5;255;48;5;236}m"
  [[ "$target" == *:* ]] && mode="${target#*:}"
  width="${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}"

  # the entry, as the menu line shows it
  color="${FZX_COLORS[${module}_icon_$mode]:-${FZX_COLORS[${module}_icon]:-${FZX_COLORS[menu_target]:-0}}}"
  if [[ "${FZX_ICONS:-nerd}" == nerd ]]; then
    icon="$FZX_ICON"
    [[ -n "$mode" && -n "${FZX_ICON_MODES[$mode]:-}" ]] && icon="${FZX_ICON_MODES[$mode]}"
    icon=$'\e['"${color}m${icon:- }$r "
  fi
  printf '%s%s%s%s\n' "$icon" $'\e['"${FZX_COLORS[menu_target]:-0};1m" "$target" "$r"
  printf '%s\n' "${FZX_ENTRY_DESCS[n]}"
  if declare -F "$module::summary" > /dev/null; then
    fzx::summary_path file "$module" "$n"
    [[ -s "$file" ]] && printf '%s%s%s\n' $'\e['"${FZX_COLORS[menu_summary]:-0}m" "$(< "$file")" "$r"
  fi

  menu::_components "$module" "$dir" "$mode"
  menu::_use "$module"

  fzx::menu_entry_args "$n"
  printf '\n%sfzx -m %s%s%s\n%s%s\n' "$d" "$target" "${FZX_ENTRY_ARGS[n]:+ ${FZX_ENTRY_ARGS[n]}}" "$r" "$d" "${dir/#$HOME/\~}$r"
}

# menu::_components <module> <dir> <mode>: the module's modes (the entry's marked), toggles, sort orders and
# actions (the mode's part of a scoped description; the built-in actions every module has are left out)
menu::_components() {
  local module="$1" dir="$2" mode="$3" kind name key desc flags row title last="" room mark keycap namew=4
  fzx::require components keys
  fzx::comp_load "$dir" "$module" 2> /dev/null || return 0
  [[ -n "$mode" ]] || mode="${FZX_MODES[0]:-}"
  # every mode, hidden ones too, so a scoped description is recognized as one
  local modes=()
  for row in "${FZX_COMP[@]}"; do
    IFS=$'\t' read -r kind name _ <<< "$row"
    [[ "$kind" == mode ]] && modes+=("$name")
    ((${#name} > namew)) && namew=${#name}
  done
  room=$((width - namew - 17))
  ((room < 12)) && room=12
  for row in "${FZX_COMP[@]}"; do
    IFS=$'\t' read -r kind name key desc flags <<< "$row"
    [[ ",$flags," == *,hidden,* || ",$flags," == *,builtin,* ]] && continue
    [[ "$desc" == - ]] && desc=""
    if [[ "$kind" == action || "$kind" == sort ]] && ((${#modes[@]} > 1)); then
      fzx::mode_desc "$desc" "$mode" desc "${modes[@]}" || continue
    fi
    if [[ "$kind" != "$last" ]]; then
      case "$kind" in
        mode) title=modes ;; toggle) title=toggles ;; sort) title="sort (f11/f12)" ;; *) title=actions ;;
      esac
      printf '\n%s▌ %s%s\n' $'\e['"${FZX_COLORS[help_module]:-1}m" "$title" "$r"
      last="$kind"
    fi
    mark=" "
    [[ "$kind" == mode && "$name" == "$mode" ]] && mark="${b}▸$r"
    keycap="           "
    if [[ "$key" != - ]]; then
      fzx::key_label "$key" key
      printf -v keycap '%s %s %s' "$cap" "$(fzx::pad "$key" 9)" "$r"
    fi
    ((${#desc} > room)) && desc="${desc:0:room-1}…"
    printf '%s %s %s%-*s%s  %s\n' "$mark" "$keycap" "$b" "$namew" "$name" "$r" "$desc"
  done
}

# menu::_use <module>: how often the module was open (its sessions, opened from the menu or not), when it
# last ran, how the runs that ended in it ended and how long its source takes
menu::_use() {
  fzx::require stats
  [[ -s "$FZX_STATS_FILE" ]] || return 0
  awk -F'\t' -v m="$1" -v t="$(printf '%s▌ use%s' $'\e['"${FZX_COLORS[help_module]:-1}m" $'\e[0m')" '
    function dur(ms) { return ms < 1000 ? sprintf("%dms", ms) : sprintf("%.1fs", ms / 1000) }
    $4 != m { next }
    !($3 in seen) { seen[$3] = 1; runs++ }
    $1 > last { last = $1 }
    $6 == "exit" { split($9, ex, " "); if (ex[2] == "accept") acc++; else if (ex[2] == "abort") ab++ }
    $6 == "source" && $9 !~ /^fail/ { src++; ssum += $7 }
    END {
      if (!runs) exit
      printf "\n%s\n", t
      printf "  opened %d times, last %s\n", runs, strftime("%Y-%m-%d %H:%M", int(last / 1000))
      if (acc + ab) printf "  %d picked, %d cancelled\n", acc, ab
      if (src) printf "  source %s on average (%d runs)\n", dur(ssum / src), src
    }' "$FZX_STATS_FILE"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && menu::preview "$@"
