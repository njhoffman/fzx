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
children/     <hash(module, args)> -> child sid, so navigating to the same target reuses its session
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
| Escape | `esc` (`FZX_KEYS[escape]`) | `transform(fzx _cb nav escape)`: `become` the parent; `abort` at the root. Ctrl-C keeps fzf's abort behavior. Standalone modules keep fzf's Escape behavior. |
| Placement | `ctrl-^` | `transform(fzx _cb nav placement next)`: the next `FZX_PLACEMENTS` entry that can run here into the root's `state/placement`, save query/pos; inline/popup: `become(fzx --resume <sid>)`; into or out of a tmux pane (split, float): `state/relaunch` + `abort`, and the owner relaunches; `bell` when there is nowhere to go |

**Placement** belongs to the session tree (`state/placement` on the root): `inline`, `popup[:OPTS]`,
`split:DIR[,SIZE]` (DIR up/down/left/right) or `float[:OPTS]`. `fzx -m ps --popup[=OPTS]`,
`--split[=DIR,SIZE]` or `--float[=OPTS]` starts there; ctrl-^ cycles through `FZX_PLACEMENTS` (default
`inline split:down,40% popup float`), skipping entries that cannot run here (popups need tmux 3.3+ or
Zellij, splits tmux, floats a tmux with `new-pane`).

Floats are floating tmux panes (`tmux new-pane`), made by the owner like splits (`fzx::_fzf_pane`), not
fzf's `--popup`: inside one, `become()` keeps working as in a split. OPTS use the `--popup` syntax
(`[center|top|bottom|left|right][,W[%]][,H[%]]`, default `FZX_FLOAT_OPTS`), resolved to cells against the
window's size, since `new-pane` places a pane by its top-left corner.

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
  preview.sh    defines <name>::preview <fields>; runnable directly
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

### Modes

Modes (and the other components, `docs/components.md`) are rows of the module's `components.tsv`:

```
# kind  name  key  description                              flags
mode    user  -    your processes, busiest first            default
mode    all   -    all processes, busiest first             -
mode    tree  -    process tree (input order: sorting off)  restart
```

Columns split on tabs or runs of 2+ spaces; `key`/`flags` may be `-`. An executable table is run and its
output read (dirs lists only the modes whose tool is installed). `~/.config/fzx/modules/<m>/components.tsv`
replaces rows by kind+name (`=` keeps a field, the flag `off` removes the row, new names are added). The
resolved table is stored in `meta/components`, so callbacks read it without config. Without mode rows a
module has the single mode `main`; the row flagged `default` (else the first) starts; a mode row with a key
gets a binding straight to that mode.

The current mode is exported as `FZX_MODE` to the source, preview, action and opts hooks, so a script reads
it the same way under fzx and standalone (`FZX_MODE=tree modules/ps/source.sh`). Select it with
`fzx -m ps:tree`. Mode names match `[A-Za-z0-9_-]+`.

The `restart` flag marks a mode that needs options fzf cannot change while running; entering or leaving
it restarts fzf (query kept). fzf only has `toggle-sort` and does not export the sort state (the user's
own `ctrl-s` toggles it too), so `ps` marks `tree`, which needs `--no-sort`.

### Toggles and sort

`toggle` rows are independent switches (flag `on` = on at start), `sort` rows the sort orders (flag
`default`, else the first). They reach every module script as `FZX_TOGGLES` (the names that are on,
space-separated) and `FZX_SORT`, exactly like `FZX_MODE`, and live in `state/toggles` / `state/sort`;
standalone runs take them from the environment. A toggle row's key flips it; f11/f12 (`FZX_KEYS[sort_prev]`,
`[sort_next]`) cycle the sort when there are two or more, and a sort row's key selects it. Changes reload
in place (`transform(fzx _cb toggle NAME)`, `fzx _cb sort next|prev|NAME`); a row flagged `restart` restarts
fzf instead. The cache key is the view, not just the mode: `<mode>[+<toggles on>][@<sort>]`
(`data/all+kernel@mem`), so each combination is cached once. The footer shows modes, toggles and the sort
key, active ones highlighted (`FZX_COLORS[toggle_on|toggle_off|sort]`).

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
| `default` | also bound to enter; without one, enter prints the selection as before |
| `builtin` | fzx's own (`lib/builtin.sh`), not the module's `actions.sh` |

