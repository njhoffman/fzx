# Changelog

All notable changes to fzx are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
