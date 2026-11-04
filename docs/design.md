# fzx design

fzx is a manager and wrapper for fzf "modules": self-contained folders that produce data, previews and
actions, which fzx launches with shared defaults, persistent session state, logging and statistics.

## Lessons from previous attempts

| Attempt | Runtime model | Where it stalled |
|---|---|---|
| `fzfmenu` (zsh) | `while` loop around `fzf --expect`; every mode/sort/toggle change kills and restarts fzf | One library probing for hook functions; modules not standalone or testable |
| `fzf` / `fzfer` (bash) | One long-lived fzf, piddir state, large inline transform strings | Never got past bootstrap; no module contract |
| `fzfg` (Go) | YAML compiled into `FZF_DEFAULT_OPTS` | No runtime, state or navigation; heavy validation infrastructure |

Each started with infrastructure and never fixed the process model or the module contract. Those two
decisions drive everything else, so they are fixed here.

## Decisions

1. **Core language: bash.** fzf callbacks are shell commands and module loaders import their source
   script. The module contract is plain executables, so the core can be ported later if needed.
2. **Manifest/config format: sourced bash.** No dependencies; layering is sourcing order. No schema
   validation (configs are code).
3. **Granularity:** a module is one domain (`git`, `ps`); subscreens are *modes* inside a module. Menu
   entries point at `module:mode`.
4. **Callback latency is a hard rule:** `fzx _cb` loads `core.sh` plus only the libs the handler needs,
   never the whole library.

## Process model

Every fzf callback (`reload`, `transform`, `preview`, `execute`) runs in a fresh process. The program is
therefore a coordinator plus many short-lived callbacks, and all state lives on disk in a session
directory.

On start, `fzx` creates a session and exports `FZX_SESSION=<sid>` before launching fzf. Callbacks inherit
it, so bind strings never interpolate state and stay short:

```
--bind 'start:reload:fzx _cb load'
--bind 'ctrl-r:reload:fzx _cb source'
--preview 'fzx _cb preview {1}'
```

All logic lives in bash functions behind `fzx _cb`, which are unit-testable. fzf also exports
`FZF_QUERY`, `FZF_KEY`, `FZF_POS`, `FZF_SOCK`, etc. to callbacks.

fzf is always launched with `--with-shell 'bash -c'` (the login shell may be zsh) and stdin from
`/dev/null`; data arrives through `start:reload`, so the first launch and a resume share one path.

Only the owner (below) runs fzf as a child. Every other launch (`--resume`, a mode restart, navigation)
`exec`s fzf, so a `become()` chain stays at constant depth (owner bash, then fzf) no matter how often the
user navigates.

The user's `FZF_DEFAULT_OPTS` / `FZF_DEFAULT_OPTS_FILE` are inherited. fzx and module options are passed
on the command line and therefore win where they overlap.

## Session directory

`$XDG_RUNTIME_DIR/fzx/sessions/<sid>/` (falls back to `$TMPDIR/fzx-$UID/fzx`).

```
meta/         one file per key: module, module_dir, cwd, owner_pid, owner_start, started_ms,
              args (NUL-separated), cache_key, root, parent (children only), keep (--keep);
              rewritten on every launch: modes (NUL-separated), persist, preview_layouts
              (tab-separated)
state/        one file per key, mutable: mode, query, pos (saved before every become()),
              placement, relaunch, current (root only: the tree's placement, a pending relaunch
              for a placement change, the session on screen), fresh (next load runs the source),
              layout (the FZX_PREVIEW_LAYOUTS entry applied last), preview_hidden (a preview
              hidden by hand, saved before every become())
data/<mode>   cached source output, one file per mode
children/     <hash(module, args)> -> child sid, so navigating to the same target reuses its session (a
              hidden mode's target is module:mode: its session has that mode alone)
fzf.sock      fzf --listen socket
```

One file per key (rather than one `key=value` file) makes concurrent callback writes safe without
locking, and makes the state inspectable with `ls`/`cat`.

### Session tree, ownership and lifecycle

Navigating to another module or subscreen creates a **child session** (`meta/parent`), and every session
in a tree records the root's id in `meta/root`. "Back" resumes the parent, so no separate history stack is
needed. Each session keeps exactly one module, its own cache and its saved query and cursor position, so
going back and forth costs a cache read.

The process that creates the root session is its **owner**. It runs fzf as a child (never `exec`), so it is
still waiting when fzf replaces itself through `become(...)`, and it applies cleanup when the whole chain
finishes. Processes started with `--resume` never clean up. The owner destroys the root and every session whose
`meta/root` is the root.

`--keep` / `FZX_KEEP=1` skips the cleanup and marks the root with `meta/keep`.

**Dead sessions** (owner crashed or its terminal was killed) are swept by `fzx gc`, which also runs
quietly before every new session. A tree is dead when its owner pid no longer runs *with the same start
time* (`meta/owner_start`, field 22 of `/proc/<pid>/stat`), so a recycled pid does not keep a tree
alive. Kept trees survive until `fzx gc --all`; children whose root is gone are removed too.

### Persist policies

Set per module with `FZX_PERSIST` in its `config.sh`; a user can override it per module in
`~/.config/fzx/modules/<m>/config.sh`. The resolved value is recorded in `meta/persist` at launch, so
callbacks need not load config.

| Policy | During the session | After fzx exits |
|---|---|---|
| `none` | no cache; every load runs the source | nothing |
| `session` (default) | `data/<mode>` | deleted with the tree |
| `cache:<ttl>` (`90`, `90s`, `5m`, `2h`, `1d`) | `data/<mode>` | also written through to `$XDG_CACHE_HOME/fzx/<module>/<cache_key>/<mode>` on every successful source |

`cache_key` is a hash of module, cwd and args, so "the same view" in the same directory reuses its data.
A load with no session cache serves a persistent entry younger than the ttl and seeds the session cache
from it; an older entry is refreshed by running the source. A failing source never touches either
cache. `fzx gc` removes persistent entries older than `FZX_CACHE_MAX_AGE_DAYS` (default 7).
A mode flagged `nopersist` in components.tsv stays at `session` under a `cache:<ttl>` module: its rows
follow the query (`files:grep`), so a later launch must not start with the last query's hits.

### Reloading and navigation

| Operation | Mechanism |
|---|---|
| Operation | Key | Mechanism |
|---|---|---|
| Hard reload | `ctrl-r` | `reload(fzx _cb source)`: rerun the source, rewrite `data/<mode>` |
| Soft reload | `alt-r` | `transform(fzx _cb nav resume)`: save query/pos, `become(fzx --resume <sid>)`; options re-resolved, data from cache |
| Mode change | `alt-0` / `alt-9` | `transform(fzx _cb mode next\|prev)`: `change-border-label`, `change-footer`, `reload`; fzf keeps running and keeps the query. When the mode left or entered has the `restart` flag, it restarts instead: `become(fzx --resume <sid> -m :<mode>)` |
| Go to module/subscreen | module-defined | `transform(fzx _cb nav goto <module[:mode]> [args])`: save query/pos, find or create the child, `become(fzx --resume <child>)` |
| Back | `alt-left` | `transform(fzx _cb nav back)`: `become` the parent; `bell` at the root |
| Menu | `alt-o` | `transform(fzx _cb nav menu)`: `become` the menu in the session's path, else a new menu as a child, so `alt-left` returns; not bound in the menu. In tmux, `M-o` opens the menu in a popup unless the pane runs fzf, which then gets the key |
| Escape | `esc` (`FZX_KEYS[escape]`) | `transform(fzx _cb nav escape)`: `become` the parent; `abort` at the root. Ctrl-C keeps fzf's abort behavior. Standalone modules keep fzf's Escape behavior. |
| Placement | `ctrl-^` | `transform(fzx _cb nav placement next)`: the next `FZX_PLACEMENTS` entry that can run here into the root's `state/placement`, save query/pos; inline/popup: `become(fzx --resume <sid>)`; into or out of a tmux pane (split, float): `state/relaunch` + `abort`, and the owner relaunches; `bell` when there is nowhere to go |
| Popup or inline | `alt-^` (`FZX_KEYS[popup_toggle]`) | `transform(fzx _cb nav placement popup-toggle)`: from a popup to inline, from anywhere else (inline, a split, a float) to the first popup entry of `FZX_PLACEMENTS` (none: a plain popup), as the placement key moves; `bell` where no popup can run. Terminals send ESC ^ for alt-shift-6 |

**Placement** belongs to the session tree (`state/placement` on the root): `inline`, `popup[:OPTS]`,
`split:DIR[,SIZE]` (DIR up/down/left/right) or `float[:OPTS]`. `fzx -m ps --popup[=OPTS]`,
`--split[=DIR,SIZE]` or `--float[=OPTS]` starts there; ctrl-^ cycles through `FZX_PLACEMENTS` (default
`inline split:down,40% popup float`), skipping entries that cannot run here (popups need tmux 3.3+ or
Zellij, splits tmux, floats a tmux with `new-pane`).

Floats are floating tmux panes (`tmux new-pane`), made by the owner like splits (`fzx::_fzf_pane`), not
fzf's `--popup`: inside one, `become()` keeps working as in a split. OPTS use the `--popup` syntax
(`[center|top|bottom|left|right][,W[%]][,H[%]]`), resolved to cells against the window's size, since
`new-pane` places a pane by its top-left corner.

**Popup geometry.** A plain `popup` or `float` (no OPTS) is sized by `FZX_POPUP_LAYOUTS`, `MINCOLS:SPEC`
entries like the preview layouts: the entry with the largest MINCOLS at most the width of the whole tmux
window applies (`#{window_width}`, not the calling pane: popups and floats cover its splits; outside tmux
the terminal's width). SPEC is in `--popup` syntax. Modules set their own in `config.sh` (default
`0:center,100%` `140:center,90%,85%` `220:center,80%`). `FZX_POPUP_OPTS` / `FZX_FLOAT_OPTS`, when set, are
one fixed spec that wins over the layouts (a user's global setting, which no module undoes); with no
layouts, or none that fits, `center,80%`. Explicit OPTS (`--popup=OPTS`, `popup:OPTS` placements) win over
both. Every popup launch asks for the popup again, so a `become()` into another module opens at that
module's size; the width is read at each launch.

**Popups follow the window.** tmux does not resize a running popup when its window grows, and only clamps it
when the window shrinks, so the first popup launch of a tree in tmux sets a `window-resized` hook on the
caller's window (`window-resized[N]`, N from the root's id, recorded in the root's `state/resize_hook`;
the owner removes it on exit, and a hook whose tree is gone removes itself). The hook runs
`fzx _resized ROOT_DIR N PANE`, which waits `FZX_RESIZE_SETTLE_MS` (300) and acts only if the size held, so
a drag relaunches once, then posts `transform(fzx _cb nav relayout)` to the fzf on screen (the root's
`state/current`). relayout compares the popup's geometry, its spec and the window's size, with the one
its launch recorded (`state/popup_geometry`) and restarts it in place through `become()` when they differ;
the query and position are saved as for any navigation. Explicit popup OPTS follow the window too, since
their percentages do. Floats follow it without a restart: the owner records the float's pane and the
geometry it was made for on the root (`state/float_pane`, `state/float_geometry`) and sets the same hook,
and relayout resizes and moves the pane (`tmux resize-pane -x W -y H`, `move-pane -X X -Y Y`, measured
as `new-pane` measures, border included) when the geometry for the window's new size differs; fzf
redraws on the resize.

