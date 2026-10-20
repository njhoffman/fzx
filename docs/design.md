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
              rewritten on every launch: modes (NUL-separated), persist
state/        one file per key, mutable: mode, query, pos (saved before every become()),
              popup (root only: the tree's placement)
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
| Mode change | `alt-0` / `alt-9` | `transform(fzx _cb mode next\|prev)`: `change-border-label`, `change-footer`, `reload`; fzf keeps running and keeps the query. When `<module>::mode_restart <from> <to>` returns 0, it restarts instead: `become(fzx --resume <sid> -m :<mode>)` |
| Go to module/subscreen | module-defined | `transform(fzx _cb nav goto <module[:mode]> [args])`: save query/pos, find or create the child, `become(fzx --resume <child>)` |
| Back | `alt-left` | `transform(fzx _cb nav back)`: `become` the parent; `bell` at the root |
| Popout / popin | `ctrl-space` | `transform(fzx _cb nav popout)`: toggle the root's `state/popup`, save query/pos, `become(fzx --resume <sid>)`; `bell` outside tmux/Zellij |

**Placement** belongs to the session tree (`state/popup` on the root; `fzx -m ps --popup[=OPTS]` starts
there, default `FZX_POPUP_OPTS=center,80%`) and is applied on **every** launch with fzf's `--popup`
(tmux 3.3+ or Zellij). This relies on observed fzf 0.74 behaviour that the man page does not describe: a
popup is two fzf processes, the original one in the caller's terminal and one inside the popup, and
`become()` from inside the popup is executed by the original one, in the caller's terminal. A launch that
did not ask for the popup again would therefore drop back inline. If a later fzf runs `become()` inside
the popup instead, `_placement` must skip `--popup` when already in one.

Navigation callbacks are `transform`s rather than plain `become`s so they can save `FZF_QUERY` and
`FZF_POS` first; a launch restores them with `--query` and `--bind 'load:pos(N)+unbind(load)'`. The border
label shows the path from the root (`ps:user > ps:user`) and the footer lists the modes with the active
one highlighted (only when a module has more than one mode).

## Module contract

```
modules/<name>/
  module.sh     loader: sources lib/core.sh and source.sh, defines <name>::opts and the optional
                <name>::modes and <name>::mode_restart hooks; runnable directly
  source.sh     defines <name>::source [args]; prints lines. Runnable directly
  preview.sh    defines <name>::preview <fields>; runnable directly
  actions.sh    defines <name>::action <action> <items...>; runnable directly
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

`<name>::modes` sets `FZX_MODES=(user all tree)`; without it a module has the single mode `main`. The
current mode is exported as `FZX_MODE` to the source, preview, action and opts hooks, so a script reads it
the same way under fzx and standalone (`FZX_MODE=tree modules/ps/source.sh`). Select it with
`fzx -m ps:tree`; the first mode is the default. Mode names match `[A-Za-z0-9_-]+`.

`<name>::mode_restart <from> <to>` (optional) returns 0 when the switch needs options fzf cannot change
while running. fzf only has `toggle-sort` and does not export the sort state (the user's own `ctrl-s`
toggles it too), so `ps` restarts when entering or leaving `tree`, which needs `--no-sort`.

`<name>::opts` appends to the `FZX_OPTS` array. It builds command strings through `fzx::cb <verb> [fzf
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
| `FZX_KEYS` | core: `reload_hard` ctrl-r, `reload_soft` alt-r, `mode_next` alt-0, `mode_prev` alt-9, `back` alt-left, `popout` ctrl-space | module keys are `<module>.<name>` (`ps.term`, `files.edit`, `systemd.restart`), set in the module's `config.sh` |
| `FZX_COLORS` | `mode_active`, `mode_inactive`, `menu_target`, `menu_summary`, `dim` | SGR parameters for what fzx draws itself |
| `FZX_FZF_COLORS` | empty | passed as `--color` when set; empty keeps the user's fzf theme |
| `FZX_HISTORY` | `1` | per-module `--history=$XDG_STATE_HOME/fzx/history/<module>`; `0` leaves fzf's history alone |
| `FZX_PERSIST`, `FZX_POPUP_OPTS`, `FZX_STATS`, `FZX_SUMMARY_TTL`, ... | | see their sections |

`fzx config [-m MODULE]` prints the layers that were loaded and the resolved keys, colors, base options
and settings.

## Modules

| Module | Modes | Args | Keys | Enter prints |
|---|---|---|---|---|
| `ps` | user, all, tree | `--ppid PID` | ctrl-x SIGTERM, ctrl-o children | pids |
| `files` | files, dirs, grep (as you type) | `[DIR]` | ctrl-e edit, ctrl-o into directory, alt-up parent | absolute paths (`path:line` in grep) |
| `logs` | files (newest first), units, docker | | ctrl-f follow (ctrl-c returns) | path, unit or container id |
| `systemd` | user, system, failed | | alt-s start, ctrl-x stop, alt-R restart, alt-e enable, alt-d disable, ctrl-l journal, ctrl-e edit | unit names |
| `menu` | | | enter opens the entry | entry id |

`files` uses `FZX_PERSIST=cache:5m`; its base directory is resolved physically (`pwd -P`) because fd and rg
report resolved paths. `logs` reads `FZX_LOGS_FILES` (name to path) and `FZX_LOGS_GLOBS` from config.
`systemd` runs actions on system units through sudo when not root, bound with `execute` so sudo can
prompt; list parsing forces `SYSTEMD_COLORS=0` because users commonly export it.

## Debugging

- `fzx --dry-run -m ps` prints the fully resolved fzf command, one option per line.
- Log: `$XDG_STATE_HOME/fzx/fzx.log`, one line per event tagged with session id and pid. Every callback
  logs its verb, arguments, exit code and duration. Stderr of source/action scripts goes to the log.
  Kept outside the session dir so it survives cleanup. Level via `FZX_LOG_LEVEL` (debug|info|warn|error).
- Callbacks that answer with fzf actions (`transform`, `mode`, `nav`) log what they print at debug level
  (`actions: become:...`), so what fzf was told to do is visible in `fzx debug tail`.
- `fzx debug ls` lists sessions with module:mode, parent, owner and whether the owner is alive;
  `fzx debug tail [sid]` follows the log (all, or one session).
- Each session listens on `fzf.sock`; `fzx debug attach` (later) wraps fzfg's `fzf-repl`.
- Later: a debug key that switches the preview to session state plus all `FZF_*` variables.

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
| `nav` | navigation | - | `goto:<target>`, `back`, `back:none`, `resume`, `popout:out\|in` |

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
