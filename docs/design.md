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
meta/         one file per key: module, module_dir, cwd, owner_pid, started_ms, args (NUL-separated),
              root, parent (children only); modes (NUL-separated, rewritten on every launch)
state/        one file per key, mutable: mode, query, pos (saved before every become())
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

Persist policies (step 3): `none` deletes the session dir; `session` (default) keeps it until the owner
exits; `cache:<ttl>` moves `data/` into `$XDG_CACHE_HOME/fzx/<module>/<hash(args,cwd)>` for reuse by
later runs and by menu summaries. Session dirs whose owner pid is dead are swept on startup.

Implemented so far: the owner deletes the tree on exit; `--keep` / `FZX_KEEP=1` keeps it for debugging.

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
| Popout (step 3) | | `become(fzx --resume --tmux center,80%)`; fzf 0.74's native `--tmux` |

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
  manifest.sh   (step 5) name, desc, entries, persist, applicable(), summary(), detect
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
| `mode`, `nav` | `fzx _cb mode/nav ...` | not available |

Running `module.sh` directly gives the same interface with global defaults but no session, cache,
navigation, mode keys or logging of callbacks; `FZX_MODE` picks the mode. Modules guard session-only
bindings with `fzx::in_session`.

Modules are found in `$FZX_MODULE_PATH` (default `~/.config/fzx/modules:<repo>/modules`).

## Configuration

Sourced in order; later layers override earlier ones by reassignment:

1. `config/defaults.sh` (repo)
2. `~/.config/fzx/config.sh`
3. `modules/<m>/config.sh`
4. `~/.config/fzx/modules/<m>/config.sh`
5. CLI flags

Globals: `FZX_FZF_OPTS` (array of base fzf options), `FZX_KEYS` (core keys: `reload_hard`, `reload_soft`,
`mode_next`, `mode_prev`, `back`) and `FZX_COLORS` (SGR parameters: `mode_active`, `mode_inactive`). More
colors and layout keys arrive in step 6.

## Debugging

- `fzx --dry-run -m ps` prints the fully resolved fzf command, one option per line.
- Log: `$XDG_STATE_HOME/fzx/fzx.log`, one line per event tagged with session id and pid. Every callback
  logs its verb, arguments, exit code and duration. Stderr of source/action scripts goes to the log.
  Kept outside the session dir so it survives cleanup. Level via `FZX_LOG_LEVEL` (debug|info|warn|error).
- `fzx debug ls` lists sessions with module:mode, parent, owner and whether the owner is alive;
  `fzx debug tail [sid]` follows the log (all, or one session).
- Each session listens on `fzf.sock`; `fzx debug attach` (later) wraps fzfg's `fzf-repl`.
- Later: a debug key that switches the preview to session state plus all `FZF_*` variables.

## Statistics (step 4)

Append-only `$XDG_STATE_HOME/fzx/stats.tsv`: `ts sid module mode event duration_ms items exit_action`.
`fzx stats` summarises with awk.

## Menu (step 5)

`fzx` with no arguments runs `modules/menu`. Entries come from module manifests (several per module, with
arguments). `applicable` is a fast exit-code check that hides irrelevant entries; `summary` is slow, cached
per module and context with a TTL, and filled in after first render via `bg-transform`/`reload`.

## Piping (later)

If stdin is not a tty and no module is given, match each manifest's `detect` against the first lines.

## Order of work

1. Session, callback dispatch, log, `--dry-run`, `ps` module; soft and hard reload.
2. `become` navigation (session tree, back, query/pos restore); modes (`ps`: user, all, tree; `ctrl-o`
   drills into a process's children).
3. Popout; cleanup by persist policy; dead-session sweep.
4. Stats.
5. Menu with `applicable`, then cached summaries.
6. Config layering for colors and keys; port `files`, `logs`, systemd.

Tests (bats) at each step: module scripts are tested directly, libs are unit-tested, `bin/fzx` is tested
against a stub fzf.
