#!/usr/bin/env bash
# logs source. Lines are "kind<TAB>target<TAB>display", kind being file, unit-user, unit-system or docker.
# Mode from $FZX_MODE: files (default), units, docker.

# logs::age <seconds>: short age with a color that fades from bright to dim
logs::age() {
  local s="$1" clr text
  if ((s < 60)); then
    clr="38;5;46" text="${s}s"
  elif ((s < 3600)); then
    clr="38;5;34" text="$((s / 60))m"
  elif ((s < 86400)); then
    clr="38;5;28" text="$((s / 3600))h"
  else
    clr="38;5;240" text="$((s / 86400))d"
  fi
  printf '\e[%sm%4s\e[0m' "$clr" "$text"
}

logs::source_files() {
  local name path mtime glob icon
  local -A seen=() files=()
  fzx::require icons
  fzx::icon file icon
  for name in "${!FZX_LOGS_FILES[@]}"; do
    files[$name]="${FZX_LOGS_FILES[$name]}"
  done
  for glob in "${FZX_LOGS_GLOBS[@]}"; do
    for path in $glob; do
      [[ -f "$path" ]] || continue
      name="${path##*/}"
      name="${name%.log}"
      [[ -n "${files[$name]:-}" ]] && name="${path%/*}/$name" name="${name/#$HOME/\~}"
      files[$name]="$path"
    done
  done
  # most recently written first
  for name in "${!files[@]}"; do
    path="${files[$name]}"
    [[ -f "$path" && -r "$path" && -z "${seen[$path]:-}" ]] || continue
    seen[$path]=1
    mtime="$(stat -c %Y -- "$path")" || continue
    printf '%s\tfile\t%s\t%s  %s%-28s \e[38;5;244m%s\e[0m\n' "$mtime" "$path" \
      "$(logs::age $((EPOCHSECONDS - mtime)))" "${icon:+$'\e[38;5;110m'$icon$'\e[0m' }" "$name" "${path/#$HOME/\~}"
  done | sort -t $'\t' -k1,1nr | cut -f2-
}

logs::source_units() {
  local manager unit=""
  fzx::require icons
  fzx::icon unit unit
  for manager in user system; do
    SYSTEMD_COLORS=0 command systemctl "--$manager" list-units --type=service --state=running,failed \
      --no-legend --plain --no-pager 2> /dev/null |
      awk -v m="$manager" -v glyph="${unit:-●}" '
        { unit = $1; active = $3; desc = ""; for (i = 5; i <= NF; i++) desc = desc (i > 5 ? " " : "") $i
          icon = active == "failed" ? "\033[38;5;203m" glyph "\033[0m" : "\033[38;5;114m" glyph "\033[0m"
          printf "unit-%s\t%s\t%s \033[38;5;244m%-6s\033[0m %-44s \033[38;5;244m%s\033[0m\n", m, unit, icon, m, unit, desc }'
  done
}

logs::source_docker() {
  command -v docker > /dev/null || return 0
  fzx::require icons
  fzx::icon_vars running stopped
  command docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}' 2> /dev/null |
    awk -F'\t' "${FZX_ICON_VARS[@]}" '
      { icon = $4 ~ /^Up/ ? "\033[38;5;114m" (icon_running == "" ? "●" : icon_running) "\033[0m" : "\033[38;5;240m" (icon_stopped == "" ? "○" : icon_stopped) "\033[0m"
        printf "docker\t%s\t%s %-30s %-34s \033[38;5;244m%s\033[0m\n", $1, icon, $2, $3, $4 }'
}

logs::source() {
  case "${FZX_MODE:-files}" in
    files) logs::source_files ;;
    units) logs::source_units ;;
    docker) logs::source_docker ;;
    *)
      printf 'logs: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

# run directly, the log list comes from the config layers like under fzx
[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" logs
  logs::source "$@"
}
