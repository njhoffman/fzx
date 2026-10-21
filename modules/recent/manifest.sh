#!/usr/bin/env bash
# recent menu entries

recent::manifest() {
  fzx::entry recent "Recently and frequently used files"
}

recent::applicable() {
  [[ -f "$FZX_RECENT_NVIM_DB" ]] || command -v fasd > /dev/null
}
