#!/usr/bin/env bash
# recent menu entries: the files (the default mode), then the directory trackers that are installed

recent::manifest() {
  fzx::entry recent "Recently and frequently used files"
  fzx::entry recent:fasd "Frecent files (fasd)"
  fzx::entry recent:zlua "Frecent directories (z.lua)"
  fzx::entry recent:dirs "Frecent directories (zoxide)"
  fzx::entry recent:visited "Recently visited directories (fasd)"
}

recent::applicable() {
  local zl
  case "$1" in
    # its own entry only when it is not the default already (no nvim database)
    recent:fasd) [[ -f "$FZX_RECENT_NVIM_DB" ]] && command -v fasd > /dev/null ;;
    recent:zlua)
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
      recent::zlua zl
      ;;
    recent:dirs) command -v zoxide > /dev/null ;;
    recent:visited) command -v fasd > /dev/null ;;
    *) [[ -f "$FZX_RECENT_NVIM_DB" ]] || command -v fasd > /dev/null ;;
  esac
}

recent::summary() {
  local zl
  case "$1" in
    recent)
      if [[ -f "$FZX_RECENT_NVIM_DB" ]]; then
        printf '%s\n' "$(fzx::plural "$(command sqlite3 -readonly "$FZX_RECENT_NVIM_DB" 'SELECT COUNT(*) FROM files')" file)"
      else
        printf '%s\n' "$(fzx::plural "$(command fasd -f -l 2> /dev/null | wc -l)" file)"
      fi
      ;;
    recent:fasd) printf '%s\n' "$(fzx::plural "$(command fasd -f -l 2> /dev/null | wc -l)" file)" ;;
    recent:zlua)
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
      recent::zlua zl || return 0
      printf '%s\n' "$(fzx::plural "$(command "$FZX_RECENT_ZLUA_LUA" "$zl" -l 2> /dev/null | wc -l)" 'known directory' 'known directories')"
      ;;
    recent:dirs) printf '%s\n' "$(fzx::plural "$(command zoxide query --list 2> /dev/null | wc -l)" 'known directory' 'known directories')" ;;
    recent:visited) printf '%s\n' "$(fzx::plural "$(command fasd -d -l 2> /dev/null | wc -l)" 'known directory' 'known directories')" ;;
    *) return 0 ;;
  esac
}
