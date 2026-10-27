#!/usr/bin/env bash
# shellcheck disable=SC2034
FZX_ICON=""
# shellcheck disable=SC2034
declare -gA FZX_KEYS
FZX_KEYS[tmux.capture]=ctrl-o
FZX_PERSIST=none
# Optional installed helpers used by the tmux.* aliases. Override for another layout.
FZX_TMUX_HELPERS="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts"
# shellcheck disable=SC2034
declare -gA FZX_COLORS
FZX_COLORS[tmux_name]='38;5;81'
FZX_COLORS[tmux_value]='38;5;150'
FZX_COLORS[tmux_scope]='38;5;250'
FZX_COLORS[tmux_key]='1;38;5;255'
FZX_COLORS[tmux_changed]='1;38;5;159'
FZX_COLORS[tmux_dim]='38;5;245'
FZX_COLORS[tmux_title]='1;38;5;111'
FZX_COLORS[tmux_flag]='38;5;176'
