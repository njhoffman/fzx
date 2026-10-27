#!/usr/bin/env bash
# recent defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/recent/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS FZX_COLORS

# prompt icon (Nerd Font); FZX_ICON="" keeps fzf's own prompt
FZX_ICON="󰋚"

# the icon's color in the menu
FZX_COLORS[recent_icon]="38;5;180"

FZX_KEYS[recent.dir]=ctrl-o # browse the directory (a file's own) in the files module

# telescope-frecency's database (nvim), for the nvim mode (the default when it exists)
FZX_RECENT_NVIM_DB="${FZX_RECENT_NVIM_DB:-$HOME/.local/share/nvim/file_frecency.sqlite3}"

# `fzx jump --files` (v): the mode it matches with ("" = the default mode), and how many matches it opens
# at once before it asks with a picker instead
FZX_RECENT_JUMP_MODE=""
FZX_RECENT_JUMP_MAX=10

# z.lua for the zlua mode (the jump default when found): its script, "" to look in $ZLUA_SCRIPT, zinit's
# plugin directories and ~/.local/share/z.lua, or "none"; and the Lua that runs it
FZX_RECENT_ZLUA="${FZX_RECENT_ZLUA-}"
FZX_RECENT_ZLUA_LUA="${FZX_RECENT_ZLUA_LUA:-${ZLUA_LUAEXE:-lua}}"

# the directories `fzx jump` (g, gg, alt-j) matches with: a directory mode of this module (zlua, dirs,
# fasd-dirs, visited) or MODULE:MODE of another (dirs:bookmarks); "" takes zlua, else dirs, else fasd-dirs
FZX_RECENT_DIRS_JUMP_MODE=""
