#!/usr/bin/env bash
# applications actions: launch detached (gtk-launch, else dex), edit the desktop file, copy the commands

# shellcheck source=./preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/preview.sh"

# applications::exec_line <exec> <file>: an Exec value as a shell command: the arguments it would be given
# dropped (%f %F %u %U and the deprecated %d %D %n %N %v %m), %i %c %k filled in, %% a percent
applications::exec_line() {
  local line="${1//%%/$'\001'}" file="$2" icon name
  icon="$(applications::_field "$file" Icon)"
  name="$(applications::_field "$file" Name)"
  line="${line//%i/${icon:+--icon ${icon@Q}}}"
  line="${line//%c/${name@Q}}"
  line="${line//%k/${file@Q}}"
  line="$(sed -E 's/ *%[fFuUdDnNvm]//g' <<< "$line")"
  printf '%s' "${line//$'\001'/%}"
}

# applications::run_action <file>#action:<key>: the action's Exec line, detached, in the entry's Path, in a
# terminal when the entry asks for one: neither gtk-launch nor dex can start an action
applications::run_action() {
  local file="${1%#action:*}" action="${1##*#action:}" exec line dir
  exec="$(applications::_action_field "$file" "$action" Exec)"
  [[ -n "$exec" ]] || { printf 'applications: no Exec for %s in %s\n' "$action" "$file" >&2; return 1; }
  line="$(applications::exec_line "$exec" "$file")"
  dir="$(applications::_field "$file" Path)"
  [[ -d "$dir" ]] || dir="$PWD"
  if [[ "$(applications::_field "$file" Terminal)" == true ]]; then
    (cd "$dir" && command setsid -f "${TERMINAL:-x-terminal-emulator}" -e sh -c "$line" > /dev/null 2>&1 < /dev/null)
  else
    (cd "$dir" && command setsid -f sh -c "$line" > /dev/null 2>&1 < /dev/null)
  fi
}

# applications::launch <file...>: an action's row by its Exec line, each entry through gtk-launch by its ID (the file must sit in an
# applications directory, as every listed one does), else dex by its path; detached from fzx
applications::launch() {
  local file id rc=0 dir
  for file; do
    if [[ "$file" == *"#action:"* ]]; then
      applications::run_action "$file" || rc=1
      continue
    fi
    [[ -f "$file" ]] || continue
    if command -v gtk-launch > /dev/null; then
      id=""
      while IFS= read -r dir; do
        [[ "$file" == "$dir"/* ]] && { id="${file#"$dir"/}" && id="${id//\//-}"; break; }
      done < <(applications::dirs)
      [[ -n "$id" ]] || id="${file##*/}"
      command setsid -f gtk-launch "$id" > /dev/null 2>&1 < /dev/null || rc=1
    elif command -v dex > /dev/null; then
      command setsid -f dex "$file" > /dev/null 2>&1 < /dev/null || rc=1
    else
      printf 'applications: needs gtk-launch or dex\n' >&2
      return 1
    fi
  done
  return "$rc"
}

# applications::action <action> <file...>
applications::action() {
  local action="${1:-}" f out=()
  shift
  case "$action" in
    launch | launch-stay) applications::launch "$@" ;;
    edit)
      for f; do f="${f%#action:*}"; [[ -f "$f" ]] && out+=("$f"); done
      ((${#out[@]})) || return 0
      "${VISUAL:-${EDITOR:-vi}}" "${out[@]}"
      ;;
    copy-exec)
      fzx::require builtin
      for f; do [[ -f "$f" ]] && out+=("$(applications::_field "$f" Exec)"); done
      ((${#out[@]})) || return 0
      printf '%s\n' "${out[@]}" | fzx::clip
      ;;
    *)
      printf 'applications: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" applications
  applications::action "$@"
}
