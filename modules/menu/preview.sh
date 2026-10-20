#!/usr/bin/env bash
# menu preview: what an entry opens, its summary here, and how it has been used.

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
  fzx::menu_entry_args "$n"
  printf 'opens    fzx -m %s%s\n' "${FZX_ENTRY_TARGETS[n]}" "${FZX_ENTRY_ARGS[n]:+ ${FZX_ENTRY_ARGS[n]}}"
  printf 'module   %s\n\n' "$dir"
  printf '%s\n' "${FZX_ENTRY_DESCS[n]}"
  fzx::summary_path file "$id"
  [[ -s "$file" ]] && printf '\n%s\n' "$(< "$file")"

  fzx::require stats
  if [[ -s "$FZX_STATS_FILE" ]]; then
    printf '\n'
    fzx::stats --module "$module"
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && menu::preview "$@"
