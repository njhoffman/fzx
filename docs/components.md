# Components: proposal (decided 2026-10-20)

Decisions: 1 B (tables, executable allowed), 2 environment variables, 3 a child `actions` module,
4 build fzf-tmux splits after checking `become()` in a split, 5 `minimal` in the footer, 6 a `fzf` shell
function. Built so far: tables, toggles and sort, header styles, actions (`docs/design.md`, Actions). The
`popout` built-in action was dropped: ctrl-space already does it, and the placement cycle replaces it.

PLAN.md (2026-10-20) asks for fzfmenu's reusable pieces in fzx: modes, toggles, actions (with an actions
menu and a default action), sort keys, header components with styles, per-module prompt icons with a
loading state, a placement toggle that includes tmux split panes, event tracing, and a help screen that
lists all of it. Modes exist today (`<module>::modes`, `FZX_MODES`); everything else is new. This page
proposes one design and lists the questions to settle before building it. Each question has a
recommendation; nothing here is implemented yet.

What stays true whatever is chosen: the listing (`source.sh`) and the actions (`actions.sh`) remain
standalone scripts; components only decide what is passed to them and what the header shows. With no
declarations, or the header style `none`, a module still works as it does now.

## 1. How a module declares its components

fzfmenu used one bash array per thing (`FZF_MODES`, `FZF_MODES_KEYS`, `FZF_MODES_HIDE_KEYS`,
`FZF_TOGGLES`, `FZF_ACTIONS`, `FZF_ACTION_DESCRIPTIONS`, ...), which PLAN.md wants to move away from.

| Option | Shape | Overriding | Cost |
|---|---|---|---|
| A. Arrays in config.sh | fzfmenu style, one array per field | reassign arrays | many variables; parallel arrays drift apart |
| B. A table per module (recommended) | `components.tsv` in the module dir, one row per component: `kind name key description flags` | a user file with the same name in `~/.config/fzx/modules/<m>/` replaces rows by `kind`+`name`; `key -` unbinds, flag `off` removes | one small parser in lib/; callbacks read it without loading config |
| C. Hook functions | `<m>::components` prints the same rows | users redefine the function | overriding means copying the whole function |

Recommendation B, with one addition from PLAN.md ("`FZF_MODES=modes.sh`"): if `components.tsv` is
executable it is run and its output read as the table, so a module can compute rows (dirs offers only
the modes whose tool is installed). The table replaces `<module>::modes`.

```
# kind   name     key     description                      flags
mode     user     f3      your processes                   default
mode     all      f4      all processes
mode     tree     f5      process tree                     restart
toggle   threads  alt-t   include threads                  on
sort     cpu      -       by cpu                           default
sort     mem      -       by memory
action   term     ctrl-x  send SIGTERM                     silent,reload
action   kill     -       send SIGKILL                     silent,reload,confirm
action   strace   -       trace system calls               foreground
```

`key -` means "no key, reachable from the actions menu or the mode keys only". Rows also become the
f1 help, so descriptions are written once.

## 2. How toggles and sort reach the source

Recommendation: environment variables, like `FZX_MODE` today: `FZX_TOGGLES="threads"` (the names that are
on) and `FZX_SORT=mem`. A source run standalone reads the same variables, so `FZX_TOGGLES=threads
modules/ps/source.sh` keeps working. The alternative, extra arguments, would mix with the module's own
arguments.

Toggling and sort changes reload in place (state in `state/toggles`, `state/sort`) unless the row has
`restart`, as modes do now (`mode_restart` becomes a flag).

## 3. Actions

- Kinds as flags: `silent` (execute-silent), `foreground` (execute; sudo, editors, followers),
  `become` (replace fzf, e.g. open in an editor and leave), `print` (accept and print a value); plus
  `reload` / `restart` afterwards and `confirm` (ask first).
- Built-in defaults every module gets unless it overrides the name: `copy` (the ids), `copy-line`,
  `view` (the preview in a pager), `popout` (the placement toggle). A module's `actions.sh` handles its
  own names; built-ins live in lib/.
