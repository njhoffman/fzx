#!/usr/bin/env bash
# tasks actions: run a task in its repository (with arguments asked first), pick tasks into the selected
# mode, choose projects, open a definition in the editor, scan again, paste the command line into a tmux
# pane (--paste).

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

# tasks::paste_line <var> <id...>: the command line that runs the tasks from the current directory:
# "CMD" for a task of this directory, "cd DIR && CMD" for another's; several are parenthesized and joined
# with && (a cd stays inside its parentheses). DIR is quoted, with a leading ~ for $HOME.
tasks::paste_line() {
  local _var="$1" _id _dir _kind _name _cmd _d _here _one _line="" _n=$(($# - 1))
  shift
  _here="$(pwd -P)"
  for _id in "$@"; do
    IFS='|' read -r _dir _kind _name <<< "$_id"
    tasks::command "$_dir" "$_kind" "$_name" _cmd
    [[ -n "$_cmd" ]] || continue
    if [[ "$_dir" == "$_here" ]]; then
      _one="$_cmd"
    else
      # a literal ~: the line is pasted for the shell to expand
      # shellcheck disable=SC2088
      if [[ "$_dir" == "$HOME"/* ]]; then printf -v _d '~/%q' "${_dir#"$HOME"/}"; else printf -v _d '%q' "$_dir"; fi
      _one="cd $_d && $_cmd"
      ((_n > 1)) && _one="($_one)"
    fi
    _line+="${_line:+ && }$_one"
  done
  printf -v "$_var" '%s' "$_line"
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
  # paste <pane> <id...>: the command line into a tmux pane (--paste), bracketed: nothing is submitted.
  # Projects: a cd into the repositories. The tmux server pastes 0.3s later, once the popup has closed.
  if [[ "$action" == paste ]]; then
    local pane="${1:-}" text=""
    shift
    [[ "$pane" =~ ^%[0-9]+$ ]] || { printf 'tasks: --paste needs a tmux pane id (%%N): %s\n' "$pane" >&2; return 2; }
    for id in "$@"; do [[ "$id" == - ]] && return 0; done
    (($#)) || return 0
    if [[ "$mode" == projects ]]; then
      if [[ "$1" == "$HOME"/* ]]; then printf -v text 'cd ~/%q' "${1#"$HOME"/}"; else printf -v text 'cd %q' "$1"; fi
    else
      tasks::paste_line text "$@"
    fi
    [[ -n "$text" ]] || return 0
    printf '%s' "$text" | tmux load-buffer -b fzx-tasks - &&
      tmux run-shell -b -d 0.3 "tmux paste-buffer -p -d -b fzx-tasks -t $pane"
    return
  fi
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
