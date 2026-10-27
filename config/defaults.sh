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
  [sort_next]=f12
  [sort_prev]=f11
  [back]=alt-left
  [escape]=esc
  [popout]="ctrl-^"
  [help]=f1
  [debug]=f2
  [actions]="ctrl-\\"
)

# keys modules may not take: scrolling and query editing in the user's fzf options. A module binding on one
# of these is skipped with a warning in the log (fzx's own keys are not checked); drop a key from the list
# to let modules have it
FZX_RESERVED_KEYS=(ctrl-f ctrl-b ctrl-u ctrl-w ctrl-g alt-g ctrl-p ctrl-n up down alt-b alt-f scroll-up scroll-down)

# placement of a popup (fzf's --popup on tmux/Zellij) and of a floating tmux pane (tmux new-pane), both in
# fzf's --popup syntax: [center|top|bottom|left|right][,W[%]][,H[%]]
FZX_POPUP_OPTS="center,80%"
FZX_FLOAT_OPTS="center,80%"

# what the placement key (ctrl-^, FZX_KEYS[popout]) cycles through; entries that cannot run here are
# skipped (popup needs tmux or Zellij, split needs tmux, float needs a tmux with new-pane). With FZF_TMUX
# set (fzf's shell integration setting), FZF_TMUX_OPTS (fzf-tmux syntax) picks where fzx starts:
# -p[W[,H]] a popup, -d/-u/-l/-r [SIZE] a split, anything else a popup; --popup/--split/--float win:
#   inline              in the calling terminal
#   popup[:OPTS]        an fzf popup (--popup syntax; plain "popup" uses FZX_POPUP_OPTS)
#   split:DIR[,SIZE]    a tmux split pane: DIR up, down, left or right; SIZE lines, columns or a percentage
#   float[:OPTS]        a floating tmux pane (plain "float" uses FZX_FLOAT_OPTS)
FZX_PLACEMENTS=(inline "split:down,40%" popup float)

# the preview window by terminal width: "MINCOLS:SPEC" entries, the one with the largest MINCOLS that fits
# applies (on start and on every resize, through change-preview-window). SPEC is in --preview-window
# syntax on top of the module's own --preview-window; empty means the module's own, "hidden" hides it. A
# preview hidden by hand stays hidden across breakpoints. Set per module in its config.sh; () turns it off.
FZX_PREVIEW_LAYOUTS=("0:down,50%,border-top" "120:")

# what happens to loaded data (set per module in its config.sh; users can override per module):
#   none         no cache: every load runs the source
#   session      cache for the life of the session tree, deleted when fzx exits
#   cache:<ttl>  also keep it across runs for the same module, args and directory; ttl as 90, 90s, 5m, 2h, 1d
FZX_PERSIST=session

# persistent cache entries older than this many days are removed by `fzx gc`
FZX_CACHE_MAX_AGE_DAYS=7

# menu entry summaries are cached per directory for this many seconds, and each may run this long
FZX_SUMMARY_TTL=300
FZX_SUMMARY_TIMEOUT="${FZX_SUMMARY_TIMEOUT:-3}"

# usage statistics in $FZX_STATE_DIR/stats.tsv (see `fzx stats`); 0 turns recording off
FZX_STATS="${FZX_STATS:-1}"
# once the stats file passes 1 MiB, `fzx gc` drops rows older than this many days
FZX_STATS_MAX_AGE_DAYS=90

# SGR parameters (the part between ESC[ and m) for what fzx draws itself
declare -gA FZX_COLORS=(
  [mode_active]="38;5;45;1"
  [mode_inactive]="38;5;240"
  [toggle_on]="38;5;49"
  [toggle_off]="38;5;240"
  [sort]="38;5;45"
  # bubble and triangle header styles: 256-color numbers for the background and text of on/off items
  [pill_on]=39
  [pill_on_fg]=16
  [pill_off]=237
  [pill_off_fg]=248
  [menu_target]="38;5;110"
  [menu_summary]="38;5;244"
  [dim]="38;5;244"
  # the shortcuts page (f1): keycaps, and the section titles for this screen, fzx, global and free keys
  [help_key]="1;38;5;255;48;5;236"
  [help_module]="1;38;5;45"
  [help_fzx]="1;38;5;213"
  [help_global]="1;38;5;110"
  [help_free]="1;38;5;114"
  # the prompt icon once the list is loaded, and while it loads
  [prompt_loaded]="38;5;45;1"
  [prompt_loading]="38;5;240"
)

# the prompt: {icon} is FZX_ICON (set per module in its config.sh) in FZX_COLORS[prompt_loaded], or in
# [prompt_loading] while the list loads. A prompt that is empty or blank leaves fzf's own prompt alone,
# so with no icon nothing changes. Prompts cannot contain ")".
FZX_ICON=""
FZX_PROMPT="{icon}  "
FZX_PROMPT_LOADING="{icon}  "

# fzf events logged (info level) with the query, cursor, counts and size, e.g. "start,load,resize" or
# "all"; focus and change start a process per keystroke or cursor move, so tracing is off by default
FZX_TRACE="${FZX_TRACE:-}"

# how the component line (modes, toggles, sort) is drawn: minimal (colored text), bubble (rounded pills),
# triangle (powerline arrows), none (no line; keys keep working). bubble and triangle need a Nerd Font.
FZX_HEADER_STYLE=minimal
# where it goes: footer, or header (merged with a header the module sets itself)
FZX_HEADER_POSITION=footer

# icons and colors from prettypath in the files and dirs lists: auto (when it is installed), 1 or 0
FZX_PRETTY="${FZX_PRETTY:-auto}"

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
