> Pane capture (lines, URLs, paths, words, hashes, IPs) moved to its own module, `capture` (0.15.0):
> `fzx -m capture:urls`; the `--scope` option and `FZX_TMUX_LINES`/`FZX_TMUX_SCOPE` are gone.

# Tmux module

`fzx -m tmux` lists sessions. Enter prints the selected ID or text, as in the other modules.
`alt-s` switches to a session, window or pane; outside tmux it attaches instead.

```sh
fzx -m tmux:panes
fzx -m capture:urls
fzx -m capture:paths --pane %3
fzx -m tmux:buffers
fzx -m tmux:options
fzx -m tmux:keys --table prefix,root
fzx -m tmux:options --option-scope session --user-only
fzx -m tmux:formats
fzx -m tmux:status
```

The modes are sessions, windows, panes, lines, urls, paths, words, hashes, ips (IPv4), buffers,
keys, commands, options, variables, styles, formats, status and hooks. `alt-0` / `alt-9` cycle modes.
Lists use aligned columns, colored scopes/names/values, syntax highlights and full descriptions in
the preview. Reference rows are returned as text and never executed.

Keys show their table, key, note, command and `*` changed / `+` repeat markers. Their preview compares
the current binding with the installed tmux defaults. `--table` accepts comma-separated tables
(`prefix`, `root`, `copy-mode`, `copy-mode-vi`, custom tables), or `all` (the default).

Options and hooks show server, global session/window and local session/window/pane scopes; hooks list
only the hooks that are set (`alt-e` includes the unset ones), as `tmux.options -H` does. Local
overrides carry a `*`; the preview includes the parent value. `--option-scope` selects `server`,
`global-session`, `global-window`, `session`, `window`, `pane`, or `all`. `--user-only` / `--builtin-only`
filter user options. The `changed` toggle shows local differences and additions.

Variables show their format expression, short alias, current value and description, with full values
in the preview. One `display-message -a` call supplies live values. Styles display actual foreground,
background and attributes, with color swatches; formats and status show expanded templates with their
embedded styles. `--options-file FILE` accepts `name value` or `name=value` assignments, while
`--data-file FILE` supplies variable assignments for offline style/format samples (simple `#{name}`
and `#S`/`#W`-style substitutions). Using both avoids querying the live server for those samples.

| Key | Action |
|---|---|
| Enter | Return the selection |
| alt-s | Switch/attach to a session, window or pane |
| ctrl-o | Open captured lines from the selected session's active pane, window or pane |
| ctrl-x | Confirm, then kill selected objects or delete selected buffers |
| alt-n | Rename the first selected session/window or set its pane title |
| alt-m | Move the first selected window or pane; prompt for the destination ID |
| alt-p | Paste selected captured text or buffers into the invoking pane, without Enter |
| alt-v | Toggle capture of only the visible viewport (also in copy mode) |
| alt-d | Keys/options/hooks: show only changes |
| alt-u | Keys: show unassigned keys in the selected table (prefix when all tables are selected) |
| alt-e | Variables and hooks: include empty values |
| alt-c | Commands: switch between full signatures and short names/aliases |
| ctrl-\ | Actions menu, including link/swap/mark, next/previous session, themes, scratch popup, nvim layout and nvim (the whole reference list in nvim) |
| ctrl-r | Refresh from tmux |

Actions apply to their corresponding modes. Switch, rename, move, swap, link and mark use the first
selection; kill and paste use all selections. Destination prompts accept IDs shown by Enter (`$N`
for sessions, `@N` or `$N:@N` for windows, `%N` for panes); moving a window also accepts `$N:INDEX`.
Blank input cancels. Move/link never overwrite an occupied window slot.

Capture defaults to the invoking pane and up to 2,000 scrollback lines, with wrapped lines joined.
`--pane %N` chooses another pane. `--scope pane|window|session|all` broadens capture. Every capture
result shows its source pane; duplicate values keep their first occurrence. Paths are text candidates,
including relative names and `path:line`, rather than files verified on the local filesystem. Quoted
paths containing spaces can be selected intact in lines mode. The originating pane remains the paste
destination when using a popup or split, unless `--pane` explicitly chooses another destination.

