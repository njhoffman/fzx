#!/usr/bin/env bash
# tasks actions: run a task in its repository (with arguments asked first), pick tasks into the selected
# mode, choose projects, open a definition in the editor, scan again.

# shellcheck source=./source.sh
declare -F tasks::scan > /dev/null || source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# tasks::command <dir> <kind> <name> <var>: the command line that runs the task, from its repository
tasks::command() {
  local _dir="$1" _kind="$2" _name _run
  printf -v _name '%q' "$3"
  case "$_kind" in
    make) _run="make $_name" ;;
    just) _run="just $_name" ;;
    npm)
      # the package manager the lockfile belongs to
      if [[ -f "$_dir/pnpm-lock.yaml" ]]; then _run="pnpm run $_name"
      elif [[ -f "$_dir/yarn.lock" ]]; then _run="yarn run $_name"
      elif [[ -f "$_dir/bun.lockb" || -f "$_dir/bun.lock" ]]; then _run="bun run $_name"
      else _run="npm run $_name"; fi
      ;;
    task) _run="$(tasks::gotask || echo go-task) $_name" ;;
    cargo) _run="cargo $_name" ;;
    pdm) _run="pdm run $_name" ;;
    poe) _run="poe $_name" ;;
    hatch) _run="hatch run $_name" ;;
    *) _run="" ;;
  esac
  printf -v "$4" '%s' "$_run"
}

# tasks::locate <dir> <kind> <name>: "file line" of the task's definition
tasks::locate() {
  local dir="$1" kind="$2" name="$3" file="" pattern=""
  case "$kind" in
    make) file="$(tasks::makefile "$dir")" pattern="^([^:=#]* )?NAME( [^:=#]*)?[ \t]*::?([^=]|$)" ;;
    just) file="$(tasks::justfile "$dir")" pattern="^@?NAME([ \t:]|$)" ;;
    npm) file="$dir/package.json" pattern="^[ \t]*\"NAME\"[ \t]*:" ;;
    task) file="$(tasks::taskfile "$dir")" pattern="^[ \t]+['\"]?NAME['\"]?:" ;;
    cargo) file="$dir/.cargo/config.toml"; [[ -f "$file" ]] || file="$dir/.cargo/config"; pattern="^[ \t]*['\"]?NAME['\"]?[ \t]*=" ;;
    pdm | poe | hatch) file="$dir/pyproject.toml" pattern="^[ \t]*['\"]?NAME['\"]?[ \t]*=|^\[tool\.[a-z.]*\.NAME\]" ;;
  esac
  [[ -f "$file" ]] || return 1
  # the name is matched literally: its regex characters are escaped (through ENVIRON: awk -v would
  # process the pattern's backslashes)
  TASKS_PAT="$pattern" TASKS_NAME="$name" awk -v file="$file" -v kind="$kind" '
    BEGIN { pat = ENVIRON["TASKS_PAT"]; name = ENVIRON["TASKS_NAME"]; gsub(/[][\\.^$*+?(){}|]/, "\\\\&", name); gsub(/NAME/, name, pat) }
    # package.json: a script of that name, not a dependency of the same name
    kind == "npm" && /"scripts"[ \t]*:/ { inside = 1 }
    kind == "npm" && !inside { next }
    $0 ~ pat { print file, NR; found = 1; exit }
    END { exit !found }' "$file"
}

# tasks::_toggle <file> <line>: add the line to the file, or take it out when it is there
tasks::_toggle() {
  local file="$1" line="$2"
  mkdir -p -- "${file%/*}"
  touch -- "$file"
  if grep -qxF -- "$line" "$file"; then
    grep -vxF -- "$line" "$file" > "$file.$$"
    mv -f -- "$file.$$" "$file"
  else
    printf '%s\n' "$line" >> "$file"
  fi
}

# tasks::_run <id> [args]: the task, from its repository, then wait for a key
tasks::_run() {
  local dir kind name cmd rc
  IFS='|' read -r dir kind name <<< "$1"
  tasks::command "$dir" "$kind" "$name" cmd
  [[ -n "$cmd" ]] || { printf 'tasks: unknown kind: %s\n' "$kind" >&2; return 2; }
  [[ -n "${2:-}" ]] && cmd+=" $2"
  printf '\e[38;5;244m%s$ %s\e[0m\n' "${dir/#$HOME/\~}" "$cmd"
  (cd -- "$dir" && eval "$cmd")
  rc=$?
  if [[ -t 1 ]]; then
    printf '\n\e[38;5;244m(exit %s; press a key)\e[0m' "$rc"
    read -rsn1 < /dev/tty || :
  fi
  return "$rc"
}

# tasks::action <action> <id...>
tasks::action() {
  local action="${1:-}" mode="${FZX_MODE:-selected}" state id dir kind name args file line
  shift
  state="$(tasks::state_dir)"
  if [[ "$action" == rescan ]]; then
    rm -f -- "$(tasks::index_file)"
    return 0
  fi
  [[ "$mode" == projects && ("$action" == run || "$action" == pick) ]] && action=choose
  for id in "$@"; do [[ "$id" == - ]] && return 0; done
  case "$action" in
    run) tasks::_run "${1:-}" ;;
    args)
      read -r -e -p "$(printf '\e[1m%s\e[0m args: ' "${1##*|}")" args < /dev/tty || return 0
      tasks::_run "${1:-}" "$args"
      ;;
    pick)
      for id in "$@"; do
        IFS='|' read -r dir kind name <<< "$id"
        tasks::_toggle "$state/selected" "$dir"$'\t'"$kind"$'\t'"$name"
      done
      ;;
    choose)
      for id in "$@"; do tasks::_toggle "$state/projects" "$id"; done
      ;;
    edit)
      IFS='|' read -r dir kind name <<< "${1:-}"
      read -r file line < <(tasks::locate "$dir" "$kind" "$name") || { file="$dir"; line=1; }
      "${EDITOR:-vi}" "+$line" "$file"
      ;;
    *)
      printf 'tasks: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then tasks::action "$@"; fi