- Default action: the row flagged `default` runs on enter; without one, enter keeps printing the
  selection (today's behaviour, which scripts and the zsh widgets rely on).
- Actions menu (fzfmenu's `ctrl-\`). Recommendation: a built-in `actions` module opened as a child
  session with the selected ids as its arguments, listing the module's actions; enter runs one, back
  returns. It reuses navigation and gets help, stats and debugging for free. The alternative, swapping
  the list in place with `reload` + `change-preview`, needs its own state machine for "which list is
  showing".

## 4. Placement, including tmux split panes

`--popup` (today's ctrl-space) cannot make split panes. Proposal: `FZX_PLACEMENTS=(inline popup:center,80%
split:-d,40% split:-r,50%)` and the ctrl-space key cycles through them. Splits run through `fzf-tmux`
(its -u/-d/-l/-r/-w/-h/-x/-y flags; fzf-rsc/fzfp shows the popup side). fzf-tmux runs fzf in another pane,
so a switch has to go through the owner again (the relaunch loop dropped in step 3 comes back, for this
case only).

Risk to check before building: how `become()` behaves inside an fzf-tmux pane (navigation and mode
restarts use it). If it runs in the split pane, splits behave like popups do now; if not, every
navigation would have to relaunch through the owner.

## 5. Header components and styles

The header line is rendered from the table: modes (one active), toggles (each on or off), the sort key,
and key hints. Settings:

- `FZX_HEADER_STYLE`: `bubble` (rounded powerline caps), `triangle` (powerline arrows), `minimal` (plain
  text), `none` (no line; keys and behaviour unchanged).
- `FZX_COLORS[component_active]`, `[component_inactive]`, per kind if wanted
  (`[toggle_on]`, `[mode_active]`, ...), overridable per module.
- `FZX_HEADER_POSITION`: `header` | `footer` (modes are in the footer today).

Glyphs come from Nerd Font private-use code points, so `minimal` is the safe default for terminals
without them.

## 6. Prompt icon and loading state

`FZX_PROMPT` and `FZX_PROMPT_LOADING` per module (config). `start` changes the prompt to the loading form
before the reload; `load` changes it to the loaded form. Your `.fzfrc` no longer binds `load` (dotfiles
7c9204bce), so fzx owns it and composes its own load actions (prompt, then the cursor restore).

## 7. Event tracing

`FZX_TRACE=start,load,resize,result,focus,change` (or `all`) adds a `bg-transform` callback per listed event
that logs the event with `FZF_QUERY`, `FZF_POS`, `FZF_MATCH_COUNT`, `FZF_LINES`/`COLUMNS` and prints no
action. `bg-transform` keeps the UI from waiting; `focus` and `change` still start a process per event, so
tracing is off by default.

## 8. prettypath

First the glyph bug (TODO). Then `FZX_PRETTY=1` makes files and dirs build their display column with
prettypath (icon + colors); ids stay plain paths, so output does not change. For plain fzf with nothing
piped in, PLAN.md wants the same listing: proposal, a `fzf` shell function in `shell/fzx.zsh` that, when
stdin is a terminal and no options are given, runs `fzx -m files` instead, and otherwise calls the real
fzf. An alternative is `FZF_DEFAULT_COMMAND`, but that cannot also set the `--with-nth`/`--accept-nth`
the formatted lines need without affecting every other fzf call.

## 9. Help and free keys

f1 adds the table (modes, toggles, sort, actions with their keys). A second page lists every key fzf
binds: fzf's defaults (a static table from `fzf --man`), the user's FZF_DEFAULT_OPTS and
FZF_DEFAULT_OPTS_FILE binds, and fzx's own, and the keys left free for components.

## Questions

1. Declarations: B (`components.tsv`, executable allowed), A or C?
2. Toggles and sort as `FZX_TOGGLES` / `FZX_SORT` environment variables?
3. Actions menu as a child `actions` module, or in place?
4. Placement: build the fzf-tmux split support, after first checking `become()` inside fzf-tmux?
5. Header: default style `minimal`, header or footer by default?
6. prettypath for plain fzf: the `fzf` shell function, or leave plain fzf alone?