Configure `FZX_TMUX_LINES` and `FZX_TMUX_SCOPE` in the module's user config. The module defaults to
`FZX_PERSIST=none` so returning to a screen refreshes the live tmux state. The standalone entry point
is `FZX_MODE=urls modules/tmux/module.sh --pane %3`.

Reference formatting uses Python 3's standard library. Descriptions come from the installed tmux
manual (rendered 400 columns wide so signatures stay on one line, with hyphenation breaks joined), cached
by its path and modification time. Options and hooks for every scope come from one tmux client call.
Formats and status expand each template with its own `display-message`, which also runs the
template's `#(...)` jobs on the server, so these two screens are the slowest. Key defaults come from a private server with an
empty config, cached by binary/version. Colors can be overridden in user config through
the `FZX_COLORS` roles `tmux_name`, `tmux_value`, `tmux_scope`, `tmux_key`, `tmux_changed`,
`tmux_dim`, `tmux_title` and `tmux_flag`. For example, `FZX_COLORS[tmux_name]='38;5;81'`.

## Alias functionality

| Shell helper | Module equivalent |
|---|---|
| `tmux.keys` | keys mode, table filter, notes, modified/default comparison, free keys |
| `tmux.* --nvim` | nvim action: the current reference list as plain text in nvim (`ft=tmux`, `FZX_TMUX_NVIM`) |
| `tmux.commands` | commands mode, full/short toggle, documented preview |
| `tmux.options` | options and hooks modes, scopes, user-only filtering and parent comparisons |
| `tmux.variables` | variables mode with aliases, descriptions and empty-value toggle |
| `tmux.styles` | styles, formats and status modes, including file-backed samples |
| `tmux.n` / `tmux.p` | next-session / prev-session actions, wrapping within a session prefix |
| `tmux.theme-main` / `tmux.theme-float` | theme-main / theme-float actions |
| `tmux.pop` | scratch action |
| `tmux.nvim` | nvim-layout action |
| `tmux.fzf` | fzx's existing `--popup` and placement cycle |

`--prefix TEXT` filters the sessions list and next/previous actions. The actions also honor
`TMUX_PREFIX` when no explicit prefix is supplied; `FZX_TMUX_SESSION_PREFIX` sets a module default.
Theme actions use the selected object's session, or the invoking pane's session on reference screens.
The theme, scratch and nvim actions call the installed alias helpers under `FZX_TMUX_HELPERS`
(default `$XDG_CONFIG_HOME/tmux/scripts`, or `~/.config/tmux/scripts`), reporting an error if absent.
They run only when explicitly chosen.

## Sources and follow-ups

The implementation draws on these local references:

| Reference | Functionality used |
|---|---|
| `~/.shell/aliases/user.sh`: `tmux.keys`, `.commands`, `.options`, `.variables`, `.styles` | Reference browsers |
| `~/.shell/functions/t` | Switch inside tmux, attach outside |
| `resources/fzfmenu/proto-widgets/tmux/{ftsess,ftwind,ftpane}` | Session/window/pane navigation |
| `resources/fzfmenu/widgets/tmux/fzf.tmux-capture*` | Capture scopes, visible viewport, source pane labels |
| `resources/fzfmenu/proto-widgets/tmux/{tmux-butler,quetty,quetty-fzf,filters/*}` | Extraction modes, deduplication and explicit pasting |
| `resources/fzfmenu/proto-widgets/tmux/manage-window` | Move/link/swap windows |
| `resources/fzfmenu/proto-widgets/tmux/jump-marked` | Mark selected panes |

Potential follow-ups from the same references: persistent snippet/paste history, edit selection before
pasting, command-line and quoted-string filters, IPv6 extraction, marked-pane round trips, opening URLs,
and tmuxp/resurrect session definitions.