With `FZF_TMUX` set (fzf's shell integration setting, not `0`) and inside tmux, a new run without a
placement flag starts where `FZF_TMUX_OPTS` points, read in fzf-tmux syntax: `-p[W[,H]]` (and `-w`/`-h`)
a popup, `-d`/`-u`/`-l`/`-r` `[SIZE]` a split; no options, or none recognised, a popup (fzf's own
widgets default to `-d 40%`). Only the start: the placement key still cycles from there.

Popups are fzf's `--popup`, applied on **every** launch. This relies on observed fzf 0.74 behaviour that
the man page does not describe: a popup is two fzf processes, the original one in the caller's terminal
and one inside the popup, and `become()` from inside the popup is executed by the original one, in the
caller's terminal. A launch that did not ask for the popup again would therefore drop back inline. If a
later fzf runs `become()` inside the popup instead, `_placement` must skip `--popup` when already in one.

Splits are made by the owner (`fzx::_fzf_split`): `tmux split-window -P -F '#{pane_id}' -c $PWD -v|-h [-b]
[-l SIZE]` running `fzx --resume <sid>` with its output and exit status in `split.out` / `split.rc` in the
session dir, which the owner polls (every 0.1s; a pane closed by hand counts as an abort) and then prints.
fzf-tmux is not used: it passes only `TERM` and the `FZF_*` options into the pane, while callbacks need
the whole environment, so the owner writes `export -p` (minus `PWD`, `TMUX_PANE`, ...) to `split.env` and
the pane sources it. The pane's fzx is not the owner, so it execs fzf, and `become()` inside a split pane
runs in that pane (checked with fzf-tmux on fzf 0.74): navigation works there like anywhere else. Only a
move into or out of a split needs the owner: the placement callback sets `state/relaunch` and prints
`abort`; when its fzf (or pane) ends, the owner relaunches `state/current` in the new placement, and
repeats while a relaunch is pending.

Navigation callbacks are `transform`s rather than plain `become`s so they can save `FZF_QUERY` and
`FZF_POS` first; a launch restores them with `--query` and `--bind 'result-final:pos(N)+unbind(result-final)'`. The border
label shows the path from the root (`ps:user > ps:user`) and the footer lists the modes with the active
one highlighted (only when a module has more than one mode).

## Module contract

```
modules/<name>/
  module.sh     loader: sources lib/core.sh and source.sh, defines <name>::opts; runnable directly
  components.tsv  optional: modes, toggles, sort orders and actions, one row each; see Modes
  source.sh     defines <name>::source [args]; prints lines. Runnable directly
  preview.sh    defines <name>::preview <fields>; runnable directly. Optionally <name>::debug: a
                section of its own in the debug view (f2)
  actions.sh    defines <name>::action <action> <items...> for its action rows; runnable directly
  config.sh     optional overrides of global config
  manifest.sh   optional: menu entries (<name>::manifest) and the <name>::applicable and
                <name>::summary hooks; see Menu
```

Each script defines namespaced functions and ends with a guard so it is both importable and executable:

```bash
[[ "${BASH_SOURCE[0]}" == "$0" ]] && ps::source "$@"
```

Callbacks source these scripts inside a function, so module scripts must declare globals with
`declare -g` (plain `declare -A` would be local to the loader). Stderr from `source` and `action` goes to the
log; stderr from `preview` shows in the preview window.

Functions that return through a variable name (`fzx::session_label label`) prefix their locals with `_`,
because bash's dynamic scoping would otherwise let a same-named local swallow the result.

### New-module checklist

What a module ships with, beyond the scripts above:

- **Components**: modes, toggles, sort orders and actions in `components.tsv`, each with a description
  (f1 lists them). Order toggles by how often they are used: alt-1 .. alt-8 follow the table. Copies and
  other silent actions whose effect is not visible get the `notify` flag (the copy built-ins have it).
- **Preview**: `preview.sh` draws from the item's fields, colors through `FZX_COLORS` (no hard-coded
  escapes, nothing that reads as bright yellow), icons through `fzx::icon` / `fzx::icon_label`.
- **Preview layouts**: `FZX_PREVIEW_LAYOUTS` in `config.sh`, tuned to the content: long lines (logs,
  diffs, man pages) want the preview below on narrow terminals and wide on the right; short details
  (colors, tasks, keybindings) fit a right preview early, unless the rows themselves are what is read (ps
  command lines keep the whole width until 220). Breakpoints compare with `$FZF_COLUMNS`, 4 less than the
  terminal (fzx's border): a 120-column terminal is 116 to them, so an entry meant for it starts at 110 or
  so. Content that reads wide (logs, diffs, pane captures) also gets a larger `FZX_POPUP_LAYOUTS`. Check
  each live at 80, 120 and 200 columns.
- **Icon and menu color**: `FZX_ICON` and `FZX_COLORS[<module>_icon]`; modes with an icon of their own in
  `FZX_ICON_MODES` and `FZX_COLORS[<module>_icon_<mode>]`.
- **Menu**: `manifest.sh` with an entry per mode worth listing, `<module>::applicable` when the module
  needs a tool or a place (a git repository), and `<module>::summary` lines that stay within
  `FZX_SUMMARY_TIMEOUT` (and the manifest within `FZX_APPLICABLE_TIMEOUT`); slow counts belong in the
  cache, not in the summary. `FZX_MENU_GROUP` in config.sh, one of the menu's `FZX_MENU_GROUPS`
  (files, shell, development, system, terminal, other; test/menu.bats checks it).
- **Tests**: `test/<module>.bats` through `setup_fzx`: the source per mode and toggle (with stubbed tools
  where the real ones are not on every machine), the preview, the actions, and the bindings under fzx.
- **Docs**: a paragraph under Modules below, a CHANGELOG entry, and the module in TODO.md's status line.

Every module has these parts (checked 2026-11-03); the actions menu keeps the global preview layouts, as it
shows the parent screen's rows.

### Modes

Modes (and the other components, `docs/components.md`) are rows of the module's `components.tsv`:

```
# kind  name  key  description                              flags
mode    user  -    your processes, busiest first            default
mode    all   -    all processes, busiest first             -
mode    tree  -    process tree (input order: sorting off)  restart
```

Columns split on tabs or runs of 2+ spaces; `key`/`flags` may be `-`. An executable table is run and its
output read (dirs lists only the modes whose tool is installed, files the trash action only with a trash
tool). `~/.config/fzx/modules/<m>/components.tsv`
replaces rows by kind+name (`=` keeps a field, the flag `off` removes the row, new names are added). The
resolved table is stored in `meta/components`, so callbacks read it without config. Without mode rows a
module has the single mode `main`; the row flagged `default` (else the first) starts; a mode row with a key
gets a binding straight to that mode. A mode flagged `hidden` is left out of the cycle and only opened by
name (`-m git:commit`, or `fzx::nav goto` from a drill-down key); a session opened in one has that mode alone.
An action's description may be scoped by mode, "; "-separated parts of the form `MODE[, MODE]: text`
(`status: stage the files; stash: pop the stash`): the f1 help and the actions menu show the current mode's
part and leave the action out in modes no part names (`fzx::mode_desc`). One key then serves as a verb
whose meaning follows the mode.

The current mode is exported as `FZX_MODE` to the source, preview, action and opts hooks, so a script reads
it the same way under fzx and standalone (`FZX_MODE=tree modules/ps/source.sh`). Select it with
`fzx -m ps:tree`. Mode names match `[A-Za-z0-9_-]+`.

The `restart` flag marks a mode that needs options fzf cannot change while running; entering or leaving
it restarts fzf (query kept). fzf only has `toggle-sort` and does not export the sort state (the user's
own `ctrl-s` toggles it too), so `ps` marks `tree`, which needs `--no-sort`.

Options a running fzf can change need no restart: a module whose modes or toggles differ only in its
header or in whether fzf filters (`--disabled`) defines `<module>::refresh` in its module.sh. After an
in-place mode, toggle or sort change, `fzx::_nav_refresh` sources module.sh (`fzx::module_main` returns when
sourced) and calls it with the new `FZX_MODE`, `FZX_TOGGLES`, `FZX_SORT` and the session's `FZX_ARGS`; it
sets `FZX_REFRESH_HEADER` (the new header; unset leaves it), `FZX_REFRESH_SEARCH` (`on` or `off`:
`enable-search` / `disable-search`; empty leaves it) and `FZX_REFRESH_CHANGE` (`on` or `off`: `rebind(change)` /
`unbind(change)`, for a mode that reloads as you type: the module binds change at launch in every mode, with
`start:+unbind(change)` where it does not apply; empty leaves it). packages uses it for search. Options fzf
cannot change while it runs (`--with-nth`, `--accept-nth`, sorting) still need the `restart` flag: files:grep,
ps:top, ps:tree. In the footer position the header goes out as
`change-header`, in the header position into `meta/header`, which the header callback draws under the
component line. A failing hook is logged and the refresh goes on without it. github builds its header in
`github::header` for both the launch and the hook, so no github mode or toggle restarts fzf.

Lists whose order is a ranking (frecency, recency, priority, the screen) keep fzf's sorting on with
`--tiebreak=index`: the best matches rise to the top and equal ones keep the list's order, and with no
query the list shows as it came. After a `--scheme`, which sets its own tiebreak, the option has to come
later to win. Only an order that is the content itself (ps's tree) turns sorting off.

### Toggles and sort

`toggle` rows are independent switches (flag `on` = on at start), `sort` rows the sort orders (flag
`default`, else the first). They reach every module script as `FZX_TOGGLES` (the names that are on,
space-separated) and `FZX_SORT`, exactly like `FZX_MODE`, and live in `state/toggles` / `state/sort`;
standalone runs take them from the environment. A toggle row's key flips it, and so does alt-1 .. alt-8 by
the toggle's place in the table (`FZX_TOGGLE_DIGIT_KEYS`; a number another row or `FZX_KEYS` has is skipped); f11/f12 (`FZX_KEYS[sort_prev]`,
`[sort_next]`, which also has ctrl-_) cycle the sort when there are two or more, and a sort row's key selects it. Changes reload
in place (`transform(fzx _cb toggle NAME)`, `fzx _cb sort next|prev|NAME`); a row flagged `restart` restarts
fzf instead. The cache key is the view, not just the mode: `<mode>[+<toggles on>][@<sort>]`
(`data/all+kernel@mem`; `#header` appended for a view with a header row), so each combination is cached
once. A sort row flagged `desc` orders its column's values from the largest (most stars, the newest
date); the header row's arrow points down for it (`FZX_SORT_DESC`). The footer shows modes, toggles and the sort
key, active ones highlighted (`FZX_COLORS[toggle_on|toggle_off|sort]`).