Built-ins come from `config/components.tsv` and every module gets them, listed after its own rows:
`copy` (the ids, `{+1}`), `copy-line` (`{+}`) and `view` (the module's preview of the item in `$PAGER`).
Clipboard: wl-copy, xclip, xsel, pbcopy, else tmux's paste buffer. A module row of the same name replaces
a built-in, and the flag `off` removes it (the menu and actions modules switch all three off).

Arguments are fzf placeholders appended to `fzx _cb action NAME`: `FZX_ACTION_ARGS` (default `{+1}`) for
the module's actions and `FZX_ACTION_ARGS_FOR[name]` for one action, built-ins included, both set in the
module's opts hook (it can depend on the mode). `view` takes the arguments of the module's `--preview`
callback. git passes its module args (`$a {+1}`), logs `{1} {2}`, files in grep mode `{1} {2}`.

The actions menu (`ctrl-\`, `FZX_KEYS[actions]`) is a child session of the built-in `actions` module, so
back, help, stats and debugging work as on any screen. The binding passes the selection already expanded,
grouped by argument template: `nav goto actions term,kill,copy {+1} --fzx-- copy-line {+} --fzx-- ...`.
The menu lists the parent's rows (from its `meta/components`), the preview shows the flags and the
arguments; enter runs `FZX_SESSION=<parent> fzx _cb action NAME ARGS` in the foreground and goes back
(`become` and `print` actions take over instead). An action flagged `reload` or `restart` sets the parent's
`state/fresh`, so its next load runs the source instead of serving the cache; `nav restart` uses the same
flag.

`FZX_HEADER_STYLE` draws that line: `minimal` (colored text, the default), `bubble` (a rounded pill per
item), `triangle` (one powerline with arrows), `none` (no line; every key still works). Pills use
`FZX_COLORS[pill_on|pill_off]` (background) and `[pill_on_fg|pill_off_fg]` (text) as 256-color numbers;
bubble and triangle need a Nerd Font. `FZX_HEADER_POSITION=footer` (default) or `header`: in the header
the line sits above the module's own `--header` (kept in `meta/header`), and in-place refreshes rebuild
both with `transform-header(fzx _cb header)`, since a module header can hold text that cannot be quoted
into `change-header(...)`. Standalone runs show the line too.

`<name>::opts` appends to the `FZX_OPTS` array. Key bindings go through
`fzx::bind <key> <action> <description>`, which records them for the help key (f1, `FZX_KEYS[help]`):
f1 runs `show-preview+preview:fzx keys ...` with every recorded binding (`k:SCOPE<TAB>KEY<TAB>DESC`), the
component rows (`c:...`) and the module's name as arguments; lib/keys.sh draws the page, so help needs no
callback and works standalone. Sections, each under a colored title: this screen's keys (the module's
bindings, including component keys and action rows), fzx's keys (every fzx screen), the global keys (the
user's `--bind`s from `FZF_DEFAULT_OPTS_FILE` and `FZF_DEFAULT_OPTS`, then fzf's defaults from a static
table of the fzf 0.74 man page; the first that binds a key wins), the components (modes, toggles, sort
orders, actions with their keys), then the free ctrl, alt, alt-shift and function keys. Keys are keycaps
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
| `FZX_KEYS` | core: `reload_hard` ctrl-r, `reload_soft` alt-r, `mode_next` alt-0, `mode_prev` alt-9, `back` alt-left, `escape` esc, `popout` ctrl-^, `actions` ctrl-\\ | module navigation keys are `<module>.<name>` (`ps.children`, `files.into`), set in the module's `config.sh`; action keys are in the action rows of `components.tsv` |
| `FZX_RESERVED_KEYS` | ctrl-f ctrl-b ctrl-u ctrl-w ctrl-g alt-g ctrl-p ctrl-n up down alt-b alt-f scroll-up scroll-down | keys modules may not bind (the user's scrolling and query editing); `fzx::bind` skips a module binding on one and logs a warning. fzx's own keys are not checked. Modules may still take keys the user binds elsewhere (ctrl-e edit replaces the user's `become(nvim)` with a per-module editor action) |
| `FZX_COLORS` | `mode_active`, `mode_inactive`, `menu_target`, `menu_summary`, `dim` | SGR parameters for what fzx draws itself |
| `FZX_FZF_COLORS` | empty | passed as `--color` when set; empty keeps the user's fzf theme |
| `FZX_HISTORY` | `1` | per-module `--history=$XDG_STATE_HOME/fzx/history/<module>`; `0` leaves fzf's history alone |
| `FZX_ICON`, `FZX_PROMPT`, `FZX_PROMPT_LOADING` | icon per module (Nerd Font), `{icon} ` | the prompt: `{icon}` in `FZX_COLORS[prompt_loading]` from start until `load`, then `[prompt_loaded]`; every reload (ctrl-r, mode/toggle/sort switches, reload actions) goes back to loading first. A blank prompt (`FZX_ICON=""`) keeps fzf's own prompt and binds nothing. `)` is dropped (it would end `change-prompt(...)`) |
| `FZX_ICONS` | `nerd` | icons in rows and previews (lib/icons.sh, `fzx::icon NAME`): `nerd` (Nerd Font glyphs), `unicode` (plain symbols, for terminals without a Nerd Font) or `none`. Used by the menu (each module's `FZX_ICON`, nerd only), git status (added, modified, deleted, renamed, untracked, conflict), repos (branch, changed, ahead, behind, todos), docker containers and logs (running, paused, stopped, created; file, unit), history (failed); the footer's toggles (on/off) and sort; the ps, history and repos previews' labels (`fzx::icon_label`, icons in `FZX_COLORS[preview_icon]`) |
| `FZX_PREVIEW_LAYOUTS` | `0:down,50%,border-top` `120:` (menu: `0:down,50%,border-top` `180:right,40%`) | the preview window by terminal width, see below; `()` turns it off |
| `FZX_PERSIST`, `FZX_POPUP_OPTS`, `FZX_FLOAT_OPTS`, `FZX_STATS`, `FZX_SUMMARY_TTL`, `FZX_TRACE`, ... | | see their sections |

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

## Modules

| Module | Modes | Args | Keys | Enter prints |
|---|---|---|---|---|
| `ps` | user, all, tree | `--ppid PID` | ctrl-x SIGTERM, kill (SIGKILL, confirm; menu only), ctrl-o children | pids |
| `files` | files, dirs, grep (as you type); toggles hidden (on), ignored, follow; sort path/recent | `[DIR]` | ctrl-e edit, ctrl-o into directory, alt-up parent, alt-h/alt-i/alt-l toggles | absolute paths (`path:line` in grep) |
| `logs` | files (newest first), units, docker | | alt-F follow (ctrl-c returns) | path, unit or container id |
| `systemd` | user, system, failed | | alt-s start, ctrl-x stop, alt-R restart, alt-e enable, alt-d disable, ctrl-l journal, ctrl-e edit | unit names |
| `git` | status, log, branches, stash (switch in place) | `[--all] [--rev REV] [DIR]` | alt-s stage, alt-u unstage, ctrl-e edit, alt-c switch branch (remote: `--track`), ctrl-o branch to its log | paths, hashes, ref names, stash names |
| `dirs` | all (fd over ~, the default), bookmarks (`FZX_DIRS_BOOKMARKS`, when configured) | `[WORDS...]`: the fzf query (all) or a bookmark filter, where a single match is printed without the picker | ctrl-o browse in files | the directory |
| `recent` | files: nvim (telescope-frecency's `file_frecency.sqlite3`, scored by its count and recency weights), fasd; directories: zlua (z.lua, `FZX_RECENT_ZLUA`), dirs (zoxide), fasd-dirs, visited (fasd by last visit); whichever are installed | `[WORDS...]`: files, each in order in the path, ignoring case; directories, the tracker's keywords; with words a single match is printed (`--select-1 --exit-0`) | ctrl-e edit, ctrl-x forget (fasd, zoxide, z.lua), ctrl-o browse in files | paths |
| `tmux` | sessions, windows, panes; capture: lines, urls, paths, words, hashes, ips; buffers; keys, commands, options, variables, styles, formats, status, hooks | `--pane %N`, `--scope pane|window|session|all`, `--table`, `--option-scope`, `--user-only`, `--builtin-only`, `--prefix`, `--options-file`, `--data-file` | alt-s switch/attach, ctrl-o capture, ctrl-x kill (confirm), alt-n rename, alt-m move, alt-p paste; toggles: viewport/changed/free/empty/short; actions: link/swap/mark, next/prev session, theme, scratch, nvim | plain IDs/text; colored display and hidden metadata; see [tmux](tmux.md) |
| `history` | session, directory, host (default), global (zsh-histdb); toggle failed; sort recent/frequent | `[WORDS...]`: the starting query | alt-enter run (exit status 10), ctrl-x forget (confirm), alt-e failed only | the command (multi-line kept) |
| `repos` | all, mine, changed, unsynced, todos; sort recent/name | | ctrl-o git module, alt-o files, ctrl-e edit, alt-w browse; actions: fetch, pull (`--ff-only`), rescan | the repository path |
| `docker` | containers (running first), images, volumes, networks, compose; toggle running | | alt-s start/up, ctrl-x stop/down, alt-R restart, alt-x remove (confirm), alt-e exec a shell, ctrl-l follow logs, alt-i inspect; actions: kill, run (image), pull, prune | ids (volume and project names) |
| `todos` | here (this repository's TODO.md), all (every repository's); toggle done; sort urgency/file | `[--paste PANE] [QUERY...]` | ctrl-d done, ctrl-e edit at the line, ctrl-y copy titles, alt-y copy lines | `TODO.md:LINE ☐  (Pn) [category] Title` per item (with `--paste`, pasted into the pane) |
| `menu` | | | enter opens the entry | entry id |
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
and searches nothing. The preview starts with one line: the path under ~ and the size (a directory's
entry count, a link's target); images go through chafa (`FZX_FILES_IMAGE_FORMAT`, symbols by default).
`shell/fzx.zsh` also defines `fzf`: with no options and a terminal on stdin it runs `fzx -m files`,
otherwise the real fzf (`FZX_ZSH_NO_FZF=1` before sourcing leaves fzf alone).
`history` reads `FZX_HISTDB_FILE` (default `$HISTDB_FILE`, else `~/.histdb/zsh-history.db`) read-only, one row
per command: the id is the latest run's `history.id` (sqlite takes bare columns from the row holding
`max()`), and insert/run look the text up by id, since commands span lines. Directory mode matches the
logical `$PWD` (what histdb stores) and the resolved path, `LIKE` escaped with `!`. Session mode uses
`FZX_HISTDB_SESSION`, which the zsh widget sets from the shell's `HISTDB_SESSION` (outside the widget: this
host's latest session). The widget (ctrl-r, `FZX_ZSH_KEYS[history]`) starts in the mode of the shell's
`SHELL_HISTORY_SCOPE`, replaces the line with the result and accepts it when fzx exits 10 (the run action).
Delete removes every run and the command row, as histdb's `--forget` does. `FZX_PERSIST=none`.
`repos` lists `ghq list -p` plus repositories under `FZX_REPOS_ROOTS` (resolved, so `~/git` links into ghq
collapse) and joins them with `$FZX_CACHE_DIR/repos/status` (`path, branch, changed, ahead, behind, last commit,
open TODO items`). The list itself takes ~40ms; `git status` over 300 repositories takes ~15s even in
parallel (a few large checkouts dominate), so the scan is `start:+bg-transform(fzx _cb transform refresh)`:
at most once per `FZX_REPOS_TTL`, `FZX_REPOS_JOBS` at a time under `nice`, each status limited to
`FZX_REPOS_TIMEOUT`, one scan at a time (a lock directory), and a reload only when the cache changed. fetch
and pull rescan just their repositories. The mine mode's owners default to git's `github.user`, `ghq.user`,
then gh's `hosts.yml` (no network). The zsh widget (alt-r, `FZX_ZSH_KEYS[repos]`) cds into the result.
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
todo-status does. `--paste PANE` hands the paste to the tmux server 0.3s after fzf exits (`run-shell -b -d`):
in tmux 3.9 a popup is a pane of its own, and the target's shell or /todo-pop's hook may not be ready yet.
/todo-pop, the `todo.pop` alias and tmux Alt-i open `fzx -m todos`, with todo-fzf kept as the fallback.
`systemd` runs actions on system units through sudo when not root, bound with `execute` so sudo can
prompt; list parsing forces `SYSTEMD_COLORS=0` because users commonly export it.

## Debugging

- `fzx --dry-run -m ps` prints the fully resolved fzf command, one option per line.
- Log: `$XDG_STATE_HOME/fzx/fzx.log`, one line per event tagged with session id and pid. Every callback
  logs its verb, arguments, exit code and duration. Stderr of source/action scripts goes to the log.
  Kept outside the session dir so it survives cleanup. Level via `FZX_LOG_LEVEL` (debug|info|warn|error).
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
  persistent cache entry for `cache:` modules, every `FZF_*` variable fzf exported to the preview, and
  the focused line raw (tabs shown as ⇥). Standalone runs show the `FZX_*`/`FZF_*` variables only.
  `fzx::bind` logs a warning when one key is bound twice (the later binding wins in fzf).

## Statistics

Append-only `$XDG_STATE_HOME/fzx/stats.tsv`, one row per event:
`ts_ms root sid module mode event duration_ms count detail`.

| Event | Recorded by | count | detail |
|---|---|---|---|
| `start` | owner, first launch | - | module and args |
| `exit` | owner, when the tree ends; duration is the whole run; sid/module/mode are where the user ended (`state/current` on the root) | - | `rc:<n> accept\|nomatch\|error\|abort\|rc` |
| `source` | load miss or hard reload | lines (`-` for `persist=none`, which streams) | `miss`, `reload`, `fail:<rc>` |
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

**Preview** shows what the entry opens, its description and summary, and `fzx stats` for its module.
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
