#!/usr/bin/env bash
# tasks menu entries

tasks::manifest() {
  fzx::entry tasks "Tasks here and the ones you picked"
  fzx::entry tasks:repos "Tasks of the projects you chose"
  fzx::entry tasks:all "Tasks of every repository"
}

tasks::applicable() {
  command -v make > /dev/null || command -v just > /dev/null || command -v npm > /dev/null
}

# tasks::summary <target>: here: the repository's tasks and the picks; the others from the last scan only
tasks::summary() {
  local index="$FZX_CACHE_DIR/tasks/index" state="$FZX_STATE_DIR/tasks" here n picked=0 chosen=0
  [[ -s "$state/selected" ]] && picked="$(wc -l < "$state/selected")"
  [[ -s "$state/projects" ]] && chosen="$(wc -l < "$state/projects")"
  case "$1" in
    tasks)
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
      here="$(tasks::here)" && n="$(tasks::scan "$here" | wc -l)" || n=0
      printf '%s here, %s picked\n' "$n" "$picked"
      ;;
    tasks:repos) printf '%s projects chosen\n' "$chosen" ;;
    tasks:all) [[ -s "$index" ]] && awk -F'\t' '{ d[$1] = 1 } END { printf "%d tasks in %d repositories\n", NR, length(d) }' "$index" ;;
  esac
}