`--freeze-left` (`FZX_FREEZE_LEFT`, 1 by default, 0 for none; a module's own option wins) counts fields of the
displayed text, and a row's display is one field, so on its own it would do nothing. `fzx::_freeze_opts`
therefore, under a session and without `--read0`, turns `--with-nth=K` into `--with-nth=K,-1` (and `--nth=1`
into `--nth=1,2`), adds `--tabstop=1` and records K in `meta/freeze`; `fzx::freeze_rows`, between the source and
fzf or the cache, then cuts field K at the space `FZX_FREEZE_COLS[mode]` or `FZX_FREEZE_COL` names (`gap`,
`gap2`, `word`, a column, `none`) and appends what follows as a new last field. The tab takes the replaced
space's column, so nothing shifts, and every field a binding reads keeps its number. The display is whole again
for what needs it: copy-line rejoins it and tmux's preview takes `{-1}`. The cache key gets `~K`.

A toggle row's description may be scoped by mode too (`params: exported ones only`; `fzx::comp_toggle_names`): it shows in
the footer only in the modes it names, its key does nothing elsewhere (fzf keeps its bindings across modes,
so it stays bound; `ignore`), and it stays out of those modes' cache key, so turning it on elsewhere
does not make them read their list again. Its state is kept for when you come back.

A sort row's description may be scoped by mode as an action's is (`branches: last commit first`,
`mine, starred: most stars first`): the row then exists only in the modes it names
(`fzx::comp_sort_names`), and a mode no row names has no sort (`FZX_SORT` empty, no footer item, f11/f12
do nothing; ps's tree, whose order is the content). The default is the row flagged `default`, else the
first, among the rows the mode has. A scoped description must name modes that exist: one naming only
modes the table lacks applies everywhere, so computed tables print such rows only with their mode (dirs'
bookmarks).

Sources draw the column a list is sorted by in `FZX_COLORS[sorted]` on top of the column's own color.
`fzx::config_load` derives it from `FZX_SORTED_STYLE` (decoration names, default `underdashed`) and
`FZX_SORTED_UNDERLINE_COLOR` (default `#6e6e6e`) unless a layer sets it; it may hold colons (`4:5`), so
anything stripping SGR must allow `[0-9;:]`. It is drawn in the text and not its padding, header included
where there is one. It is done in the source and not with fzf's `change-nth` and `--color nth`, because `change-nth` also narrows what
the query matches to that column.

`FZX_SORTED_SHOW` picks where the sort shows: `header` (the default), `rows` (the above, no header rows)
or `both`. With
header or both, a view that has a sort (`fzx::sort_header_on`: the mode has one and the module marks a
column, `FZX_SORTED_COLUMNS` not 0; files and todos set it to 0) gets a header row, and lib/components.sh
exports `FZX_SORT_HEADER=1` with the view: opts_build adds `--header-lines=1` (unless the module always has
one, ps and network) and the source prints the row first, before anything that could fail into a row of
its own (github's error rows), and before any sort or filter its rows pass through. lib/header.sh builds it:
`fzx::header_print [-z] <hidden fields> <sorted name> NAME WIDTH RIGHT...` for sources in bash (empty id
fields, cells one space apart, an empty 0-wide cell for a two-space gap, a `\t` cell for a field break,
`-z` for `--read0` lists), `fzx::header_vars` (`hcell`, `hwidth` in `FZX_HEADER_AWK`) for sources that size
their columns in awk. Cells are padded like the rows' columns (a label wider than its column would shift
the rest: github's issue count, 5 wide without its icon, is OPEN then), colored in the text only:
`FZX_COLORS[header_column]` (from `FZX_HEADER_COLUMN_COLOR`, default `#007e95`; "" leaves fzf's own `header`
color) and, for the sorted column and its arrow, `[header_sorted]` (`FZX_SORTED_HEADER_STYLE`, default
`bold underline`, and `FZX_SORTED_HEADER_COLOR`, default `#00d7ff`).
The arrows are `FZX_SORTED_ARROWS` ("ascending descending", default `↑ ↓`; "" for none). Under header the
rows' `FZX_COLORS[sorted]` is 24, so they stay plain. fzf cannot change `--header-lines` while it runs, so a
mode switch between a mode with a header row and one without restarts fzf (`fzx::mode_has_header` in
`fzx::nav_mode`). tmux pads its sessions, windows and panes into columns only when there is a header row.
Sorted columns: ps (cpu, mem, age, pid), docker containers (state, name)
and images (created, size, name), tmux sessions, windows and panes (order, recent: an activity age column,
name), systemd (name, state), recent (rank: the score, path), dirs bookmarks (name, path), logs files
(recent, size, name), git branches (recent, name), github mine and starred (listed: mine's push age,
stars, name), repos (recent, name), history (recent: the age, frequent: the count), claude (recent, name),
cron (next), browser history (recent: the date; header only) and packages (name, apt's size). files (path,
modification time) and todos (urgency) sort without a column to mark.

### Actions

`action` rows name what can be done to the selection; `lib/actions.sh` turns them into bindings. Flags:

| Flag | Binding |
|---|---|
| `silent` | `execute-silent`: no screen change (signals, database updates) |
| `foreground` (default) | `execute`: the action gets the terminal (editors, sudo, followers) |
| `become`, `print` | `become`: fzf is replaced by the action, whose output is fzx's result |
| `reload` | `+reload(source)` afterwards |
| `restart` | `+transform(nav restart)`: the interface restarts with fresh data (standalone: reload) |
| `confirm` | ask `[y/N]` on the terminal first (in the callback; standalone in the binding); runs in the foreground |
| `asks` | the action asks on the terminal itself (`fzx::confirm`, e.g. one question per kind of target, as git's drop of local and remote branches); listed as asking first and run in the foreground, but fzx asks nothing |
| `default` | also bound to enter; without one, enter prints the selection as before |
| `builtin` | fzx's own (`lib/builtin.sh`), not the module's `actions.sh` |
| `notify` | silent, and under fzx `transform(fzx _cb notify NAME ARGS)`: the callback runs the action, puts "copied ITEM", "copied N items" or "✓ DESCRIPTION" (on failure "✗ NAME failed: first stderr line") in the footer and brings the component line back after `FZX_NOTIFY_SECONDS` (`bg-transform-footer(sleep N; fzx _cb footer)`, from the state then). The `copy` and `copy-line` built-ins always notify |

Built-ins come from `config/components.tsv` and every module gets them, listed after its own rows:
`copy` (the ids, `{+1}`), `copy-line` (`{+}`) and `view` (the module's preview of the item in `$PAGER`).
Clipboard: wl-copy, xclip, xsel, pbcopy, else tmux's paste buffer. A module row of the same name replaces
a built-in, and the flag `off` removes it (the menu and actions modules switch all three off).

Arguments are fzf placeholders appended to `fzx _cb action NAME`: `FZX_ACTION_ARGS` (default `{+1}`) for
the module's actions and `FZX_ACTION_ARGS_FOR[name]` for one action, built-ins included, both set in the
module's opts hook (it can depend on the mode). `view` takes the arguments of the module's `--preview`
callback. git passes its module args (`$a {+1}`), logs `{1} {2}`, files in grep mode `{1} {2}`.

The actions menu (`ctrl-\`, `FZX_KEYS[actions]`) is a child session of the built-in `actions` module, so
back, help, stats and debugging work as on any screen; its own key there goes back to the screen it was
opened from. The binding passes the selection already expanded,
grouped by argument template: `nav goto actions term,kill,copy {+1} --fzx-- copy-line {+} --fzx-- ...`.
The menu lists the parent's rows (from its `meta/components`): an icon for how each runs (in the terminal,
in the background, in fzf's place, asking first) and a reload mark, the name (built-ins dimmer), the key as a
keycap and ⏎ on the default action, colored by `FZX_COLORS[actions_*]`; the preview shows the key, the flags
in the same colors and the arguments; enter runs `FZX_SESSION=<parent> fzx _cb action NAME ARGS` in the foreground and goes back
(`become` and `print` actions take over instead). An action flagged `reload` or `restart` sets the parent's
`state/fresh`, so its next load runs the source instead of serving the cache; `nav restart` uses the same
flag.

`FZX_COMPONENT_STYLE` draws that line: `minimal` (colored text, the default; a toggle's state is its
color), `icon` (colored text, toggles with an on/off marker: `FZX_TOGGLE_ICONS=switch` or `dot`), `round` (a
rounded pill per item), `triangle` (one powerline with arrows), `none` (no line; every key still works). The
sort keeps its icon in every style. `FZX_HEADER_STYLE` (with `bubble` for `round`) is the older name, read
when `FZX_COMPONENT_STYLE` is empty. Pills use `FZX_COLORS[pill_on|pill_off]` (background) and
`[pill_on_fg|pill_off_fg]` (text) as 256-color numbers; round and triangle need a Nerd Font. `FZX_HEADER_POSITION=footer` (default) or `header`: in the header
the line sits above the module's own `--header` (kept in `meta/header`), and in-place refreshes rebuild
both with `transform-header(fzx _cb header)`, since a module header can hold text that cannot be quoted
into `change-header(...)`. Standalone runs show the line too.

`<name>::opts` appends to the `FZX_OPTS` array. Key bindings go through
`fzx::bind <key>[,<key>...] <action> <description>`, which records them for the help key (f1,
`FZX_KEYS[help]`). A comma list binds several keys to one action (`FZX_KEYS[back]="alt-left,ctrl-bspace"`,
or a component row's key field; a comma after a dash is the comma key, `alt-,`); each key gets its own `--bind` and is recorded, checked against `FZX_RESERVED_KEYS` and for double
binding on its own. f1 runs `transform:fzx keys --toggle s:STYLE ...` with every recorded binding
(`k:SCOPE<TAB>KEY<TAB>DESC`), the component rows (`c:...`) and the module's name as arguments; it answers
`show-preview+preview:fzx keys ...` and lib/keys.sh draws the page, so help needs no callback and works
standalone. Pressed again while the page shows (fzf's `FZF_ACTION` is still that `show-preview`), it
answers the grid instead (`l:grid`, ending in `ignore` so a third press brings the list back): a row per
modifier (none, ctrl, alt, alt-shift, shift, ctrl-alt, ctrl-shift) with the keys fzf 0.74 accepts with it
(letters, digits, function keys, movement, editing; fzf has no shift-f1), each colored by who binds it.
Sections of the page, each under a colored title: the components (modes, toggles, sort orders, actions
with their keys), this screen's keys (the module's bindings, including component keys and action rows),
fzx's keys (every fzx screen), the global keys (the user's `--bind`s from `FZF_DEFAULT_OPTS_FILE` and
`FZF_DEFAULT_OPTS`, then fzf's defaults from a static table of the fzf 0.74 man page; the first that binds
a key wins), then the free ctrl, alt, alt-shift and function keys. `FZX_KEY_STYLE` sets how keys are shown
there and in the menu preview (`fzx::key_label`): `full` (fzf's names, the default), `short` (`^X`,
`M-left`) or `glyph` (`⌃X`, `⌥←`). Keys are keycaps
(`FZX_COLORS[help_key]`); a key fzx takes over from a global binding says what it shadows ("over yours:
...", "over fzf: ..."); lines are cut to `FZF_PREVIEW_COLUMNS`. The user's options are split into shell words
by an awk tokenizer (quotes, escapes, continuations, comments; nothing is evaluated) and fzf's key synonyms
are folded (`return` is `enter`, `bs` is `bspace`). It runs only when f1 is pressed (~70ms). Moving the
cursor returns to the normal preview. Descriptions must not contain `{...}`, which fzf would substitute.
`fzx::key_hints <var>` turns the module's bindings into a header. Non-key events
(`start`, `change`, `load`) still use plain `--bind`. It builds command strings through `fzx::cb <verb> [fzf
placeholders]`, which resolves differently depending on how the module was launched:

| Verb | Under fzx | Standalone (`modules/ps/module.sh`) |
|---|---|---|
| `load` | `fzx _cb load` (cache, else source) | `source.sh <args>` |
| `source` | `fzx _cb source` | `source.sh <args>` |
| `preview` | `fzx _cb preview ...` | `preview.sh ...` |
| `action` | `fzx _cb action ...` | `actions.sh ...` |
| `transform` | `fzx _cb transform <name> ...`: `<name>::transform` in actions.sh, prints fzf actions | not available |
| `mode`, `nav` | `fzx _cb mode/nav ...` | not available |

Running `module.sh` directly gives the same interface with global defaults but no session, cache,
navigation, mode keys or logging of callbacks; `FZX_MODE` picks the mode. Modules guard session-only
bindings with `fzx::in_session`.

Modules are found in `$FZX_MODULE_PATH` (default `~/.config/fzx/modules:<repo>/modules`).

## Configuration

Sourced in order; later layers override earlier ones by reassignment:

1. `config/defaults.sh` (repo)
2. `modules/<m>/config.sh` (the module's own defaults: its keys, settings, persist policy)
3. `~/.config/fzx/config.sh` (the user, for every module)
4. `~/.config/fzx/modules/<m>/config.sh` (the user, for one module)
5. CLI flags

Module defaults come before the user's config, so a key or setting the user sets globally is never
undone by a module. Module code running in callbacks (source, preview, action, transform) gets the same
resolved config: the callback loads the layers just before the first module function runs.

| Setting | Default | Meaning |
|---|---|---|
| `FZX_FZF_OPTS` | `--ansi --with-shell='bash -c'` | base fzf options for every module |
| `FZX_KEYS` | core: `reload_hard` ctrl-r, `reload_soft` alt-r, `mode_next` alt-0, `mode_prev` alt-9, `back` alt-left, `escape` esc, `popout` ctrl-^, `popup_toggle` alt-^, `actions` ctrl-\\ | module navigation keys are `<module>.<name>` (`ps.children`, `files.into`), set in the module's `config.sh`; action keys are in the action rows of `components.tsv` |
| `FZX_TOGGLE_DIGIT_KEYS` | `1` | toggles also flip with alt-1 .. alt-8 in table order; `0` turns it off |
| `FZX_RESERVED_KEYS` | ctrl-f ctrl-b ctrl-u ctrl-w ctrl-g alt-g ctrl-p ctrl-n up down alt-b alt-f alt-w scroll-up scroll-down | keys modules may not bind (the user's scrolling, query editing and preview wrap toggle); `fzx::bind` skips a module binding on one and logs a warning. fzx's own keys are not checked. Modules may still take keys the user binds elsewhere (ctrl-e edit replaces the user's `become(nvim)` with a per-module editor action) |
| `FZX_COLORS` | `mode_active`, `mode_inactive`, `menu_target`, `menu_summary`, `menu_group`, `dim`, `sorted` | SGR parameters for what fzx draws itself (`sorted`: added to the column a list is sorted by) |
| `FZX_FZF_COLORS` | empty | passed as `--color` when set; empty keeps the user's fzf theme |
| `FZX_NOTIFY_SECONDS` | `2` | how long an action's footer message stays (`FZX_COLORS[notify_ok\|notify_fail]`) |
| `FZX_HISTORY` | `1` | per-module `--history=$XDG_STATE_HOME/fzx/history/<module>`; `0` leaves fzf's history alone |
| `FZX_ICON`, `FZX_PROMPT`, `FZX_PROMPT_LOADING` | icon per module (Nerd Font), `{icon} ` | the prompt: `{icon}` in `FZX_COLORS[prompt_loading]` from start until `load`, then `[prompt_loaded]`; every reload (ctrl-r, mode/toggle/sort switches, reload actions) goes back to loading first. A blank prompt (`FZX_ICON=""`) keeps fzf's own prompt and binds nothing. A mode with an icon of its own (`FZX_ICON_MODES[mode]`) shows it instead of `FZX_ICON`; since an in-place mode switch cannot change the load bind, such modules keep each mode's loaded prompt in `meta/prompt.<mode>` and bind `load:transform-prompt(fzx _cb prompt)`, which reads the mode and that file (no config); other modules keep a fixed `change-prompt`. The hard reload key's loading form is fixed at start, so after a switch it shows the start mode's icon until the load ends. `)` is dropped (it would end `change-prompt(...)`) |
| `FZX_ICONS` | `nerd` | icons in rows and previews (lib/icons.sh, `fzx::icon NAME`): `nerd` (Nerd Font glyphs), `unicode` (plain symbols, for terminals without a Nerd Font) or `none`. Used by the menu (each module's `FZX_ICON`, or `FZX_ICON_MODES[mode]` for a mode that opens a different list, in `FZX_COLORS[<module>_icon_<mode>]` or `[<module>_icon]`; nerd only), git status (added, modified, deleted, renamed, untracked, conflict), repos (branch, changed, ahead, behind, todos), docker containers and logs (running, paused, stopped, created; file, unit), history (failed); the footer's toggles (on/off) and sort; the ps, history and repos previews' labels (`fzx::icon_label`, icons in `FZX_COLORS[preview_icon]`) |
| `FZX_PREVIEW_LAYOUTS` | `0:down,50%,border-top` `120:` (menu: `0:down,50%,border-top` `180:right,40%`) | the preview window by terminal width, see below; `()` turns it off |
| `FZX_PREVIEW_TEXT` | empty (bat) | the command file previews (lib/preview.sh) use for text and code; the path is appended, or replaces `{}` |
| `FZX_PREVIEW_VIEWERS` | empty | per-type preview commands, `KEY=COMMAND;KEY=COMMAND`: KEY is a type (`markdown`, `mp3`, `audio`, `video`, `image`, `pdf`, `archive`, `compressed`, `json`, `sqlite`, `cert`, `document`, `binary`, `text`) or a glob on the file name (`*.log`); a glob wins over a type, a type over `FZX_PREVIEW_TEXT`. Commands run through bash, so they may hold options and pipes, but not `;` |
| `FZX_PREVIEW_DEBUG` | `0` | `1`: file previews start with a dim line saying how the file was detected, what drew it and how long it took (`ext:markdown -> nvcat (230ms)`) |
| `FZX_PREVIEW_NVCAT_MAX_LINES` | `300` | the longest file (source lines) nvcat draws; longer ones go to bat, since nvcat's complete output stops at 1000 screen rows and reaching that took seconds |
| `FZX_READ0` | `0` | `1` (a module's opts hook may set it): the source's items end with NUL and may span lines; fzf gets `--read0 --highlight-line`, and the callbacks count items by NUL (`meta/read0`). history sets it unless `FZX_HISTORY_MULTILINE=0` |
| `FZX_POPUP_LAYOUTS` | `0:center,100%` `140:center,90%,85%` `220:center,80%` | popup and float size by the tmux window's width, see "Popup geometry" |
| `FZX_RESIZE_SETTLE_MS` | `300` | how long the window's size must hold before a popup is reopened at the new size |
| `FZX_PERSIST`, `FZX_POPUP_OPTS`, `FZX_FLOAT_OPTS`, `FZX_STATS`, `FZX_SUMMARY_TTL`, `FZX_TRACE`, ... | | see their sections |

**Yanking.** ctrl-y and alt-y are global in the user's fzfrc (the first field, the whole line). Modules refine
them, and both report in the footer rather than by fzfrc's notify-send: the built-in `copy` is ctrl-y everywhere
(`{+1}`; a module's `copy` row or `FZX_ACTION_ARGS_FOR[copy]` says what it means by the row, a URL, a family
name: docker's and tmux's rows carry a field of their own for it, since their ids are hashes and `$N`), and the
built-in `copy-line` is alt-y everywhere, copying the display as it shows rather than fzf's `{}`, which holds
the hidden fields. Other copies a module offers use alt-Y.

**Wrapping keys.** `FZX_KEYS[wrap]` (ctrl-w) toggles word wrap in the list and `[preview_wrap]` (alt-w) the
preview's, in every module; both are in `FZX_RESERVED_KEYS`. fzf has no ctrl-shift-w: the terminal has to send
something else for it, and alacritty.toml sends alt-w. The sort keys are bound in every module too, to `ignore`
where there is nothing to switch to, or fzf's own ctrl-/ (ctrl-\_) would wrap the list.

**Wrapping.** Previews do not wrap: no module asks for `wrap` in its `--preview-window`, so the user's own setting applies (fzf's default and FZF_DEFAULT_OPTS', `nowrap` here) and their key for `toggle-preview-wrap` (alt-w here) turns it on. Module keys leave alt-w alone for that reason (github's and repos' browser actions are alt-W). logs and systemd say `nowrap` outright: their lines are read as they are.

**Responsive preview.** `FZX_PREVIEW_LAYOUTS` entries are `MINCOLS:SPEC`; the entry with the largest
MINCOLS that is at most `$FZF_COLUMNS` applies, through `change-preview-window(SPEC)`. SPEC is in
`--preview-window` syntax and, as fzf does for that action, sits on top of the module's own
`--preview-window`: an empty SPEC is the module's own layout, `hidden` hides it, and any other SPEC shows the
preview (fzf: a spec without `hidden` shows it, even over a default that hides it). opts_build keeps the
entries in `meta/preview_layouts` and appends `start:+transform(fzx _cb layout start)` and
`resize:+transform(fzx _cb layout resize)`, so the callback loads no config (about 6ms). Width only: fzf's
native `<SIZE(ALT)` alternative is one breakpoint measured on the preview itself, so it cannot express a
hidden tier plus two positions. Sessions only: standalone runs keep the module's layout.

A resize within the same entry prints nothing, so a manual toggle stays. When the entry changes and the
preview is hidden (`FZF_PREVIEW_COLUMNS` is empty; fzf 0.74 exports it only while the preview shows) but the
last entry showed it, the user hid it: the new SPEC is applied with `,hidden`, so toggling it back shows the
new layout. A preview shown by hand (the last entry hid it) stays when the new entry also hides it. Across
`become()` the navigation callbacks save a hand-hidden preview in `state/preview_hidden`, and the next
`start` applies the entry with `,hidden`.

`fzx config [-m MODULE]` prints the layers that were loaded and the resolved keys, colors, base options
and settings.

**File previews.** `lib/preview.sh` draws a file by its type, for the files module (under its own
header line) and for plain fzf through `fzx preview ITEM [LINE]` (~/.shell/scripts/fzf-preview runs it).
ITEM may be a grep hit, `path:line[:col:text]`: the shortest prefix that exists, followed by digits, is the
path. Detection takes the extension first and runs `file --mime` only for names it does not know (about
20ms); a `.db` must start with SQLite's magic. Each type has a chain, the first tool installed and
succeeding wins: text and code bat (cat), or nvcat for the files `nvcat-dispatch --print` claims (config
formats bat has no syntax for; not for a grep hit's line, which bat highlights); markdown nvcat (bat); mp3 mid3v2's tags named and ordered,
under mediainfo's stream line (mediainfo, ffprobe); audio and video mediainfo (ffprobe); images a size line
and chafa (an svg's source); pdf pdftotext's first three pages; archives bsdtar (7z, unzip; dpkg-deb for
.deb); compressed files their decompressed first megabyte, highlighted for the inner name; json jq up to
1M (bat); sqlite the tables and schema, read-only; certificates openssl, PEM or DER, while a private key
is named and never shown; office documents and epub pandoc; other binaries file's description and hexyl
(xxd below 79 columns); directories eza's tree two levels deep (lsd, ls). Every preview logs
`preview PATH: ext:TYPE -> TOOL (Nms)` at debug level. nvcat is skipped (bat draws) under `NO_COLOR` and
for files over `FZX_PREVIEW_NVCAT_MAX_LINES`.

**Renderers.** `lib/render.sh` holds the text and markdown renderers for every preview: `lib/preview.sh` and
the modules' own (github, history, logs, man, shell, todos) source it by path, since module previews run as
scripts without core.sh. `fzx::render_text [--language L] [--name NAME] [--style S] [--line N] [--mark N]
[--wrap] [FILE]` and `fzx::render_markdown [--width N] [FILE]` read stdin without a FILE (spooled to a
temporary file for the tools that open their input by name), honor `NO_COLOR` and `FZF_PREVIEW_COLUMNS`, and
apply `FZX_PREVIEW_VIEWERS`: a markdown viewer always, a text viewer when `--name` names the file. Snippets
given only a `--language` (zsh commands, man pages, logs) go to bat.

## Modules

| Module | Modes | Args | Keys | Enter prints |
|---|---|---|---|---|
| `ps` | user, all, top (all processes, reloaded every `FZX_PS_TOP_INTERVAL` seconds, 2 by default, the cursor and selection kept on their pids), tree | `--ppid PID` | ctrl-x SIGTERM, kill (SIGKILL, confirm; menu only), both through `sudo -n` for a process that is not yours (else the footer says so); sudo-term, sudo-kill (menu only: sudo asks for the password); alt-t strace (every call), alt-T strace -Z (failing calls only), both following threads, through sudo unless ptrace allows it (root, or yours with ptrace_scope 0), ctrl-c returns; ctrl-o children, alt-O open files (network:files) | pids |
| `files` | files, dirs, grep (as you type), locate (plocate, else locate, when installed: every word in the query, any case, under the directory, or the whole database with the everywhere toggle; hidden and `FZX_FILES_EXCLUDES` paths left out as in files, paths gone since the last updatedb dropped, at most `FZX_FILES_LOCATE_LIMIT` (2000), in sort order; the header says how old the database is); replace (hidden, ripgrep only: a grep term's matches, `--term T`, a child of grep from alt-s; the query is the replacement, `$1` a group, so the rows show each line as `rg --replace` leaves it and the preview the line before and after in context; enter applies it to the selected matches, every match when none are selected, after a question naming the lines and files: ripgrep rewrites each file (`--passthru`) and only those lines are taken from its output, so a file's other matches stay, written in place with `cat >` (mode, owner and links kept) and a missing last newline kept missing; a replacement that would change a file's line count leaves it alone; every changed file is copied first under `$FZX_STATE_DIR/files/replace/<time>`, the newest `FZX_FILES_REPLACE_KEEP` (20) kept); toggles hidden (on), ignored, follow, everywhere (locate), multiline (grep: ripgrep's `-U --multiline-dotall`, `\n` in the term, each line of a match its own row); sort path/recent | `[DIR]` | ctrl-e edit, alt-x trash (confirm; trash-put, else gio trash; offered when either is installed; grep: the files of the selected matches), ctrl-o into directory, alt-up parent, ctrl-t grep/filter, alt-s replace (grep), alt-u undo the last replacement (grep, replace: asks; files changed since are left alone), alt-h/alt-i/alt-l/alt-e/alt-m toggles | absolute paths (`path:line` in grep) |
| `keybindings` | zsh (every keymap; zle descriptions from zshzle(1), user widgets from the comment above their function), tmux (the tmux module's keys), fzf (yours, then fzf's defaults) | | ctrl-y copy | bindkey / bind-key lines, fzf keys |
| `logs` | files (newest first, a dot in the color of the age before each), units (restarts fzf: its preview pins the top of `systemctl status`, `FZX_LOGS_STATUS_LINES`), docker; the preview follows the log while the row has focus (`FZX_LOGS_PREVIEW_FOLLOW`; every `FZX_LOGS_FOLLOW_CHECK` seconds it asks fzf's socket for the focused row and stops once it is another or nothing answers, since fzf runs previews in a process group of their own and one left behind by a closed pane or popup kept following a quiet log forever), files and containers colored by `FZX_LOGS_COLORIZER` (ccze -A), journals by systemd | | alt-F follow (ctrl-c returns) | path, unit or container id |
| `man` | commands (`FZX_MAN_SECTIONS`, 1 and 8), all, tldr (descriptions from tealdeer's pages); cached a day | | enter opens in the pager, alt-n nvim (`:Man`, a tldr page's markdown), ctrl-y copy | (enter opens) |
| `packages` | apt (installed; dependencies dim, held ones marked; toggle manual: the ones installed by hand), available (every package the archives offer, installed ones marked), upgradable (installed -> candidate), snap, snap-available (snapd's list of every snap name), flatpak (applications; toggle runtimes), flatpak-available (the remotes' appstream applications, cached per checkout), pipx, cargo (with the source each crate came from), pnpm (global), gem (user and system gem homes; apt's gems left out), search (crates.io, npm and rubygems.org as you type, and PyPI by exact name; toggles crates, npm, rubygems, pypi); a mode per manager on PATH; sort name (not search: the registries' relevance), size (apt). Preview: an apt package's fields, description and the commands it provides, snap info, flatpak info or a catalog application's appstream entry, a pipx venv's metadata, a crate's install record (its description from the registry sources when still unpacked), a pnpm package.json, a gemspec; a package that is not installed from the network (snap info, cargo info, pnpm view, the rubygems.org and PyPI APIs), cached a day per package | | alt-i install (available, the catalogs, search; snaps that need it with --classic, flatpaks from the row's remote, gems into the user's gem home), alt-u upgrade, alt-x remove (asks first; apt asks itself); actions: purge (apt); apt and snap through sudo, flatpak's system installation through polkit, gems through sudo when their home is not writable | package names |
| `systemd` | user, system (loaded units and the enabled and disabled unit files not loaded; toggle files: static, masked, generated and alias ones too; templates left out), failed, timers (next and last run), sockets (addresses); sort name/state | | alt-s start, ctrl-x stop, alt-R restart, alt-L reload (reload-or-restart), alt-e enable, alt-d disable, ctrl-l journal (a timer's or socket's: the unit it activates), ctrl-e edit, alt-u files toggle; actions: daemon-reload | unit names |
| `git` | grep (`git grep` as you type, `--rev` for a commit; a restart in and out, as files:grep), clean (what `git clean -d` would remove, alt-x asks and removes the chosen ones, needing no `FZX_GIT_DESTRUCTIVE`), status, log, branches, tags, stash, reflog, worktrees (switch in place); commit (hidden: a commit's files) | `[--all] [--rev REV] [DIR]` | verbs shared across modes (f1 shows the current mode's meaning): alt-s stage, alt-u unstage, alt-p add -p, ctrl-e edit, alt-c switch / check out detached / restore files as of a commit, alt-k cherry-pick / stash apply, alt-R revert, alt-B new branch there, alt-z stash files / pop, alt-i ignore, alt-m commit, alt-M amend (refused once pushed unless `FZX_GIT_DESTRUCTIVE=1`), alt-F fetch, ctrl-y copy; with `FZX_GIT_DESTRUCTIVE=1` only, each confirmed: alt-x drop (discard changes / delete untracked, branches: local ones and remote ones through `git push REMOTE --delete`, a question for each kind; stashes), alt-U fixup, alt-Q squash, alt-W reword, alt-E rebase -i; ctrl-o: branch or tag to its log, commit/reflog/stash entry to its files, worktree to its status; alt-v diff/blame preview; diffs through delta when installed | paths, hashes, ref names, tag names, stash names, work tree paths |
| `dirs` | all (fd over ~, the default), bookmarks (alt-m, kept in `$FZX_STATE_DIR/dirs/bookmarks`, and `FZX_DIRS_BOOKMARKS` from config, where a name both have takes the file's) | `[WORDS...]`: the fzf query (all) or a bookmark filter, where a single match is printed without the picker | ctrl-o browse in files | the directory |
| `recent` | files: nvim (telescope-frecency's `file_frecency.sqlite3`, scored by its count and recency weights), fasd; directories: zlua (z.lua, `FZX_RECENT_ZLUA`), dirs (zoxide), fasd-dirs, visited (fasd by last visit); whichever are installed | `[WORDS...]`: files, each in order in the path, ignoring case; directories, the tracker's keywords; with words a single match is printed (`--select-1 --exit-0`) | ctrl-e edit, ctrl-x forget (fasd, zoxide, z.lua), ctrl-o browse in files | paths |
| `tmux` | sessions, windows, panes; buffers; keys, commands, options, variables, styles, formats, status, hooks | `--pane %N`, `--table`, `--option-scope`, `--user-only`, `--builtin-only`, `--prefix`, `--options-file`, `--data-file` | alt-s switch/attach, ctrl-o capture (the capture module on that pane), ctrl-x kill (confirm), alt-n rename, alt-m move, alt-p paste a buffer, ctrl-e edit buffers then paste, alt-enter run a key binding (keys); toggles: changed/free/empty/short; actions: link/swap/mark, next/prev session, theme, scratch, nvim | plain IDs/text; colored display and hidden metadata; see [tmux](tmux.md) |
| `capture` | lines, urls, paths, words, hashes, ips (IPv4 and IPv6) out of a tmux pane: the screen first (newest first), then the scrollback nearest first, each row marked `vis`, `↑N` or `↓N`; toggle visible | `--pane %N` (the origin) | alt-. / alt-, the window's next/previous pane (header shows which), alt-p paste into the origin pane, ctrl-e edit in $EDITOR then paste (emptied: nothing), alt-O open URLs in the browser (urls), ctrl-y copy | the values |
| `audio` | sinks (outputs, the default marked; `--move N`: the output for stream N, its current one marked), sources (inputs; the outputs' monitors with the monitors toggle, PipeWire's device class or PulseAudio's monitor_of_sink, the default kept), streams (what plays, per application, with its output), players (MPRIS through playerctl: state, artist, title); `pactl -f json`, read on every load (`FZX_PERSIST=none`); long device names cut in the middle. Preview: a device's state, volume per channel, port, bus, codec and what plays there; a stream's process and output; a player's track | sinks: `--move INDEX` | enter: sinks and sources make it the default, streams pick a new output (a child sinks list; enter there moves it and goes back), players play or pause; alt-up and alt-down volume by `FZX_AUDIO_STEP` (up to `FZX_AUDIO_MAX`), alt-m mute (players: play or pause), alt-n and alt-p next and previous track, alt-1 monitors | sink and source names, stream indexes, player names |
| `music` | queue (the current song marked, playing or paused), artists (album artists, MPD's fallback to the artist included; toggle byartist: the artist tag), albums (by artist then year, with songs and minutes), playlists; drill-downs as child sessions: artist (an artist's albums by year), tracks (an album's songs in disc and track order, or a playlist's); all through mpc, read on every load (`FZX_PERSIST=none`). Preview: a song's cover (`mpc albumart`, else the embedded picture; cached per directory, drawn by chafa), tags and musicman's fields (`FZX_MUSIC_TAGS`, `musicman view` cached per file until it changes; `FZX_MUSIC_MUSICMAN=off` leaves it out), the queue's with the player's state first; an album's cover and songs; an artist's albums; a playlist's songs | artist: `--artist A`; tracks: `--artist A --album B` or `--playlist P`; `--tag artist` | enter: queue plays the song, artists and albums and playlists open the next level, songs play their album or playlist from there; alt-enter play the selection (replacing the queue), alt-a add, alt-i play next, alt-x remove from the queue, alt-X delete playlists (confirm), alt-c clear the queue (confirm), alt-s save the queue as a playlist, alt-m play or pause, alt-n and alt-p next and previous, alt-* rate the selected songs (queue and songs; asks 0-5 in half steps, the first song's rating to edit) and alt-t their context, mood and picks (`FZX_MUSIC_EDIT_FIELDS`) in an fzf of the values in use (`musicman values`, 1.61+), each marked by how many of the songs have it, the ones every song has selected at the start: enter writes the difference (`musicman edit FILE field=+a,-b` per song; a value only some have stays unless selected), alt-enter also adds the query as `field:value`; both drop the songs' cached musicman answers, ctrl-y copy | files, artist and playlist names, "artist - album" |
| `colors` | 256 (xterm names), 16 (the terminal's 30-37 and 90-97: normal, bold, faint, inverted; preview: the background twin, the 256 index, every attribute), names (X11 rgb.txt in true color, nearest 256; the preview ends in a true-color gradient, banded where the terminal maps it to 256), fzx (`FZX_COLORS` of every layer, by module) | | alt-h copy hex, alt-s copy SGR parameters, alt-e copy escape sequences, ctrl-y copy | numbers, names or keys |
| `glyphs` | nerd (Nerd Font glyphs by `nf-` name from the module's `data/glyphnames.json`, Nerd Fonts 3.5.1, or the one the update action downloaded into the cache), unicode (UnicodeData.txt's named characters with their block; controls, surrogates, private use and the CJK and other ranges left out; a combining mark on ◌), blocks (Blocks.txt: each block's first visible character, range and named count; enter or ctrl-o opens it as `unicode --block NAME`), emoji (emoji-test.txt's fully-qualified ones, sequences whole, with group and subgroup); the Unicode data from `FZX_GLYPHS_UNICODE_DIR` (unicode-data); each list built once into `$FZX_CACHE_DIR/glyphs`, again when its source is newer. Preview: the glyph in colors and on light and dark, its name, code points, `\u` escape, UTF-8 bytes and HTML reference, then the rows of 16 around it with it marked (code points the list does not name are dots) | unicode: `--block NAME` | enter prints the glyphs, ctrl-o a character's block, alt-c copy code points, alt-n names, alt-e escapes, ctrl-y the glyphs, alt-U (nerd) download the latest glyph names | the glyphs |
| `history` | global (default: every host, each row naming its host), host, directory, session (zsh-histdb); rows: age of the latest run, runs, failed icon, duration, host, the command colored by its parts (only the command is searched), a command over several lines over several lines, padded under the command column (up to `FZX_HISTORY_MAX_LINES`, 4, then "… +N lines"; `FZX_HISTORY_MULTILINE=0` joins them with ↵); an exit status in `FZX_HISTORY_INTERRUPTED` (130, 141) is interrupted, not failed: its own icon, not red, left out of the failed toggle and the success rate; toggles failed, succeeded, runs (every run); sort recent/frequent/frecent | `[WORDS...]`: the starting query | alt-enter run (exit status 10), alt-c `cd DIR && COMMAND` (the directory it last ran in), ctrl-y copy, ctrl-x forget (confirm), alt-e failed only, alt-s succeeded only, alt-a every run | the command (multi-line kept) |
| `repos` | all, mine, changed, unsynced, todos; sort recent/name | | ctrl-o git module, alt-O files, ctrl-e edit, alt-W browse; actions: fetch, pull (`--ff-only`), rescan, links (every ghq repository linked into `FZX_REPOS_LINKS_DIR`) | the repository path |
| `claude` | all (your projects with a CLAUDE.md and every directory Claude has sessions for, from `claude-projects --tsv` in ~/.shell), own, active (uncommitted, unpushed, or a session in `FZX_CLAUDE_ACTIVE_DAYS`); sort recent (last session)/name; rows: name (`*`: sessions only), kind (git, dotbare, plain), version, branch, last session, sessions, changes, ahead/behind, open TODO items and P1s; preview: git status and commits, the top TODO items, the newest sessions' titles and last prompts | | ctrl-o Claude Code there (tmux: a window per project named after it; elsewhere in this terminal), alt-O the same with `--continue`, ctrl-e edit, alt-i the full `claude-projects show` card in $PAGER, alt-l git module, alt-d files, alt-t todos (the project's TODO.md: `todos --dir PATH`); action rescan; zsh: `fzx-claude-widget` (unbound) | the project path |
| `cron` | all (your crontab and the system's), user (your crontab), system (the other users' crontabs in `FZX_CRON_SPOOL_DIR` when sudo is cached; `FZX_CRON_SYSTEM_FILES`: /etc/crontab and /etc/cron.d, names cron skips left out; then anacron's jobs); commented-out entries are listed as disabled (in system files only when their user exists, so the crontab's example line is not), and `CRON_TZ=` puts the entries after it in that zone where cron honors it (`FZX_CRON_HONORS_TZ`: cronie does, Debian's cron does not; the preview says so), scripts (the run-parts directories, each script with the next run of the job that runs its directory, anacron's before a crontab line; names run-parts skips and scripts that are not executable marked); rows: next run (in 15m, due, at boot, disabled, invalid, never), schedule, user, command, file:line; sort next/file; read on every load (`FZX_PERSIST=none`). Preview: the command highlighted as sh, schedule, user and file, then the next `FZX_CRON_PREVIEW_RUNS` (5) runs; an anacron job's period, delay and last run; a script's file | | ctrl-e edit (your crontab: `crontab -e`; another user's: `sudo crontab -u`; system files and scripts: sudoedit at the line), alt-d disable or enable (comments the line out or in: another user's crontab through `crontab -u`, system files through `sudo -n sed -i`; scripts: `chmod -x` or `+x`, which run-parts honors; others than yours need a cached sudo, since the action runs in the background), alt-enter run now as cron would (as the entry's user, through sudo unless it is you, in its home, with only cron's environment: HOME, LOGNAME, SHELL=/bin/sh, PATH=/usr/bin:/bin, then the crontab's VAR= lines before the entry; `%` as cron takes it; anacron jobs through `anacron -d -f -n`; scripts as root from / with the first system file's variables; output stays until a key), ctrl-y copy | commands (scripts: paths) |
| `docker` | containers (running first), images, volumes, networks, compose; toggle running | | alt-s start/up, ctrl-x stop/down, alt-R restart, alt-x remove (confirm), alt-e exec a shell, alt-E run a typed command in each selected container (through its sh, else as words; readline with the history in `$FZX_STATE_DIR/docker/cmd_history` (`lib/ask.sh`), `FZX_DOCKER_CMD_HISTORY` kept; output stays until a key), ctrl-l follow logs, alt-i inspect; actions: kill, run (image), pull, prune, df (`docker system df` and `-v` in $PAGER, any mode) | ids (volume and project names) |
| `bluetooth` | paired (default: paired or bonded devices), all (every device bluez knows, a scan's finds included; toggle scan keeps one running meanwhile: the source starts `scan.sh` detached when the toggle is on in this mode and stops it on any other load, and it ends by itself once fzf's socket stops answering; it keeps a `bluetoothctl --timeout FZX_BLUETOOTH_SCAN_RUN scan on` client running, 60s at a time, and reloads through `$FZF_SOCK` on its `[NEW]`/`[DEL] Device` lines, at most once a second, since `busctl monitor` needs root); connected first, then paired, then the rest by signal; a header row with the controller (name, power, scanning); rows: state, an icon by bluez's `Icon` property, name, connected/paired/blocked or the signal, trusted, battery (`Battery1`), the address (two devices often share a name); read on every load (`FZX_PERSIST=none`) from one D-Bus call (`busctl GetManagedObjects`, ~20ms, where `bluetoothctl info` takes ~80ms a device; busctl cannot write JSON for number-keyed dictionaries such as the ManufacturerData of devices a scan finds, so then its text form is turned into the same JSON, `bluetooth::text_json`). Preview: `bluetoothctl info` (the header row: `show`), services by name, vendor-specific UUIDs left out | | alt-c connect, alt-d disconnect, alt-p pair (then trust and connect), alt-t trust or untrust (each device flips), alt-x remove (confirm), alt-P power the controller on or off, ctrl-y copy | addresses |
| `firewall` | rules (ufw's numbered rules: number, to, action colored by kind, from, comment; with ufw off, which numbers nothing, the rules added from `ufw show added`, ids `added:SPEC`, marked not in effect and deleted by rule), apps (the application profiles in `FZX_FIREWALL_APPS_DIR`, every section of each file: name, the rule naming it, ports, title); a header row with ufw's state, default policies and logging. ufw answers only root, so both read it through `sudo -n`: without a cached sudo the header says so and takes the state from ufw.conf, the rules list is empty and apps lists the profiles without their rules; read on every load (`FZX_PERSIST=none`). Preview: the header row's `ufw status verbose`; a rule's fields and the profile it names; a profile's title, description, ports, file and rules | | alt-x delete rules (confirm; highest number first, since numbers shift), alt-n add a typed rule and alt-I insert one above the focused rule (`ufw insert N`; readline with the history in `$FZX_STATE_DIR/firewall/rule_history`, `lib/ask.sh`; allow, deny, reject or limit only, checked with `ufw --dry-run` first), alt-a and alt-D allow and deny profiles, alt-e enable (confirm; `--force`), alt-d disable (confirm), all through sudo in the foreground so it can ask; ctrl-y copy | rules, profile names |
| `browser` | history (default: every profile's visits, newest first; `FZX_BROWSER_HISTORY_MAX`, 5000, a profile), bookmarks (by folder path); every Chromium-family profile (`FZX_BROWSER_CHROMIUM_DIRS`: Chrome, Chromium, Brave, Vivaldi; names from Local State) and Firefox profile (profiles.ini) merged, toggles chrome and firefox, sorts recent and visits; rows: profile, last visit or folder, title, URL. The databases are copied before sqlite3 reads them (a running browser locks them), Chrome's Bookmarks JSON read with jq; cached five minutes. Preview: title, URL, host and path, profile, visits and last visit or folder and date added | | enter opens in the row's own browser and profile (`--profile-directory` / Firefox `--profile`, Developer Edition's binary for dev-edition-* profiles; one call a profile, detached) and closes, ctrl-o opens and stays, alt-O xdg-open, ctrl-y copy URLs, alt-y titles | URLs |
| `applications` | actions (hidden, `--file FILE`, alt-a: an entry's `[Desktop Action]` groups in `Actions=` order, enter runs the Exec line: gtk-launch and dex cannot; the spec's field codes removed or filled in, the entry's Path and Terminal honored); apps: desktop entries (Type=Application) from `$XDG_DATA_HOME` and `$XDG_DATA_DIRS` (or `FZX_APPLICATIONS_DIRS`), the first directory holding an ID wins; by name: name, main category, comment; toggle hidden (a TryExec not installed, OnlyShowIn and NotShowIn against `$XDG_CURRENT_DESKTOP`, NoDisplay and Hidden ones, dim). Preview: the icon (the theme from GTK's settings.ini or gsettings, the themes it inherits, hicolor, pixmaps; an SVG first, else the largest PNG; chafa), name, generic name, comment, ID, Exec, categories, keywords, the entry's own actions, the file | | enter launches (`gtk-launch ID`, else `dex FILE`, detached) and closes, so a window-manager binding of `fzx -m applications --popup` is a launcher; ctrl-o launches and stays, alt-e edit, ctrl-y copy IDs, alt-y Exec lines | desktop IDs |
| `fonts` | families: fontconfig's (each font's first family name): name, mono marker, style count, formats; toggle mono (spacing mono, dual or charcell). Preview: a sample in the family's regular style, rendered by ImageMagick once per file and settings into `$FZX_CACHE_DIR/fonts` and drawn by chafa (`FZX_FONTS_SAMPLE*`; legible with `FZX_PREVIEW_IMAGE_FORMAT=kitty` or sixels, blocky with symbols), then spacing, formats and every style with its file | | ctrl-y copy names, alt-y the font files, alt-O open the folder | family names |
| `network` | ports (listening, by port or process), connections (by remote or process), interfaces, routes, wifi (nmcli; strongest first or by name), services (mDNS through avahi, cached `FZX_NETWORK_SERVICES_TTL`), files (hidden: lsof of a process); toggle root (ss and lsof through `sudo -n`) | files: `--pid PID` | ctrl-x SIGTERM to the port's process (confirm; sudo when not yours, `sudo fuser -k` without a visible process), ctrl-o the process's open files, alt-c connect (a saved connection, else nmcli asks for the password), alt-d disconnect (confirm), alt-s rescan wifi / browse services again, alt-O open web services, alt-u root, ctrl-y copy | addresses, interface names, SSIDs, file names |
| `github` | repos, code (GitHub search through gh; enter runs the query, GitHub qualifiers in it, a code query of qualifiers alone asks for words; an empty query lists the mode's recent searches; ctrl-t filters the results with fzf instead, and back), mine (yours, or `--owner NAME`'s), starred (both filtered by fzf: switching to or from them turns fzf's search on or off in place, `github::refresh`), tree (hidden: a repository's files at a commit), repo (hidden: a repository's hub, ctrl-o on a repository row: files, open issues, open pull requests and workflow runs with their counts and the last run's state, each row opening its list as a child session on enter or ctrl-o; preview: the README, the first issues or pull requests, the latest runs), runs (hidden: a repository's workflow runs, latest first: state, workflow, title, branch, event, age and duration; preview: the run and its jobs, a failed job's failed steps, cached by the run's last update), issues and prs (the repository here, from its origin remote, or `--repo`'s; with no GitHub repository here or the everywhere toggle (in place: the refresh hook rewrites the header naming the scope), the ones involving you anywhere through the search API; open ones, closed and merged too with the closed toggle; state icon, labels in their GitHub colors, author and age, a pull request's size and review; preview: the state's icon in its color, details, labels as chips, a pull request's branches, review (icon) and checks; the body and its reactions, then the comments and a pull request's reviews oldest first, as markdown, each under a header line fzx draws over a marker after rendering (author, association, verdict and date, a rule to the preview's width; `FZX_COLORS[github_author]`), and its reactions; then a pull request's review threads (GraphQL `reviewThreads`: REST has no resolved state) by file and line, each under a `path:line · outdated · resolved` header line with the last `FZX_GITHUB_HUNK_LINES` (4) lines of its diff and its comments, a resolved one as its header alone (cached with the view; a failed read leaves them out and is tried again); cached by the last update), notifications (unread, the latest 50; the read toggle adds read ones; each row links to its subject's page, so an issue's or pull request's preview and actions work on it); toggles private, public, sources, forks (every repository list; both of a pair or neither: all) and missing (not cloned here; cloned ones are marked); searches and lists cached for `FZX_GITHUB_CACHE_TTL`, issue, pull request, notification and run lists and the hub's counts for `FZX_GITHUB_ISSUES_TTL` (2m; dropped by their actions), trees and file contents by sha; GitHub's emoji shortcodes shown as characters; f2 lists every rate limit | `[--query Q]`; mine: `--owner NAME`; tree: `--repo OWNER/REPO [--ref REF]`; issues, prs, repo, runs: `--repo OWNER/REPO` | alt-O browser, alt-c clone (ghq; yours over ssh) and link, alt-d fetch (files, directories; a repository is cloned), ctrl-e a read-only copy in $EDITOR, alt-s star (starred: unstar), alt-F fork (confirm), alt-e settings page, alt-W the search on github.com, ctrl-y copy, ctrl-o the repository's hub (a code hit: its files), alt-p code search in the repository (code: narrow the search to it), alt-1..8 toggles; issues and prs: alt-k checkout (a pull request, or a branch for an issue, in the repository here or its ghq clone), alt-m comment ($EDITOR), alt-x close and alt-X reopen (confirm); runs: alt-l the log in $PAGER (failed jobs of a failed run; a running one is watched), alt-R rerun (a failed run's failed jobs), alt-x cancel (confirm); notifications: alt-u mark read; zsh: `ghs`, `ghsc`, `ghfetch URL [--dest DIR]` | github.com URLs |
| `tasks` | selected (this repository's tasks, read now, and the ones picked with ctrl-t), repos (every task of the projects chosen), all, projects (the repositories with tasks; enter or ctrl-t chooses); make targets (`##` docs), just recipes, package.json scripts (pnpm, yarn or bun by lockfile, else npm), Taskfile tasks (go-task; a `task` that is taskwarrior is left alone), cargo aliases, pdm/poe/hatch scripts; every repository scanned in parallel into `$FZX_CACHE_DIR/tasks/index`, served stale and scanned again in the background after `FZX_TASKS_TTL`; picks and projects in `$FZX_STATE_DIR/tasks`; the preview highlights the definition in its file's language (npm JSON, make Makefile, Taskfile YAML, TOML; just recipes and the command line as bash) | `[--paste PANE]` | enter runs the task in its repository (then waits for a key), alt-enter with arguments, ctrl-t pick, ctrl-e the definition in $EDITOR, alt-s scan again, ctrl-y copy; with `--paste` enter pastes the command line (`cd DIR && CMD` for another repository) into the pane and alt-x runs it in place | `project:task` (projects: directories); a colored icon per runner (`FZX_COLORS[tasks_kind_<runner>]`) with Nerd Font icons |
| `shell` | commands (the first of each name on PATH, then zsh's builtins and reserved words), aliases (regular, global, suffix), functions (completion functions with the completion toggle), params (the zsh dump's parameters, with the exported ones' values from the environment fzx started with, saved in the session; exported toggle: those only), completions (zsh-complete's bindings, ~/.shell's completion manager: one row per command with its provider, function and file, the commands you have (PATH, aliases, functions) unless toggle all; `zsh-complete list --tsv` takes 15s or more, so the mode keeps its list in `$FZX_CACHE_DIR/shell/completions.tsv` for `FZX_SHELL_COMPLETIONS_TTL` (a day) while the module stays `FZX_PERSIST=none`; the preview shows each binding's provider, function, file, upstream and revision and the file itself; alt-R asks again, alt-i runs `zsh-complete status` in the pager, ctrl-e edits the file). Aliases, functions and parameters come from `modules/shell/dump.zsh`, written by shell/fzx.zsh at the first prompt and by its shell widget (alt-s) before it opens the module, used for `FZX_SHELL_DUMP_TTL`, else an interactive `zsh -ic`. Values of names matching `FZX_SHELL_SECRETS` are masked and never written to the dump; the reveal toggle shows exported ones. Preview: a command's locations, whatis and tldr (else man) page, a builtin's zshbuiltins entry, an alias's definition and what its first word is, a function's definition (else its file), a parameter's whole value | | ctrl-e a function's file at its definition or a command's script in $EDITOR, alt-n the tldr or man page in the pager, alt-y copy parameter values, ctrl-y copy names; alt-1..3 toggles completion, exported, reveal | names |
| `todos` | here (this repository's TODO.md, or the one nearest `--dir`'s directory), all (every repository's: ghq's, `FZX_TODOS_ROOTS`, the git repositories directly under ~ such as ~/.shell (`FZX_TODOS_HOME_REPOS`), the TODO.md files the dotbare repository tracks such as ~/.config/tmux's (`FZX_TODOS_DOTBARE_DIR`, `git ls-files`, ~20ms), and `FZX_TODOS_FILES`; read on every load, so ctrl-r rescans); toggle done; sort urgency/file | `[--dir DIR] [--paste PANE] [QUERY...]` | ctrl-d done, ctrl-e edit at the line, ctrl-y copy titles, alt-y copy lines | `TODO.md:LINE ☐  (Pn) [category] Title` per item (with `--paste`, pasted into the pane) |
| `sessions` | every session tree but its own, newest first, each root followed by its screens depth first: state (kept: `--keep`, its owner gone; live: its owner runs, in another terminal; dead: not swept yet), module:mode (the screen on display bold), age, directory, arguments, query; read on every load (`FZX_PERSIST=none`). Preview: the path from the root, what enter does, module, mode, args, query, toggles, sort, directory, age, owner, placement and the cached views | | enter: a kept tree's session resumes here (`become(fzx --resume SID)`: this list's fzf is replaced, and its owner cleans up only its own tree). The list's owner adopts the tree: it copies its pid and start time into the tree's root, so other terminals see the tree live while it runs here, and records it in its own root's `state/adopt`, so its relaunch loop also relaunches the tree's `state/current` when a placement change into or out of a pane asks for it there; once the owner exits the tree is kept again, its owner gone, and the owner removes the resize hook its launches set; any other opens as a copy, a screen of this list (`nav goto` with the session's module, mode and arguments, then its query, toggles and sort copied over, so back returns to the list), since two fzfs on one session would share its socket and state and the live owner would delete it on exit; alt-x deletes kept trees (confirm; any of their screens names the tree; live ones refused), ctrl-y copy | session ids |
| `youtube` | search (YouTube through yt-dlp, `FZX_YOUTUBE_RESULTS` (30) a search; enter runs the query, an empty query lists the recent searches, `FZX_YOUTUBE_HISTORY_MAX`; searches cached `FZX_YOUTUBE_CACHE_TTL`), formats (hidden: a video's formats, `--url URL`, a child session from alt-F). Preview: the thumbnail (chafa, `FZX_YOUTUBE_THUMBS`, fetched once with curl) above the details and description | `[--query Q]`; formats: `--url URL` | ctrl-o play in mpv (detached, `FZX_YOUTUBE_PLAYER`), alt-a the audio in this terminal, alt-O browser, alt-m save as mp3 (`FZX_YOUTUBE_AUDIO_DIR`, needs ffmpeg), alt-d download (formats: also enter; the selected ones, a video-only one merged with the best audio; `FZX_YOUTUBE_VIDEO_DIR`), alt-F formats | video URLs |
| `menu` | list (module order), groups (most used first, then by group) | | enter opens the entry (on a group header: moves down) | entry id |
| `actions` | | groups of `names args... --fzx--` (built by the actions key) | enter runs the action, then back | |

`files` uses `FZX_PERSIST=cache:5m`; its base directory is resolved physically (`pwd -P`) because fd and rg
report resolved paths. `logs` reads `FZX_LOGS_FILES` (name to path) and `FZX_LOGS_GLOBS` from config.
`git` uses one line format (`id<TAB>display`) in every mode, so preview, actions and ctrl-o dispatch on the
current mode and switching never restarts fzf; an action that does not apply to the mode does nothing.
Its callbacks take the module args explicitly (`<verb> [module args] -- <ids>`), so a session opened on
another directory acts on that repository, standalone too. Failed actions wait for a key so the error stays
visible. Menu entries apply only inside a work tree (stash only when stashes exist); summaries report
changes, commits ahead/behind the upstream (no fetch), branch counts and stashes. `FZX_GIT_DIFF_FILTER`
(e.g. `delta --paging=never`) is applied to preview diffs. There is no discard/restore key on purpose.
`files` (files and dirs modes) and `dirs` decorate their display column with prettypath icons and colors
when `FZX_PRETTY` is `auto` (the default; on when `prettypath` is installed) or `1` (lib/pretty.sh): paths go
in absolute (prettypath drops relative ones), `--stat_file=false`, the base directory is cut from the
shown directory, and dirs joins the result back to its scores by path (a path missing from the result
keeps a plain display). Older prettypath versions strip `%` from `%path%` (the id) and drop paths
directly under `/`; `fzx::pretty_sound` probes the installed one once per binary (path and mtime, cached in
`$FZX_CACHE_DIR/prettypath/`), and with an old one those paths skip prettypath. About 13µs per path with
the fixed prettypath (20k paths in 0.26s), streamed.
Directories keep fd's trailing `/` into prettypath, which marks them as directories (folder icon) and drops
it from `%path%`; `fzx::pretty --dirs` adds it for lists without one (zoxide). prettypath's own roadmap
(stat only when the format needs it, `--base`, `--dirs`, a field of tabbed input) is in its TODO.md.
`files` lists in path order (component by component, so `a/` comes before `a-b/`) or newest first, and
leaves `FZX_FILES_EXCLUDES` (tool caches such as `.ruff_cache`) out of every mode. With follow off,
symbolic links are listed by their target's kind but not entered: fd's `--type f`/`--type d` skip links, so
a second `--type l` pass sorts them into files or dirs and drops broken ones. grep mode uses ripgrep, else
`grep -E` (smart case emulated, binary files skipped, no ignore files); it runs from inside the base with
`--exclude-dir='.?*'`, since GNU grep matches `--exclude-dir='.*'` against a `.` or dot-named base itself
and searches nothing. ctrl-t (`FZX_KEYS[files.filter]`, sessions only) switches grep mode between grepping
(the query is the term, a reload per change) and fzf filtering the matches (`unbind(change)+enable-search`;
the term is frozen in `state/files_grep_term`, the source greps it on reloads and toggles, and the header
shows it, through `meta/header` in the header position); again restores the term as the query and greps.
Entering the mode starts grepping. The preview starts with one line: the path under ~ and the size (a directory's
entry count, a link's target); images go through chafa (`FZX_FILES_IMAGE_FORMAT`, symbols by default).
`shell/fzx.zsh` also defines `fzf`: with no options and a terminal on stdin it runs `fzx -m files`,
otherwise the real fzf (`FZX_ZSH_NO_FZF=1` before sourcing leaves fzf alone).
`history` reads `FZX_HISTDB_FILE` (default `$HISTDB_FILE`, else `~/.histdb/zsh-history.db`) read-only, one row
per command: the id is the latest run's `history.id` (sqlite takes bare columns from the row holding
`max()`), and insert/run look the text up by id, since commands span lines. Directory mode matches the
logical `$PWD` (what histdb stores) and the resolved path, `LIKE` escaped with `!`. Session mode uses
`FZX_HISTDB_SESSION`, which the zsh widget sets from the shell's `HISTDB_SESSION` (outside the widget: this
host's latest session). The widget (ctrl-r, `FZX_ZSH_KEYS[history]`) starts in `FZX_ZSH_HISTORY_MODE`
(global by default; alt-0/alt-9 step through the modes), replaces the line with the result and accepts it
when fzx exits 10 (the run action). Delete removes every run and the command row, as histdb's `--forget`
does, and drops the cache. `FZX_PERSIST=none`: the module keeps its own cache instead. host and global by
recency, the slow ones (105k commands, 340k runs: 0.55s in sqlite before the first row), keep their raw rows in
`$FZX_CACHE_DIR/history/<mode>.v2.rows` (newlines as `\x1e`) with the last run's id; a run queries only the commands run from that
id on (histdb fills a run's status and duration when it ends, so the last cached one is read again), prints
them first and then the cached rows of the other commands. A database whose last id is below the cache's is
read whole. Rows are formatted on every run (ages stay current), through mawk when installed (about twice
as fast as gawk); `tee -p` writes the cache whole when fzf stops reading early.
`repos` lists `ghq list -p` plus repositories under `FZX_REPOS_ROOTS` (resolved, so `~/git` links into ghq
collapse) and joins them with `$FZX_CACHE_DIR/repos/status` (`path, branch, changed, ahead, behind, last commit,
open TODO items`). The list itself takes ~40ms; `git status` over 300 repositories takes ~15s even in
parallel (a few large checkouts dominate), so the scan is `start:+bg-transform(fzx _cb transform refresh)`:
at most once per `FZX_REPOS_TTL`, `FZX_REPOS_JOBS` at a time under `nice`, each status limited to
`FZX_REPOS_TIMEOUT`, one scan at a time (a lock directory), and a reload only when the cache changed. fetch
and pull rescan just their repositories. The mine mode's owners default to git's `github.user`, `ghq.user`,
then gh's `hosts.yml` (no network). The zsh widget (alt-r, `FZX_ZSH_KEYS[repos]`) cds into the result.
`claude` keeps `claude-projects --tsv` (a few seconds: git state, todo-status and the session store for ~50 projects) in `$FZX_CACHE_DIR/claude/projects` and formats it on every open, so ages stay current; the first open ever waits for the scan, later ones refresh it in the background as repos does (`FZX_CLAUDE_TTL`, a lock, a reload only when the rows changed; a failed or empty scan keeps the cache). The preview does not run `claude-projects show` (~2s, most of it test totals): it reads the cached row, git, TODO.md and the newest transcripts in `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<path with non-alphanumerics as ->` (their `custom-title` and `last-prompt` records, through jq), so sessions started only in subdirectories show as such; the full card is the card action.
`cron` turns each schedule into systemd OnCalendar expressions (fields expanded to lists, month and day
names, 7 as Sunday, the @ shortcuts; @weekly is Sunday, as cron has it, not systemd's Monday) and computes
every next run with one `systemd-analyze calendar` call, which prints a block per expression in order; when
it fails (it rejects one expression and the order no longer holds) each expression is asked on its own.
cron runs an entry whose day of month and day of week are both restricted (neither starts with `*`) on
either, where systemd needs both, so such an entry is two expressions and the earlier run wins. anacron
jobs come due PERIOD local days after their last run, the mtime of `FZX_CRON_ANACRON_SPOOL/JOB` (the
files themselves are root's); a job never run is due. Your crontab is changed through `crontab -l` and
`crontab -`; system entries are only edited (sudoedit), not disabled or run, since they run as root with
cron's environment.
`docker` actions check the mode they run in and refuse the ones that do not apply (exec on an image) rather
than guess; compose projects are addressed by name (`docker compose -p`). Image previews read config fields
through `index` and lists through `range`: docker 28 returns maps and `[]interface {}` there, where a missing
key is an error and `join` fails. exec tries `FZX_DOCKER_SHELLS` in order. The menu shows docker entries
only when the daemon answers within 2 seconds.
`todos` parses the TODO.md format itself (todo-status's rules: bold lead as the title, `(pN)` with p2 the
default, the first known `[category]`, extended by a `Categories:` line, `(due YYYY-MM-DD)`, continuation
lines, fenced blocks skipped) and matches `todo-status -l` on open items. Its id is `file\x1fline\x1ftitle`:
done (ctrl-d) checks the box only while that line still holds the open item with that title (todo-fzf
keeps a file snapshot for the same purpose), rewriting through a temporary file with the mode kept.
The here mode picks the nearest TODO.md in that format (a `## ` heading and a checkbox item) from the
current directory up to the repository's top, or the current directory only outside a repository, as
todo-status does; `--dir DIR` starts that search from DIR instead (the claude module's alt-t, a child session
per project, since module args are what `nav goto` passes on). `--paste PANE` hands the paste to the tmux server 0.3s after fzf exits (`run-shell -b -d`):
in tmux 3.9 a popup is a pane of its own, and the target's shell or /todo-pop's hook may not be ready yet.
/todo-pop, the `todo.pop` alias and tmux Alt-i open `fzx -m todos`, with todo-fzf kept as the fallback.
`packages` reads apt without apt-cache, which takes over a second per call on a full archive: installed
packages from `dpkg-query`, manual ones from `/var/lib/apt/extended_states`, a preview of one that is not
installed from the lists' Packages files (the highest version for this architecture, the long description
from Translation-en). Only the available (`apt-cache search`) and upgradable (`apt list --upgradable`)
lists come from apt, ~2s each, kept raw in `$FZX_CACHE_DIR/packages` and rebuilt when `/var/lib/apt/lists`
(and for upgradable `/var/lib/dpkg/status`) changes; rows are formatted on every load so the installed
marks stay current, in the C locale (half the time on 75k packages). Row ids name the manager
(`apt:NAME`, `flatpak:system:APP`, `gem:user:NAME`), so preview and actions dispatch on the id, and actions
group the selection into one command per manager. cargo upgrades reinstall from the crate's recorded
source (git repository with its branch, tag or rev; path). System pip is left out: PEP 668 makes it apt's.
Finding packages to install: snap and flatpak have local catalogs, so their -available modes are lists fzf
filters. snapd keeps every store name in `/var/cache/snapd/names` (no summaries: the preview fetches `snap
info`). Each flatpak remote's appstream XML (ostree checks it out with mtime 0, so the cache is stamped with
the active checkout's path) is read once into `$FZX_CACHE_DIR/packages/flatpak-<installation>-<remote>`, one
line per application with the details the preview shows; `flatpak search` takes 6-13s a call. crates.io, npm
and rubygems.org (its API: `gem search -r` takes over 20s) have no local catalog, so the search mode is
`--disabled` with a 0.3s debounced `change:reload`, asking every registry whose toggle is on in parallel and
keeping their order; PyPI has no search API, so a query that is a valid name is looked up as one. Previews of
packages that are not installed come from the network once a day per package (`FZX_PACKAGES_INFO_TTL`) in
`$FZX_CACHE_DIR/packages/info/<manager>/<name>`. Catalog flatpak ids carry their remote (`APP@REMOTE`) for
install.
`systemd` runs actions on system units through sudo when not root, bound with `execute` so sudo can
prompt; list parsing forces `SYSTEMD_COLORS=0` because users commonly export it. `list-units` only knows
loaded units, so the user and system lists merge `list-unit-files`: a unit file that is not loaded gets a
dim row with its file state (and no description, which only a loaded unit has). Timers and sockets come
from `list-timers`/`list-sockets -o json` (flat objects, read with awk), both managers in one list.

## Debugging

- `fzx --dry-run -m ps` prints the fully resolved fzf command, one option per line.
- Log: `$XDG_STATE_HOME/fzx/fzx.log`, one line per event tagged with session id and pid. Every callback
  logs its verb, arguments, exit code and duration. Stderr of source/action scripts goes to the log.
  Kept outside the session dir so it survives cleanup. Level via `FZX_LOG_LEVEL` (debug|info|warn|error).
  `fzx gc` moves it to `fzx.log.1` once it passes `FZX_LOG_MAX_KB` (1024), one old generation kept.
- Callbacks that answer with fzf actions (`transform`, `mode`, `nav`) log what they print at debug level
  (`actions: become:...`), so what fzf was told to do is visible in `fzx debug tail`.
- `FZX_TRACE=start,load,resize` (or `all`; also settable in the environment for one run) logs fzf events
  at info level: `event resize query='..' pos=3 matches=2/9 selected=0 size=80x24 key= action=`. Each is a
  `bg-transform(fzx _cb trace EVENT)` prepended to the event's own binding (fzf keeps one per event, and a
  colon-form action such as `start:reload:...` must stay last). `focus` and `change` start a process per
  cursor move or keystroke, so tracing is off by default.
- The cursor restore after `become()` binds `result-final:pos(N)+unbind(result-final)`, not `load`:
  `result-final` fires once the reloaded list is complete (not for the empty stdin before `start`), and
  `load` stays free for the prompt, which needs it on every reload.
- `fzx debug ls` lists sessions with module:mode, parent, owner and whether the owner is alive;
  `fzx debug tail [sid]` follows the log (all, or one session).
- Each session listens on `fzf.sock`. `fzx debug attach [SID]` is an interactive prompt against it (curl
  over the unix socket): `state [N]` summarises query, position, counts, selection, current item and the
  first N matches (jq when installed), `raw [N]` prints the JSON, any other line is sent as an fzf action.
  `fzx debug state [SID] [N]` and `fzx debug send ACTION [SID]` are the one-shot forms. Without a SID the
  newest session whose fzf answers is used: the one on screen, since sessions navigated away from no
  longer listen. Chosen over wrapping fzfg's Go `fzf-repl`: no build step, same API.
- The debug key (f2, `FZX_KEYS[debug]`) shows in the preview: session id, path in the tree, owner and
  whether it is alive, every `meta/` and `state/` key, the cached `data/` per mode (lines, age), the
  persistent cache entry for `cache:` modules, the module's own section (`<module>::debug` in its
  preview.sh, when it defines one; github lists every API rate limit), every `FZF_*` variable fzf exported to the preview, every
  `FZX_*` parameter with the module's config loaded (arrays one row per element, `FZX_KEYS[help]`), and
  the focused line raw (tabs shown as ⇥). Standalone runs show the `FZX_*`/`FZF_*` variables only.
  `fzx::bind` logs a warning when one key is bound twice (the later binding wins in fzf).

## Statistics

Append-only `$XDG_STATE_HOME/fzx/stats.tsv`, one row per event:
`ts_ms root sid module mode event duration_ms count detail`.

| Event | Recorded by | count | detail |
|---|---|---|---|
| `start` | owner, first launch | - | module and args |
| `exit` | owner, when the tree ends, also from its EXIT trap when the terminal hangs up or it is killed (not SIGKILL); duration is the whole run; sid/module/mode are where the user ended (`state/current` on the root) | - | `rc:<n> accept\|nomatch\|error\|abort\|hangup\|term\|rc` (hangup and term count as aborts in `fzx stats`) |
| `source` | load miss or hard reload | lines (`persist=none` streams to fzf through `tee`, a copy counted by `wc -l`) | `miss`, `reload`, `fail:<rc>` |
| `cache` | load served from cache | lines | `session`, `persistent` |
| `action` | module action | items | `<action>:<rc>` |
| `mode` | mode switch; mode column is the mode switched from | - | `<from>><to>[:restart]` |
| `nav` | navigation | - | `goto:<target>`, `back`, `back:none`, `abort` (Escape at the root), `resume`, `restart`, `placement:<placement>\|none` |

Previews are not recorded (they run on every focus change; the stats lib is loaded only when a handler
sets `_FZX_STAT`). The dispatcher writes the row with the duration it already measures, and resolves the
current mode itself: `FZX_MODE` inherited from fzf's environment goes stale after an in-place switch.
Recording is on unless `FZX_STATS=0` (env or config); `FZX_STATS` and `FZX_STATS_FILE` are exported at
launch because callbacks do not load config. Standalone runs are not recorded.

`fzx stats [--since 90s|5m|2h|7d] [--module NAME] [--raw]` prints, per module: runs, last use, run
duration avg/max, source runs avg/max (and failures), average items, cache hit rate (hits / (hits +
misses); hard reloads are not misses), accept/abort, actions and navigation counts. Runs, durations and
outcomes are credited to the module a tree started in; source, cache, action and nav rows to the module
where they happened. `--raw` prints the matching rows with a header. Needs an awk with `strftime` (gawk,
or mawk 1.3.4+).

`fzx gc` keeps the file bounded: once it passes 1 MiB it drops rows older than `FZX_STATS_MAX_AGE_DAYS`
(default 90). Rows appended during that rewrite can be lost.

## Menu

`fzx` with no arguments runs `modules/menu` as the root session.

**Entries** come from each module's optional `manifest.sh` (first module of a name on `FZX_MODULE_PATH`
wins; the menu itself is excluded):

```bash
ps::manifest() {
  fzx::entry ps "Your processes, busiest first"
  fzx::entry ps:all "All processes, busiest first"
  fzx::entry ps:tree "Process tree"
}
ps::applicable() { ... }   # optional: <target> [args]; fast exit-code check, run on every menu open
ps::summary() { ... }      # optional: <target> [args]; one short line, may be slow
```

`fzx::entry <module[:mode]> <description> [args...]` stores args `%q`-quoted. An entry's id is
`<module>#<index in its manifest>`, so hiding an entry with `applicable` does not renumber the others.
Each module is read in a subshell, so a broken manifest drops only that module (logged as a warning).
All modules are read at once, each into its own file, printed in module order; a module whose manifest
and `applicable` checks take longer than `FZX_APPLICABLE_TIMEOUT` (default 2s) is left out of that
listing (a warning; each module's time is logged at the debug level). A check that costs a request
(docker's daemon, gh's keyring token, git's work tree) is made once per module and kept in a variable
for its other entries.

**Order** follows the mode. `menu:list` (the default) keeps module order. `menu:groups` ranks entries by
use from the stats file (`fzx::menu_scores`): every launch (`start`, keyed by its module; the menu's own
are left out) and navigation (`nav goto:<target>`) adds `0.5^(age / FZX_MENU_HALF_LIFE_DAYS)` (7) to its
target, over the last `FZX_MENU_STATS_DAYS` (90). The `FZX_MENU_RECENT` (5) highest come first under a
"recent" header, then every other entry under its module's `FZX_MENU_GROUP` (no group: `other`), the
groups in `FZX_MENU_GROUPS` order and any others by name, each most used first and otherwise in module
order. A line is `id<TAB>display<TAB>header<TAB>target` (ctrl-y copies the target), shown with `--with-nth=2,3` and searched with `--nth=1`,
so a header (id `@<group>`, `FZX_COLORS[menu_group]`) shows but never matches a query: typing hides them.
fzf has no unselectable rows, so the grouped menu starts on the second row (`result-final:pos(2)` unless
a saved position or query is restored), enter on a header returns `down`, and its preview is empty.

**Opening** an entry is `enter:transform:fzx _cb nav entry {1}`: the callback re-reads that module's
manifest, then goes to the entry as a child of the menu (`nav goto`), so `alt-left` comes back to the
menu. Entries with the same module and args share one child session, so `ps` and `ps:tree` reuse one
session and its per-mode cache.

**Summaries** are cached per directory in `$XDG_CACHE_HOME/fzx/summary/<hash(cwd)>/<id>` and shown
immediately. `start:+bg-transform:fzx _cb transform refresh` then computes the stale ones (older than
`FZX_SUMMARY_TTL`, default 300s) for applicable entries, all in parallel, each cut off after
`FZX_SUMMARY_TIMEOUT` (default 3s), and answers with a single `reload` when anything changed. A
failing or timed-out summary is cached empty, so it is not retried on every open. The timeout watcher
must not hold the callback's stdout: fzf waits for every writer of a `bg-transform` to close it.
A summary describes what the entry would open from here (counts, the state of a server or repository)
and stays well under the timeout: one that would need an interactive shell or a walk of `~` (the zsh
key bindings without a saved dump, `dirs`) prints nothing instead. A summary that depends on more than the
directory has its manifest define `<module>::summary_key`, a fast command whose output joins the cache
key of every entry of the module (it is asked once per module and listing): git prints HEAD's commit and the times the index, HEAD, refs, fetches and stashes changed (so a
commit, stage, switch, fetch or stash shows at once; edits not yet staged wait for the TTL), capture the
active pane with its history size and cursor line (its entries count the lines, URLs, paths and the rest
there). Entries under old keys are left to `fzx gc` (`FZX_CACHE_MAX_AGE_DAYS`).

**Preview** (`modules/menu/preview.sh`) shows the entry as the menu line does (icon, target), its
description and summary; the module's modes (the entry's marked), toggles, sort orders and actions with
their keys (actions described for the entry's mode, the built-in ones left out); how often the module was
open (its sessions in `stats.tsv`), how runs ended there and its average source time; then the command
and the module directory.
Running `modules/menu/module.sh` directly lists entries but cannot open them.

## Shell integration

`shell/fzx.zsh` (source it from the zshrc) defines zle widgets that run a module and put the result on the
command line: `fzx-insert [fzx args]` inserts the output at the cursor as shell-quoted words, with paths
under the current directory made relative (against both `$PWD` and its resolved form, since modules print
resolved paths). Default keys, bound in viins, vicmd and emacs unless `FZX_ZSH_NO_BIND=1`; set
`FZX_ZSH_KEYS[<name>]` before sourcing to change one, or to empty to leave it unbound:

| Key | Widget | Does |
|---|---|---|
| alt-f | `fzx-files-widget` | insert file paths |
| alt-d | `fzx-dirs-widget` | `cd` into a directory below the current one, through accept-line so it is in history |
| alt-j | `fzx-jump-widget` | `cd` into a frecent directory (`fzx jump`: the recent module's directory mode, as `g` picks it) |
| alt-g | `fzx-git-widget` | insert git paths, a hash or a branch |
| alt-p | `fzx-ps-widget` | insert pids |
| alt-m | `fzx-menu-widget` | open the menu, insert what it returns |
| (none) | `fzx-claude-widget` | `cd` into a Claude Code project (the claude module) |
| (none) | `fzx-menu-popup-widget` | the same in a tmux or Zellij popup (`fzx --popup`; inline elsewhere): fzf's popup hands the selection back to the calling terminal |

`g` and `gg` are functions, not widgets (they cd the shell they run in), over `fzx jump` (lib/jump.sh),
which prints the directory; `FZX_ZSH_NO_JUMP=1` leaves them undefined:

- `g WORDS`: the best frecent match (`FZX_RECENT_DIRS_JUMP_MODE`: a directory mode of recent, or
  `MODULE:MODE` such as `dirs:bookmarks`; default recent's zlua, else dirs (zoxide), else fasd-dirs). Run again from inside a match, it goes to the match after it, wrapping, so repeating `g foo`
  steps through the matches with no saved state. A single word that is a directory is taken as is.
- `gg [WORDS]`: one match cds, several open the picker over them (`--select-1 --exit-0`); no words reuse
  the last ones (`_FZX_JUMP_LAST`, per shell). `fzx-cd` is the same function.
- No words (`g`): the picker over every frecent directory. No match: the picker over every directory under
  ~ (`dirs:all`) with the words as its query.
- After the cd the destination is shown through prettypath when installed.
- `v [WORDS]` (`fzx jump --files`, the recent module): opens every match in `$EDITOR` up to
  `FZX_RECENT_JUMP_MAX` (10), listing them first; more open the picker over them; no words, the picker over
  every recent file; no match, the files picker on `$PWD` with the words as its query (`fzx --query`). A
  path given as is opens straight away.

They replace `g_func`/`gg_func`/`v_func` (~/.fzf/functions.sh, now removed), `fgo` and `_fzf_dirs`. Their fallback walked all of
~ (430k directories, 43s here); `dirs:all` stops at `FZX_DIRS_ALL_DEPTH` (6) and skips
`FZX_DIRS_ALL_EXCLUDES` (VCS, cache and package directories) and streams into fzf with the query already
typed. fzf's own ctrl-t, alt-c and ctrl-r are left alone. `just install` symlinks `bin/fzx` into
`~/.local/bin` (or `$XDG_BIN_HOME`) and refuses to replace anything that is not a symlink.

Repositories and GitHub (they replace ~/.shell's repoman and gitman):

- `ghs [QUERY]`, `ghsc [QUERY]`: the github module's repository and code searches; `ghfetch URL...
  [--dest DIR]` downloads a file, or a directory under its own name, and clones a repository's URL
  (`FZX_ZSH_NO_GITHUB=1` leaves them out).
- `clone REPO...`: ghq get (OWNER/REPO, a URL, or anything ghq takes such as `git@bitbucket.org:o/r.git`;
  GitHub repositories of yours over ssh, `FZX_GITHUB_CLONE_SSH`), then the repository's link.
- `repos [--dry-run] [--clone-missing]`: link every ghq repository into `FZX_REPOS_LINKS_DIR` and remove
  the dead links there; with `--clone-missing` (`-u`) first clone your GitHub repositories that are not
  here yet (`FZX_ZSH_NO_REPOS=1` leaves both out).

The links (lib/links.sh): `FZX_REPOS_LINKS_DIR` (default `~/git` when it exists, else none) holds one
link per ghq repository named after it (`~/git/fzx -> ~/ghq/github.com/njhoffman/fzx`). A name two
repositories share keeps the link it has, and the other is reported as taken. Every clone fzx makes (the
github module's alt-c and fetch, `clone`, `--clone-missing`) adds its link; the repos module's `links`
action (in the actions menu) and `repos` bring the whole directory up to date.

Completion: `fzx completion zsh` prints a zsh completion function (`#compdef fzx`, lib/complete.sh) for
the commands, options and `-m module[:mode]` (with each module's and mode's description; hidden modes
left out) and session ids. It asks `fzx _complete targets|modules|sessions` while completing, so a new
module or mode needs no new script. Install it into a directory on `fpath` before compinit
(`fzx completion zsh > "${fpath[1]}/_fzx"`), or as a generated provider of ~/.shell's zsh-complete.

## Piping (later)

If stdin is not a tty and no module is given, match each manifest's `detect` against the first lines.

## Order of work

1. Session, callback dispatch, log, `--dry-run`, `ps` module; soft and hard reload.
2. `become` navigation (session tree, back, query/pos restore); modes (`ps`: user, all, tree; `ctrl-o`
   drills into a process's children).
3. Popout/popin; persist policies with a persistent cache; dead-session sweep (`fzx gc`).
4. Stats: event rows from callbacks and the owner; `fzx stats`; pruning in `fzx gc`.
5. Menu: manifests, `applicable`, cached per-directory summaries refreshed in the background, entries
   opened as children of the menu.
6. Config: module defaults before user config, module keys, `FZX_FZF_COLORS`, per-module history,
   `fzx config`; ported `files`, `logs`, `systemd`.

Tests (bats) at each step: module scripts are tested directly, libs are unit-tested, `bin/fzx` is tested
against a stub fzf.
