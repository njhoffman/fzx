#!/usr/bin/env bash
# Global defaults. User and module config files override these by reassigning them.
# fzf also reads the user's FZF_DEFAULT_OPTS / FZF_DEFAULT_OPTS_FILE; options here are passed on the
# command line and take precedence where they overlap.

# shellcheck disable=SC2034  # every setting here is read by lib/ or the modules

# keys handled by fzx itself in every module; a comma list binds several keys to one action ("f12,ctrl-_")
declare -gA FZX_KEYS=(
  [reload_hard]=ctrl-r
  [reload_soft]=alt-r
  [mode_next]=alt-0
  [mode_prev]=alt-9
  # ctrl-_ is what ctrl-shift-_ (and ctrl-/) send; it takes ctrl-/ from fzf's toggle-wrap-word
  [sort_next]="f12,ctrl-_"
  [sort_prev]=f11
  [back]=alt-left
  [menu]=alt-o
  [escape]=esc
  [popout]="ctrl-^"
  # between a popup and the plain terminal only (alt-shift-6: terminals send ESC ^)
  [popup_toggle]="alt-^"
  [help]=f1
  [debug]=f2
  [actions]="ctrl-\\"
)

# toggles also flip with alt-1 .. alt-8, numbered by their order in components.tsv (alt-9 and alt-0 switch
# modes); a number another component or FZX_KEYS entry has is skipped. 0 turns this off
FZX_TOGGLE_DIGIT_KEYS=1

# how keys are shown in the help page, its grid and the menu preview: full (fzf's names: ctrl-x, alt-left),
# short (^X, M-left) or glyph (⌃X, ⌥←; needs a font with the symbols). Binds and FZX_KEYS keep fzf's names.
FZX_KEY_STYLE=full

# keys modules may not take: scrolling, query editing and the preview wrap toggle (alt-w) in the user's fzf
# options. A module binding on one of these is skipped with a warning in the log (fzx's own keys are not
# checked); drop a key from the list to let modules have it
FZX_RESERVED_KEYS=(ctrl-f ctrl-b ctrl-u ctrl-w ctrl-g alt-g ctrl-p ctrl-n up down alt-b alt-f alt-w scroll-up scroll-down)

# size and position of a plain popup (fzf's --popup on tmux/Zellij) and float (a floating tmux pane, tmux
# new-pane) by the width of the whole tmux window (not the calling pane: they cover its splits), else the
# terminal: "MINCOLS:SPEC" entries, the one with the largest MINCOLS that fits applies. SPEC is fzf's
# --popup syntax, [center|top|bottom|left|right][,W[%]][,H[%]]. Set per module in its config.sh;
# --popup=OPTS / --float=OPTS and popup:OPTS / float:OPTS placements win.
FZX_POPUP_LAYOUTS=("0:center,100%" "140:center,90%,85%" "220:center,80%")
# one fixed spec for every popup / float instead (set in the user's config.sh, it wins over every module's
# FZX_POPUP_LAYOUTS); empty uses the layouts, and center,80% when they are () or no entry fits
FZX_POPUP_OPTS=""
FZX_FLOAT_OPTS=""

# what the placement key (ctrl-^, FZX_KEYS[popout]) cycles through; entries that cannot run here are
# skipped (popup needs tmux or Zellij, split needs tmux, float needs a tmux with new-pane). With FZF_TMUX
# set (fzf's shell integration setting), FZF_TMUX_OPTS (fzf-tmux syntax) picks where fzx starts:
# -p[W[,H]] a popup, -d/-u/-l/-r [SIZE] a split, anything else a popup; --popup/--split/--float win:
#   inline              in the calling terminal
#   popup[:OPTS]        an fzf popup (--popup syntax; plain "popup" uses FZX_POPUP_LAYOUTS)
#   split:DIR[,SIZE]    a tmux split pane: DIR up, down, left or right; SIZE lines, columns or a percentage
#   float[:OPTS]        a floating tmux pane (plain "float" uses FZX_POPUP_LAYOUTS)
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

# once the log ($FZX_STATE_DIR/fzx.log) passes this many KiB, `fzx gc` moves it to fzx.log.1 (replacing the
# previous one) and the next line starts a new file
FZX_LOG_MAX_KB=1024

# menu entry summaries are cached per directory for this many seconds, and each may run this long
FZX_SUMMARY_TTL=300

# a directory of links named after each ghq repository (~/git/fzx -> ~/ghq/github.com/njhoffman/fzx), kept
# by the repos module's links action, the shell's `repos` and every clone fzx makes; empty: none. The
# default is ~/git when that directory exists
[[ -n "${FZX_REPOS_LINKS_DIR+x}" ]] || { FZX_REPOS_LINKS_DIR=""; [[ -d "$HOME/git" ]] && FZX_REPOS_LINKS_DIR="$HOME/git"; }
FZX_SUMMARY_TIMEOUT="${FZX_SUMMARY_TIMEOUT:-3}"
# a module whose menu entries (its manifest and applicable checks) take longer than this many seconds is
# left out of that menu listing, so one slow check cannot hold up the menu
FZX_APPLICABLE_TIMEOUT="${FZX_APPLICABLE_TIMEOUT:-2}"

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
  # round and triangle component styles: 256-color numbers for the background and text of on/off items
  [pill_on]=24
  [pill_on_fg]=195
  [pill_off]=237
  [pill_off_fg]=248
  [menu_target]="38;5;110"
  [menu_summary]="38;5;244"
  [menu_group]="1;38;5;244"
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
  # footer messages after an action that notifies (copies): done, failed
  [notify_ok]="38;5;116"
  [notify_fail]="38;5;203"
  # the icons before preview labels (lib/icons.sh)
  [preview_icon]="38;5;110"
)

