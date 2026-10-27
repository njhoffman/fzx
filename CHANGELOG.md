# Changelog

All notable changes to fzx are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.9.2] - 2026-10-26

### Changed

- todos: the here mode uses the nearest TODO.md in the todo format, from the current directory up to the
  repository's top (outside a repository, the current directory only); a TODO.md in another format is
  passed over. This matches todo-status, so /todo and the picker show the same list.
- /todo-pop, the `todo.pop` alias and tmux Alt-i now open `fzx -m todos` (todo-fzf stays as the fallback
  when fzx is not installed).

### Fixed

- todos `--paste`: the tmux server pastes 0.3s after the picker exits, so the lines arrive once the popup
  has closed. Under tmux 3.9 the paste could land before the target pane was ready.

## [0.9.1] - 2026-10-26

### Changed

- docker: ctrl-l on several containers follows their logs together, each line prefixed with the
  container's name in its own color. The run action asks for the run options (default: interactive,
  removed on exit, this directory mounted at /work) and a command (default: a shell).

## [0.9.0] - 2026-10-26

### Added

- todos module: the open items of TODO.md files (the format Claude Code keeps), from this repository or
  from every repository, sorted by urgency (overdue, priority, due date) or file order, with the item's
  card (priority, category, due date and details rendered as markdown) in the preview. ctrl-d marks an
  item done (refused if the file changed under it), ctrl-e opens it in your editor at its line, ctrl-y
  copies titles, alt-y the lines, alt-d shows completed items too. Enter prints
  `TODO.md:LINE ☐  (Pn) [category] Title` lines; `--paste PANE` pastes them into a tmux pane instead,
  as todo-fzf does for /todo-pop.

## [0.8.0] - 2026-10-26

### Added

- docker module: containers (running first, state colored), images (dangling ones dim), volumes (unused
  ones dim), networks and compose projects. alt-s starts (compose: up -d), ctrl-x stops (compose: down),
  alt-R restarts, alt-x removes, alt-e opens a shell in the container (the first of zsh, bash, ash, sh),
  ctrl-l follows the logs, alt-i shows docker inspect; kill, run (an image), pull and prune are in the
  actions menu. The preview shows a container's state, ports, mounts, networks and latest logs, an
  image's details, users and layers, a volume's or network's containers, a project's services.

## [0.7.0] - 2026-10-26

### Added

- repos module: your git repositories (ghq's, and any under `FZX_REPOS_ROOTS`) with branch, uncommitted
  changes, commits ahead/behind, open TODO.md items and the age of the last commit. The list opens at
  once from the last scan, and a background scan refreshes it. Modes: all, mine, changed, unsynced
  (ahead or behind), todos; sort by last commit or name. The preview shows status, recent commits and
  the open TODO items by priority. ctrl-o opens the git module on the repository, alt-o its files,
  ctrl-e your editor, alt-w the remote in the browser; fetch and pull work on several at once. alt-r in
  zsh cds into the chosen repository.

## [0.6.0] - 2026-10-26

### Added

- history module: your zsh-histdb history, one row per command with when it last ran, how often, and
  failed runs in red. Modes: this shell session, this directory (and below), this machine, every machine;
  alt-e shows only failed commands, f11/f12 sort by recency or frequency. The preview shows the whole
  command, its last run (status, duration, directory, host) and the directories it ran in. Enter puts the
  command on the line, alt-enter runs it, ctrl-x forgets it. The zsh integration binds it to ctrl-r,
  starting in your `SHELL_HISTORY_SCOPE` with what you typed as the query.

## [0.5.0] - 2026-10-26

### Added

- tmux: an `nvim` action (actions menu) opens the current reference list (keys, commands, options,
  variables, styles, formats, status, hooks) as plain text in nvim with tmux syntax, like the
  `tmux.*` helpers' `--nvim`.

### Changed

- tmux hooks lists only the hooks that are set; `alt-e` (the empty toggle) includes the unset ones.
- tmux options, styles and hooks load faster: every scope comes from one tmux call.

### Fixed

- tmux formats no longer lists `extended-keys-format`, which is a keyword option, not a template.
- tmux command and option references no longer start with a leftover piece of the signature or the
  `(alias: ...)` line, and words the manual hyphenated across lines are joined again.
- tmux formats and status expanded every template twice.

## [0.4.0] - 2026-10-26

### Added

- Responsive preview: `FZX_PREVIEW_LAYOUTS` picks the preview window from the terminal width, at start and
  on every resize. Entries are `MINCOLS:SPEC` in `--preview-window` syntax; an empty SPEC is the module's
  own layout and `hidden` hides the preview. The default puts the preview under the list below 120
  columns; the menu keeps it under the list until 180 columns, then beside it. A preview you hid by hand
  stays hidden when the layout changes (toggling it back shows the new layout), also across mode changes
  and restarts. Set per module in its config.sh; `FZX_PREVIEW_LAYOUTS=()` turns it off.

### Changed

- The menu's preview is now shown from the start (it used to follow a `hidden` default from your fzf
  options).

