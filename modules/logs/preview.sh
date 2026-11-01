#!/usr/bin/env bash
# logs preview: the last FZX_LOGS_LINES lines of a file, unit journal or container.
# shellcheck source=../../lib/render.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/render.sh"

# logs::show <kind> <target> <follow 0|1>: print (or follow) a log
logs::show() {
  local kind="$1" target="$2" follow="$3" lines="${FZX_LOGS_LINES:-200}" f=()
  ((follow)) && f=(-f)
  case "$kind" in
    file)
      if ((follow)); then
        command tail -n "$lines" -F -- "$target"
      else
        command tail -n "$lines" -- "$target"
      fi
      ;;
    unit-user | unit-system)
      SYSTEMD_COLORS=1 command journalctl "--${kind#unit-}" -u "$target" -n "$lines" --no-pager "${f[@]}"
      ;;
    docker) command docker logs --tail "$lines" "${f[@]}" "$target" 2>&1 ;;
    *)
      printf 'logs: unknown kind: %s\n' "$kind" >&2
      return 2
      ;;
  esac
}

# logs::preview <kind> <target>
logs::preview() {
  if [[ "${1:-}" == file ]]; then
    logs::show "$1" "${2:-}" 0 | fzx::render_text --language log --style plain
  else
    logs::show "${1:-}" "${2:-}" 0
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && logs::preview "$@"
