#!/usr/bin/env bash
# applications actions: launch detached (gtk-launch, else dex), edit the desktop file, copy the commands

# shellcheck source=./preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/preview.sh"

# applications::launch <file...>: each entry through gtk-launch by its ID (the file must sit in an
# applications directory, as every listed one does), else dex by its path; detached from fzx
applications::launch() {
  local file id rc=0 dir
  for file; do
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
      for f; do [[ -f "$f" ]] && out+=("$f"); done
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