### Fixed

- `FZX_TRACE=start` no longer replaces an event binding a module appends to (it dropped the menu's
  initial load); trace callbacks are now appended to the event's bindings.

## [0.3.0] - 2026-10-24

### Added

- `float` placement: fzx runs in a floating tmux pane (`tmux new-pane`, which needs a tmux that has it).
  Start there with `--float[=OPTS]`; OPTS use fzf's `--popup` syntax, and the default is
  `FZX_FLOAT_OPTS` (`center,80%`).
- `FZF_TMUX` / `FZF_TMUX_OPTS` (the variables fzf's shell integration reads) now choose where a new
  fzx run starts inside tmux: `-p` gives a popup, `-d` / `-u` / `-l` / `-r` a split, and anything else
  a popup. A `--popup`, `--split` or `--float` flag overrides them.

### Changed

- The placement key is now ctrl-^ (it was ctrl-space). The default cycle is inline, split, popup,
  float.

## [0.2.0] - 2026-10-24

### Added

- `FZX_RESERVED_KEYS`: keys that modules may not bind. The default list is the scrolling and
  query-editing keys from your fzf options (ctrl-f, ctrl-b, ctrl-u, ctrl-w, ctrl-g, alt-g, ctrl-p,
  ctrl-n, up, down, alt-b, alt-f and the scroll events). A module binding on one of these is skipped,
  and a warning is written to the log.

### Changed

- logs: follow moved from ctrl-f to alt-F, so ctrl-f half-page scrolling works in the logs module.

## [0.1.0] - 2026-10-24

First versioned release, covering everything built so far.

### Added

- Core: `fzx -m <module>` runs fzf with a module's source, preview and actions. A session tree keeps the
  query and cursor of each screen. Modes switch with alt-0 / alt-9, and alt-left goes back to the previous
  screen.
- Esc goes back to the previous screen and quits only at the root (`FZX_KEYS[escape]`). Ctrl-C still aborts.
- Placements: ctrl-space cycles between inline, tmux popup and tmux split.
- Components declared in each module's `components.tsv`: modes, toggles, sort orders (f11 / f12) and
  actions, plus an actions menu (ctrl-\\). The header line comes in minimal, bubble or triangle style.
- The menu: lists modules from their manifests, hides the ones that don't apply here, and shows cached
  summaries.
- Modules: `ps`, `files` (with grep mode), `logs`, `systemd`, `git` (status, log, branches, stash),
  `dirs` (zlua, zoxide, fasd, recent, bookmarks), `recent` (frecent files), `tmux` (sessions, windows,
  panes, pane capture of urls/paths/words/hashes/ips, buffers, and browsers for keys, options, formats,
  styles and hooks) and `youtube` (yt-dlp search with recent searches; play, audio, browser and mp3).
- Layered config: fzx defaults, then the module's `config.sh`, then `~/.config/fzx/config.sh`, then
  per-module user config. `fzx config` shows the resolved result.
- Help and debugging: f1 lists every binding, the free keys and the component rows. f2 shows session
  state. `fzx debug tail`, `attach`, `state` and `send` work over the session's fzf socket.
  `FZX_TRACE` logs fzf events.
- Persist policies, session garbage collection (`fzx gc`), usage statistics (`fzx stats`) and a prompt
  icon with a loading state.
- prettypath icons and colors on file and directory lists (`FZX_PRETTY`).
- Shell integration: zsh widgets (`shell/fzx.zsh`), `g` / `gg` / `v` through `fzx jump`, and
  `just install`.
- shellcheck linting (`just lint`) and a CI workflow.

[Unreleased]: https://github.com/njhoffman/fzx/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/njhoffman/fzx/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/njhoffman/fzx/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/njhoffman/fzx/releases/tag/v0.1.0
