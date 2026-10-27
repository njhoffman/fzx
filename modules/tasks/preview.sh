#!/usr/bin/env bash
# tasks preview: the task (project:task, kind, repository, the command that runs it) and its definition
# as written: the make rule, the just recipe, the package.json script line, the Taskfile task, the TOML
# entry. Projects mode: the repository's tasks by kind.

[[ -n "${_FZX_CORE_LOADED:-}" ]] || source "${FZX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/core.sh"
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
# shellcheck source=./actions.sh
source "$(dirname "${BASH_SOURCE[0]}")/actions.sh"

# tasks::definition <file> <line> <kind>: the definition starting at the line: a make rule runs through its
# recipe lines (those starting with a tab), others up to the next blank line, at most 30 lines
tasks::definition() {
  awk -v from="$2" -v kind="$3" '
    NR < from { next }
    NR > from && kind == "make" && !/^\t/ { exit }
    NR > from && kind != "make" && /^[ \t]*$/ { exit }
    NR >= from + 30 { exit }
    { print }' "$1"
}

tasks::preview() {
  local id="${1:-}" dir kind name file line cmd gotask b=$'\e[1m' d=$'\e[38;5;244m' r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && b="" d="" r=""
  [[ "$id" == - ]] && return 0
  if [[ "${FZX_MODE:-selected}" == projects ]]; then
    printf '%s%s%s  %s%s%s\n\n' "$b" "${id##*/}" "$r" "$d" "${id/#$HOME/\~}" "$r"
    local index
    index="$(tasks::index_file)"
    [[ -f "$index" ]] || return 0
    awk -F'\t' -v dir="$id" -v d="$d" -v r="$r" '$1 == dir { printf "%s%-5s%s %s  %s%s%s\n", d, $2, r, $3, d, substr($4, 1, 80), r }' "$index"
    return 0
  fi
  IFS='|' read -r dir kind name <<< "$id"
  tasks::command "$dir" "$kind" "$name" cmd
  printf '%s%s:%s%s  %s%s%s\n%s%s%s\n%s$ %s%s\n' "$b" "${dir##*/}" "$name" "$r" "$d" "$kind" "$r" "$d" "${dir/#$HOME/\~}" "$r" "$d" "$cmd" "$r"
  if [[ "$kind" == just ]] && command -v just > /dev/null; then
    printf '\n'
    command just --justfile "$(tasks::justfile "$dir")" --working-directory "$dir" --show "$name" 2> /dev/null
  elif [[ "$kind" == task ]] && gotask="$(tasks::gotask)"; then
    printf '\n'
    command "$gotask" --dir "$dir" --summary "$name" 2> /dev/null
  elif read -r file line < <(tasks::locate "$dir" "$kind" "$name"); then
    printf '\n%s%s:%s%s\n' "$d" "${file#"$dir"/}" "$line" "$r"
    tasks::definition "$file" "$line" "$kind"
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && tasks::preview "$@"