# how the column a list is sorted by (ps, docker, tmux, ...) is drawn on top of its own color: decorations,
# space-separated, from
#   bold dim italic underline blink reverse overline underdouble undercurl underdotted underdashed
# The last four need a terminal that has underline styles (kitty, WezTerm, foot, ...; tmux passes them on),
# others show a plain underline; fzf drops overline. "" adds nothing. Setting FZX_COLORS[sorted] (raw SGR
# parameters) instead overrides both settings.
FZX_SORTED_STYLE="${FZX_SORTED_STYLE-underdashed}"
# the color of its underline: #rrggbb, a 256-color number, or "" for the text's own color
FZX_SORTED_UNDERLINE_COLOR="${FZX_SORTED_UNDERLINE_COLOR-#6e6e6e}"
# where the sort shows: header (a header row naming the columns, the sorted one marked; the rows plain), rows
# (the sorted column in every row, as above, and no header rows), or both. With header or both, every module
# that sorts by a column shows a header row in the modes that have a sort (switching between modes with and
# without one restarts fzf, which cannot change its header lines in place)
FZX_SORTED_SHOW="${FZX_SORTED_SHOW-header}"
# the header row: its columns' color (#rrggbb, a 256-color number, or "" for fzf's header color), the sorted
# column's decorations (names as above) and color, and its arrows ("ascending descending"; "" for none).
# FZX_COLORS[header_column] and [header_sorted] (raw SGR parameters) override them
FZX_HEADER_COLUMN_COLOR="${FZX_HEADER_COLUMN_COLOR-#007e95}"
FZX_SORTED_HEADER_STYLE="${FZX_SORTED_HEADER_STYLE-bold underline}"
FZX_SORTED_HEADER_COLOR="${FZX_SORTED_HEADER_COLOR-#00d7ff}"
FZX_SORTED_ARROWS="${FZX_SORTED_ARROWS-↑ ↓}"
# set by a module that sorts without a column to mark (files, todos): 0 shows no header row
FZX_SORTED_COLUMNS=1

# the border title, the path of screens ("menu:list > glyphs:nerd"): the color of where you came from and of
# the screen you are on (#rrggbb, a 256-color number, or "" for fzf's label color). The current one is also
# bold. FZX_COLORS[title] and [title_current] (raw SGR parameters) override them
FZX_TITLE_COLOR="${FZX_TITLE_COLOR-7}"
FZX_TITLE_CURRENT_COLOR="${FZX_TITLE_CURRENT_COLOR-15}"

# the prompt: {icon} is FZX_ICON (set per module in its config.sh) in FZX_COLORS[prompt_loaded], or in
# [prompt_loading] while the list loads. A prompt that is empty or blank leaves fzf's own prompt alone,
# so with no icon nothing changes. Prompts cannot contain ")".
FZX_ICON=""
# the menu's icon per mode ([mode]=glyph), for modes that differ from FZX_ICON; their colors are
# FZX_COLORS[<module>_icon_<mode>], the module's FZX_COLORS[<module>_icon]
declare -gA FZX_ICON_MODES=()
FZX_PROMPT="{icon}  "
FZX_PROMPT_LOADING="{icon}  "

# fzf events logged (info level) with the query, cursor, counts and size, e.g. "start,load,resize" or
# "all"; focus and change start a process per keystroke or cursor move, so tracing is off by default
FZX_TRACE="${FZX_TRACE:-}"

# how the component line (modes, toggles, sort) is drawn: minimal (colored text; a toggle's state is its
# color), icon (colored text, toggles with an on/off marker), round (rounded pills), triangle (powerline
# arrows), none (no line; keys keep working). round and triangle need a Nerd Font; the sort keeps its icon
# in every style. Empty: FZX_HEADER_STYLE (its older name, where bubble was round), else minimal
FZX_COMPONENT_STYLE=""
# the icon style's toggle markers: switch (the icon set's on/off switch) or dot (● / ○)
FZX_TOGGLE_ICONS=switch
# where it goes: footer, or header (merged with a header the module sets itself)
FZX_HEADER_POSITION=footer

# how long a footer message after an action that notifies (copy, copy-line, rows flagged notify) stays
# before the component line comes back, in seconds (sleep's syntax)
FZX_NOTIFY_SECONDS=2

# icons and colors from prettypath in the files and dirs lists: auto (when it is installed), 1 or 0
FZX_PRETTY="${FZX_PRETTY:-auto}"

# icons in rows and previews (lib/icons.sh): nerd (Nerd Font glyphs), unicode (plain symbols, for terminals
# without a Nerd Font) or none
FZX_ICONS="${FZX_ICONS:-nerd}"

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
