#!/usr/bin/env bash
# logs menu entries

logs::manifest() {
  fzx::entry logs "Log files, most recently written first"
  fzx::entry logs:units "Journals of running and failed services"
  fzx::entry logs:docker "Docker container logs"
}

logs::applicable() {
  case "$1" in
    logs:units) command -v journalctl > /dev/null ;;
    logs:docker) command -v docker > /dev/null ;;
    *) return 0 ;;
  esac
}

logs::summary() {
  local n
  case "$1" in
    logs:units)
      n="$(SYSTEMD_COLORS=0 systemctl --failed --no-legend --plain --no-pager 2> /dev/null | wc -l)"
      printf '%s\n' "$(fzx::plural "$n" 'failed system unit')"
      ;;
    logs:docker)
      n="$(docker ps -q 2> /dev/null | wc -l)" || return 1
      printf '%s\n' "$(fzx::plural "$n" 'running container')"
      ;;
    logs)
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
      n="$(logs::source_files | wc -l)"
      printf '%s\n' "$(fzx::plural "$n" 'log file')"
      ;;
  esac
}
