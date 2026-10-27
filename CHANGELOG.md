# Changelog

All notable changes to fzx are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.33.0] - 2026-10-27

### Added

- The tasks module (`fzx -m tasks`): make targets, just recipes, package.json scripts, Taskfile tasks,
  cargo aliases and pdm, poe and hatch scripts of every repository, named `project:task`. Enter runs the
  task in its repository, alt-enter asks for arguments first, ctrl-t picks tasks into the default view
  (which also lists the tasks of the repository you are in), and the projects mode chooses the
  repositories the repos mode lists. The scan is cached for `FZX_TASKS_TTL` (1h) and refreshed in the
  background.

### Changed

- `just test` runs the test files in parallel (`bats --jobs`, one per CPU) when GNU parallel is
  installed; `FZX_TEST_JOBS=1` runs them one after another.

## [0.32.0] - 2026-10-27

### Added

- The network module (`fzx -m network`): listening ports and established connections with their
  processes, interfaces, routes, wifi networks and mDNS services. ctrl-x stops the process on a port
  (through sudo when it is not yours), ctrl-o lists its open files, alt-c and alt-d connect and disconnect
  wifi, alt-s scans again, alt-o opens web services; alt-u runs ss and lsof as root when sudo is cached.

## [0.31.0] - 2026-10-27

### Added

- `FZX_APPLICABLE_TIMEOUT` (default 2s): a module whose menu entries take longer than this to check is
  left out of that menu listing and logged, so one slow check (a hung docker daemon) cannot hold up the
  menu. Each module's listing time is logged at the debug level.

### Changed

