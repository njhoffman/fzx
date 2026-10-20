#!/usr/bin/env bash
# Global defaults. User and module config files override these by reassigning them.
# fzf also reads the user's FZF_DEFAULT_OPTS / FZF_DEFAULT_OPTS_FILE; options here are passed on the
# command line and take precedence where they overlap.

# shellcheck disable=SC2034  # every setting here is read by lib/ or the modules

# keys handled by fzx itself in every module
declare -gA FZX_KEYS=(
  [reload_hard]=ctrl-r
  [reload_soft]=alt-r
  [mode_next]=alt-0
  [mode_prev]=alt-9
  [back]=alt-left
  [popout]=ctrl-space
  [help]=f1
  [debug]=f2
)

# placement used when popping out into a tmux/Zellij floating pane (fzf --popup syntax)
FZX_POPUP_OPTS="center,80%"

# what happens to loaded data (set per module in its config.sh; users can override per module):
#   none         no cache: every load runs the source
#   session      cache for the life of the session tree, deleted when fzx exits
#   cache:<ttl>  also keep it across runs for the same module, args and directory; ttl as 90, 90s, 5m, 2h, 1d
FZX_PERSIST=session

# persistent cache entries older than this many days are removed by `fzx gc`
FZX_CACHE_MAX_AGE_DAYS=7

# menu entry summaries are cached per directory for this many seconds, and each may run this long
FZX_SUMMARY_TTL=300
FZX_SUMMARY_TIMEOUT=3

# usage statistics in $FZX_STATE_DIR/stats.tsv (see `fzx stats`); 0 turns recording off
FZX_STATS="${FZX_STATS:-1}"
# once the stats file passes 1 MiB, `fzx gc` drops rows older than this many days
FZX_STATS_MAX_AGE_DAYS=90

# SGR parameters (the part between ESC[ and m) for what fzx draws itself
declare -gA FZX_COLORS=(
  [mode_active]="38;5;45;1"
  [mode_inactive]="38;5;240"
  [menu_target]="38;5;110"
  [menu_summary]="38;5;244"
  [dim]="38;5;244"
)

# passed to fzf as --color when set (e.g. "dark,hl:208,border:240"); empty keeps the user's fzf colors
FZX_FZF_COLORS=""

# one query history per module ($FZX_STATE_DIR/history/<module>) instead of the user's global --history;
# 0 leaves fzf's history alone
FZX_HISTORY="${FZX_HISTORY:-1}"

# base fzf options for every module
FZX_FZF_OPTS=(
  --ansi
  "--with-shell=bash -c"
)