- The menu lists every module at once instead of one after another, and checks that cost a request
  (docker's daemon, gh's keyring token, git's work tree, git's and capture's summary keys) run once per
  module instead of once per entry: opening the menu takes about half the time it did.
- `<module>::summary_key` takes no target: it is asked once per module and listing.

## [0.30.0] - 2026-10-27

### Added

- The capture menu entries have summaries: how many lines, URLs, paths, words, hashes and addresses the
  active pane holds.
- A module's manifest can define `<module>::summary_key`: more state to key its menu summaries on than
  the directory.

### Fixed

- git's menu summaries no longer stay stale for up to five minutes after a commit, stage, branch switch,
  fetch or stash: they are keyed on HEAD and on when the index and refs changed. (Edits not yet staged
  still wait for `FZX_SUMMARY_TTL`.)

## [0.29.0] - 2026-10-27

### Added

- Several keys for one action: `FZX_KEYS` values and component row keys take a comma list
  (`FZX_KEYS[back]="alt-left,ctrl-bspace"`); each key shows in f1 and is checked on its own.
- f1 pressed again shows the keys as a grid: a row per modifier (ctrl, alt, alt-shift, shift, ctrl-alt,
  ctrl-shift and none), every key fzf accepts with it, colored by who binds it (this screen, fzx, your
  options, fzf) and dim when free. A third press brings the list back. (fzf has no shift-f1.)
- `FZX_KEY_STYLE`: keys shown as `full` (fzf's names, the default), `short` (`^X`, `M-left`) or `glyph`
  (`⌃X`, `⌥←`) in f1, the grid and the menu preview.
- f2 lists every `FZX_*` parameter with the module's config loaded, arrays one element per row.

### Changed

- f1 opens with the components (modes, toggles, sort orders, actions), then the keys.
- In the actions menu, its own key (`ctrl-\`) goes back to the screen it was opened from.

## [0.28.0] - 2026-10-27

### Added

- Sort orders (f11/f12) in more modules: docker containers (state, name) and images (created, size, name);
  tmux sessions, windows and panes (tmux's order, last active, name); systemd (name, or failed and running
  first); recent (the tool's ranking, or path); dirs bookmarks (name, path); logs files (newest, largest,
  name); git branches (last commit, name); github mine and starred (as listed, most stars, name).
- The column a list is sorted by is underlined (`FZX_COLORS[sorted]`, added to the column's own color),
  header included: ps, docker, tmux, systemd, recent, dirs, logs, git branches, github, repos and history.
  The query still matches the whole line.
- tmux sessions, windows and panes show how long ago they were last active; logs files show their size.
- A sort row's description can be scoped by mode, as actions are (`branches: last commit first`): the
  order then exists only in those modes, and a mode without one has no sort.

### Changed

- ps's tree mode has no sort orders: f11/f12 do nothing there and the footer shows none.

## [0.27.0] - 2026-10-27

### Added

- `fzx --version` (`-V`) prints the version; the f1 help page shows it in its first line.
- The menu's preview is styled: the entry's icon and target, its description and summary, the module's
  modes (the entry's marked), toggles, sort orders and actions with their keys (actions described for
  the entry's mode), how often the module was opened and how its runs ended, then the command it runs.
- A mode row in components.tsv can be flagged `nopersist`: under a `FZX_PERSIST=cache:<ttl>` module its
  data stays with the session.

### Fixed

- `files:grep` no longer opens with the previous search's hits under an empty prompt: its rows follow the
  query, so the mode is flagged `nopersist` and is no longer written to the 5-minute files cache.
- `fzx --version` used to fall through to fzf and fail.

## [0.26.0] - 2026-10-27

### Added

- zsh completion: `fzx completion zsh` prints a `#compdef fzx` function for the commands, the options,
  `-m module[:mode]` with each module's and mode's description, and session ids. It asks the new
  `fzx _complete targets|modules|sessions` while completing, so new modules need no new script.
- Repository links (lib/links.sh): `FZX_REPOS_LINKS_DIR` (default `~/git` when it exists) holds a link per
  ghq repository named after it. The repos module's new `links` action and the shell's
  `repos [--dry-run]` bring it up to date (dead links removed, shared names reported); every clone fzx
  makes adds its link.
- zsh (`shell/fzx.zsh`): `clone REPO...` clones with ghq (anything ghq takes; your GitHub repositories over
  ssh, `FZX_GITHUB_CLONE_SSH`) and links; `repos --clone-missing` first clones your GitHub repositories
  that are not here yet. `FZX_ZSH_NO_REPOS=1` leaves both out. These replace ~/.shell's repoman.
- github: repository rows mark the ones cloned here; the `missing` toggle (alt-5) keeps the others.
  alt-c clones your own repositories over ssh and links every clone.

## [0.25.0] - 2026-10-27

### Added

- github: `mine` (your repositories, or `--owner NAME`'s, last pushed first) and `starred` modes, which fzf
  filters as you type. Toggles keep private or public repositories, sources or forks only, in every
  repository list (alt-1 to alt-4).
- github actions: alt-s stars the selected repositories (unstars them in `starred`), alt-F forks one to
  your account (asks first), alt-e opens a repository's settings page.
- github: alt-p searches the code of the repository under the cursor (in code mode it narrows the current
  search to that repository); ctrl-t filters a search's results with fzf instead of searching, and back.
- github: GitHub's emoji shortcodes in descriptions show as the emoji.
- The menu's github entries: GitHub's status when it is not fine, this repository's open PRs and issues,
  unread notifications and the searches left; how many repositories and stars you have.
- The debug view (f2) shows a module's own section when its preview.sh defines `<module>::debug`; github
  lists every API rate limit there.

### Changed

- github: a code query of qualifiers alone (such as alt-p's `repo:o/r`) asks for words to look for instead
  of spending one of the ten code searches a minute on a list of arbitrary files.

### Fixed

- github: GitHub's search sometimes answers an empty list for a query that has results; an empty answer
  is no longer kept for an hour.

## [0.24.0] - 2026-10-27

### Added

- github module (`fzx -m github[:code]`), through gh: repository and code search, where enter runs the
  query (GitHub qualifiers such as `language:go stars:>100` work) and an empty query lists the mode's recent
  searches. Previews show a repository's details and README (glow when installed), a code hit's matching
  fragments with the matches highlighted and then the whole file. ctrl-o browses a repository's files
  (`github:tree`, at the commit a code hit came from). Actions: open in the browser, clone with ghq,
  fetch files and directories, open a read-only copy in $EDITOR, open the search on github.com, copy.
  Searches are cached per query for an hour, trees and file contents by their sha. In the menu: the
  searches left this minute.
- zsh (`shell/fzx.zsh`): `ghs [query]` and `ghsc [query]` open the repository and code searches;
  `ghfetch URL... [--dest DIR]` downloads a file, or a directory under its own name, from a github.com or
  raw.githubusercontent.com URL (a branch with slashes works), and clones a repository's URL with ghq.
  `FZX_ZSH_NO_GITHUB=1` leaves them out. This replaces ~/.shell's gitman.
- Icons for stars, forks, issues, archived and repositories (lib/icons.sh).

## [0.23.0] - 2026-10-27

### Added

- Every module has an icon in the menu, each in its own color (`FZX_COLORS[<module>_icon]`). A mode that
  opens a different list can have its own icon and color (`FZX_ICON_MODES[mode]`,
  `FZX_COLORS[<module>_icon_<mode>]`): files, files:dirs and files:grep now differ.
- Menu summaries for tmux (sessions and how many are attached, windows across sessions, panes across
  windows, buffers, key bindings across tables), keybindings (zsh from the saved dump, tmux, fzf yours and
  the defaults), recent (every mode), man (commands, pages, tldr pages), todos (open, urgent and overdue
  items, across files in todos:all), logs (log files), files:grep (the files a search reads and their
  size) and dirs:bookmarks.

### Fixed

- The todos menu entry finds TODO.md the way the module does (the nearest one up to the repository's top),
  not only at the top.

## [0.22.0] - 2026-10-27

### Changed

- Sorting is on in every module: actions, capture, colors, dirs, docker, git, logs, recent (g, v), repos,
  tmux, todos and youtube turned it off to keep their order (frecency, recency, priority, the screen).
  They now sort with `--tiebreak=index`, so the best matches rise to the top and equal matches keep that
  order; with no query the list shows as before. Only ps's tree mode keeps sorting off.

## [0.21.0] - 2026-10-27

### Added

- keybindings module (`fzx -m keybindings[:tmux|:fzf]`): zsh bindings in every keymap with readable keys
  (`ctrl-x ctrl-e`, `alt-f`, `up`), zle's description of each standard widget (from zshzle(1), cached)
  and, for your own widgets, the comment above their function; tmux bindings through the tmux module;
  fzf bindings, yours first. The zsh preview lists every key bound to the widget and what the same key
  does in each keymap. Enter prints `bindkey -M` lines, ready for a zshrc.
- shell/fzx.zsh dumps the shell's bindings for it (`fzx-keys-dump-file`) at the first prompt and whenever
  an fzx widget runs, in the background; `FZX_ZSH_NO_KEYS_DUMP=1` turns that off. Without a dump younger
  than `FZX_KEYBINDINGS_ZSH_TTL` (a day) the module asks an interactive zsh (`zsh -ic`, about a second).

## [0.20.1] - 2026-10-27

### Fixed

- The menu tests found the fixture's entries by position, which every real module named before "counter"
  (colors) broke; they find them by id now.

## [0.20.0] - 2026-10-27

### Added

- colors module (`fzx -m colors[:names|:fzx]`): the 256-color palette with xterm names, hex and rgb; X11
  color names in true color with the nearest 256 color; fzx's own `FZX_COLORS` from every config layer,
  by module. The preview shows a swatch, sample text on the terminal's, a dark and a light background,
  and the codes. alt-h copies hex values, alt-s SGR parameters (as `FZX_COLORS` takes them), alt-e
  escape sequences.

## [0.19.0] - 2026-10-27

### Added

- man module (`fzx -m man[:all|:tldr]`): man pages of commands (sections in `FZX_MAN_SECTIONS`, 1 and 8 by
  default), every man page, or tldr pages with descriptions from tealdeer's pages (common, then
  `FZX_MAN_TLDR_PLATFORMS`). The preview renders the page at its width through bat; enter opens it in
  the pager, alt-n in nvim. Shorter names are listed first, so the exact name ranks first. Lists are
  cached for a day.

## [0.18.0] - 2026-10-27

### Added

- git destructive verbs, bound only with `FZX_GIT_DESTRUCTIVE=1` (environment or fzx config) and confirmed
  every time: alt-x drop (status: discard unstaged changes, staged ones kept, and delete untracked files;
  branches: force-delete local branches, remote ones are left alone; stash: drop, highest index first);
  alt-U fixup (fold what is staged into the selected commit); alt-Q squash into its parent; alt-W reword;
  alt-E `rebase -i` of the commits after the selected one. History rewrites refuse commits outside HEAD's
  history or followed by merges, and stash local changes around the rebase.

### Changed

- The confirm prompt shows the current mode's part of a mode-scoped description, and only the selection
  (not the module's arguments).

## [0.17.0] - 2026-10-27

### Added

- git write actions, as verbs shared across modes: alt-p `add -p` (status); alt-c also checks out a
  log, reflog or tag entry detached, and in a commit's file list restores the selected files as of that
  commit (files with local changes are skipped); alt-k cherry-picks commits oldest first, or applies a
  stash; alt-R reverts commits newest first, without an editor; alt-B creates a branch at the selection
  and switches to it; alt-z stashes the selected files (untracked included), or pops a stash; alt-i
  appends paths to .gitignore; alt-m commits; alt-M amends, refused once HEAD is on a remote branch
  unless `FZX_GIT_DESTRUCTIVE=1`; alt-F fetches every remote with pruning. ctrl-e also edits a commit's
  files.
- Mode-scoped action descriptions (`MODE[, MODE]: text` parts separated by "; "): the f1 help and the
  actions menu show the current mode's meaning of each key and leave out actions idle in that mode.

## [0.16.0] - 2026-10-27

### Added

- git: tags, reflog (`--rev REF` for a ref's) and worktrees modes, each with a menu entry (tags and
  worktrees only when there are any).
- git: ctrl-o on a log, reflog or stash entry lists the files that commit changed (`git:commit --rev REV`),
  each previewing its own diff, renames against their original name; on a tag it opens the tag's log, on
  a work tree that tree's status.
- git: alt-v switches the status and commit previews between the diff and the blame (colored by age).
- git: ctrl-y copies the selection (paths, hashes, names).
- Mode rows flagged `hidden`: left out of the mode cycle and the footer, opened only by name; a session
  opened in one has that mode alone.

### Changed

- git: `FZX_GIT_DIFF_FILTER` defaults to `auto`, delta at the preview's width when it is installed; set
  it to "" for git's own colors.

## [0.15.0] - 2026-10-27

### Added

- capture module (`fzx -m capture[:urls|paths|words|hashes|ips]`): text out of a tmux pane, the visible
  screen first and newest first, then the whole scrollback nearest first; each row says where it was
  (`vis`, `↑N` lines above the screen, `↓N` below a copy-mode view) and the header the pane and its line
  counts. alt-. / alt-, read the window's next/previous pane; the preview shows the lines around a hit.
  Under fzx the origin pane is read once before fzf starts, so an inline fzf never captures itself.

### Removed

- The tmux module's capture modes, its visible toggle, `--scope` and `FZX_TMUX_LINES`/`FZX_TMUX_SCOPE`;
  its ctrl-o now opens `capture:lines` on the pane under the cursor.

## [0.14.0] - 2026-10-26

### Added

- Icons in the footer: each toggle shows whether it is on or off, the sort its own icon.
- Icons before the labels of the ps preview (pid, parent, user, state, threads, start, elapsed, cpu, mem,
  children), the history preview (last run, status as succeeded or failed, duration, directory, host,
  runs, directories) and the repos preview (path, remote, TODO). `FZX_COLORS[preview_icon]` colors them.

### Changed

- git: tags, commit hashes in `git show` and the parentheses around decorations are no longer yellow
  (`FZX_GIT_COLOR_CONFIG` sets git's colors for the module; the repos preview uses the same).

## [0.13.0] - 2026-10-26

### Added

- Icons in rows (`FZX_ICONS`: `nerd`, the default; `unicode` for terminals without a Nerd Font; `none`):
  the menu shows each module's icon; git status rows an icon for the change (added, modified, deleted,
  renamed, untracked, conflict); repos the branch and the changed/ahead/behind/todo flags; docker
  containers and logs the state (running, paused, stopped, created) and kind (file, unit); history a
  failed icon on commands whose last run failed.
- docker, history, recent and repos have prompt icons like the other modules.

### Fixed

- The menu loads each module's config before its manifest, so entries that depend on settings show:
  `recent:fasd` (next to telescope-frecency's files) never did.

## [0.12.0] - 2026-10-26

### Added

- ps: colored rows, after grc's conf.ps in cool colors: the pid bold purple, the parent pid dim, your user
  blue, other users cyan, root red; %cpu and %mem by load (dim, green, white, red); rss as K/M/G; the state
  by kind (running green, disk wait red, zombie on red); the tty cyan; the command's name bold white after
  its dim directory, options blue, paths light grey, kernel threads cyan, the tree's branches dim.
  `NO_COLOR` turns it off.
- ps: the preview is a labelled summary (pid, parent and its name, user, state spelled out, threads, start
  time, elapsed, cpu, mem, rss, vsz), then the colored command line and the children.

## [0.11.1] - 2026-10-26

### Changed

- Cool colors over warm ones: yellow, wheat and tan become shades of white (todos P2 and due dates, git and
  repos hashes, stash names, long history durations, repos' changed count, docker's paused state, tmux keys
  and scopes, the f1 keycaps); orange and pink become pale cyan and lavender (tmux's changed options,
  docker's merged-log palette). Red stays for errors, failures, overdue items and P1.

## [0.11.0] - 2026-10-26

### Changed

- The frecent and recently visited directories moved from the dirs module to the recent module, beside
  the recent files: `recent:zlua`, `recent:dirs` (zoxide), `recent:fasd-dirs` and `recent:visited` (fasd).
  The menu lists them under recent. The dirs module keeps `dirs:all` (every directory under ~, now its
  default) and `dirs:bookmarks`.
- `g`, `gg` and alt-j go through the recent module's directory modes (z.lua, else zoxide, else fasd), with
  the same behavior. Settings renamed: `FZX_DIRS_ZLUA` and `FZX_DIRS_ZLUA_LUA` are now `FZX_RECENT_ZLUA` and
  `FZX_RECENT_ZLUA_LUA`; `FZX_DIRS_JUMP_MODE` is now `FZX_RECENT_DIRS_JUMP_MODE`, which also takes
  `MODULE:MODE` (`dirs:bookmarks`).
- recent: ctrl-x forgets the selected entries in fasd, zoxide or z.lua; the dirs preview (git branch, then
  the listing) is shared by both modules and gained the path header.
- `v` uses recent's file modes only, whatever the default mode is.

### Fixed

- Menu summaries are cached by what the entry opens instead of its position in the module's manifest, and a
  module without a summary no longer shows an old cached one: after this change `dirs` showed zoxide's
  "known directories" count from its former first entry.

## [0.10.0] - 2026-10-26

### Added

- files: toggles for hidden files (alt-h, on at start), ignored files (alt-i) and following symbolic links
  (alt-l); sorts by path (default) and newest first (f11/f12).
- files: the preview starts with the path and size (a directory's entry count, a link's target), and shows
  images through chafa (`FZX_FILES_IMAGE_FORMAT`: symbols, sixels or kitty).
- files: grep mode falls back to `grep -E` when ripgrep is not installed.
- files: `FZX_FILES_EXCLUDES` leaves tool caches (`.ruff_cache`, `__pycache__`, ...) out of every mode.

### Changed

- files: symbolic links are no longer followed by default. Links are still listed (a link to a directory in
  dirs, to a file in files) and ctrl-o enters a linked directory; alt-l follows them all.
- files: lists come in path order instead of fd's walk order.
- files: the preview goes to the right from 130 columns, and takes 40% under the list below that.
- Directories show prettypath's folder icon and colors (files, dirs and zoxide lists).

### Fixed

- The repository's own `/todo-pop` command still ran todo-fzf to open the editor; it now matches the global
  one (`fzx -m todos --paste`).

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
