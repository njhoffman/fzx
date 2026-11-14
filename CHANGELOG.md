# Changelog

All notable changes to fzx are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.115.0] - 2026-11-14

### Added

- The actions menu says what enter does when it is not a default action: a first `enter` row names the module's
  own enter (todos `--paste`: paste into the pane) or what fzf's accept prints (repos: the repository's path,
  `FZX_ENTER_DESC`), and carries the ⏎ mark.
- An action flag `background`: the action runs in a bg-transform, so the list stays usable, and the footer says
  when it is done; with `reload` the list reloads then.
- An action row may take fzx's reload key with `reload` in its key column (`FZX_KEYS[reload_hard]`, ctrl-r): it
  replaces the plain reload on that screen, listed once in the help.
- A module hook `<module>::start_mode`: a launch that names no mode may start in another.

### Changed

- repos: ctrl-r rescans every repository in the background and reloads when the scan is done (it only re-read
  the last scan before); the rescan action is listed with its key. A rescan during the start's scan waits for it.
- todos: here mode finds the nearest TODO.md through every parent directory up to ~ (it stopped at the
  repository's top, and outside a repository looked in the current directory only), and `fzx -m todos` (alt-i)
  starts in all when there is none. `todos:here` and `--dir` stay in here mode.

## [0.114.4] - 2026-11-14

### Fixed

- Split and float panes fill the pane: fzx passes `--height=100%` there, so a `--height=-1` (or any other height) in
  `FZF_DEFAULT_OPTS_FILE` no longer leaves an empty row under fzf's bottom border. Inline launches keep the user's
  `--height`; popups were never affected.

## [0.114.3] - 2026-11-13

### Changed

- Live searches (files grep and locate, git grep, github, youtube, packages) record each keystroke's reload as a
  `search` stats event, so `fzx stats` and the menu's source times count real loads only.
- files: the rg/fd flags label (alt-a) leads the header, before the path, so a long path no longer hides it.

### Fixed

- files: alt-up and ctrl-o return to a session already above in the tree for that directory instead of opening a
  new one each time, so walking up and down no longer stacks sessions.

## [0.114.2] - 2026-11-13

### Changed

- The tmux formats and status screens expand every template in one tmux call instead of one call each (about
  240ms down to 160ms here).

### Fixed

- An empty `NO_COLOR` no longer turns color off: like no-color.org asks, only a non-empty one does, everywhere in
  fzx and for the tools it runs (`bin/fzx` unsets an empty one).
- firewall: with ufw off, the header says "rules added, not in effect" only when some are.
- `fzx gc` no longer loses stats rows written while it prunes the stats file.
- tmux formats: a template ending in `;` keeps it in the rendered sample (tmux read it as a command separator).

## [0.114.1] - 2026-11-13

### Changed

- docs/design.md says what the `off` flag does to the copy built-ins: the row leaves the help and the actions menu,
  while ctrl-y and alt-y stay bound in every session, so a yank key from FZF_DEFAULT_OPTS never reaches one.
- `just lint` runs shellcheck in parallel batches, one per core, instead of once over all 267 files (about two
  minutes on one core).
- `just test-live` also checks the fzf behaviour popups rely on: `become()` inside a `--popup` runs in the caller's
  terminal. Run it after every fzf upgrade.
- CI installs prettypath (pinned, `PRETTYPATH_VERSION`), so the tests against the real one run there too.

### Fixed

- The tests no longer fail on a loaded machine: the menu's applicability and summary timeouts are 20s in the tests
  (fixture modules dropped out of the list at 2s), and the elapsed-time checks have room while still well under
  the delays they guard against.
- test/tmux.bats ends its tmux servers by pid when `kill-server` leaves one running, and a run kills servers an
  interrupted earlier run left behind (their test directory gone).

## [0.114.0] - 2026-11-13

### Added

- kdeconnect: enter on an SMS conversation opens it as a chat. Its latest messages (`FZX_KDECONNECT_CHAT_MESSAGES`, 50)
  are listed newest first, next to the prompt, and what you type is the reply: enter shows "send to NAME: TEXT?" in the
  header, enter again sends it (group conversations too), typing again cancels. New messages, yours included, appear on
  their own while the chat is open (`FZX_KDECONNECT_CHAT_LIVE=0` turns that off; ctrl-r reloads). Esc returns to the list.
  The text goes to the phone without passing through a command line, a file or the log.

### Fixed

- A conversation's preview no longer takes 6 seconds with phones that never say a conversation is loaded: it ends once
  as many messages as asked for came, or a second after the last one.
- The tests no longer copy to the desktop's clipboard: a test that copied left xclip running, which kept the
  kdeconnect test file from ending until something else took the clipboard.

## [0.113.1] - 2026-11-13

### Fixed

- A list cut short (fzf quitting while it loads, or `head` in a pipe) no longer adds "Broken pipe" from the emoji
  filter to the output where SIGPIPE is ignored, as in CI: 0.113.0's history list failed its header-row test there.

## [0.113.0] - 2026-11-13

### Fixed

- Rows and previews with some emoji no longer push the border out of line. fzf and tmux (with
  `variation-selector-always-wide on`) count a heart with its emoji selector, a skin-toned or joined emoji and a
  keycap as different widths, so the row ran a cell or two long or short. kdeconnect (sms and notifications, lists
  and previews), browser (history, bookmarks and tabs; the title in the preview) and history drop those parts
  (`fzx::glyphs_plain`): the heart draws as text, skin tones go, a family shows its members. Ids, URLs and copied
  titles keep them. `FZX_GLYPHS_PLAIN=0` turns it off.

## [0.112.0] - 2026-11-13

### Changed

- Esc closes fzx about four times faster (about 200ms down to 35-50ms here). fzf waits after Esc for the rest of an alt
  key or arrow sequence: fzx now runs fzf with `ESCDELAY=25` instead of fzf's 100ms (`FZX_ESCDELAY`, new; an
  `ESCDELAY` you set is kept, and `FZX_ESCDELAY=""` leaves it alone). On the first screen of a session that is not
  kept, Esc quits directly instead of starting a callback that could only print `abort`.
- Every callback starts a little faster: bin/fzx no longer runs `readlink` and `dirname` when fzf calls it by its own
  path, and the stats row of a callback reads the mode without loading the module's components table.

## [0.111.0] - 2026-11-11

### Removed

- Support for prettypath older than 0.2.0. Such a prettypath now counts as not installed: the files, dirs,
  recent and github lists keep their plain displays, and the log says why once. fzx no longer adds the
  trailing slash, cuts the base directory or joins displays back by path itself; prettypath's `--dirs`,
  `--base` and `--field` do that.

### Changed

- The prettypath tests also run against the installed prettypath (when it is 0.2.0 or later), so a change in
  prettypath that breaks the displays shows up here. docs/design.md points at prettypath's `make bench` for
  its speed instead of a figure measured before 0.1.0.

## [0.110.3] - 2026-11-10

### Fixed

- The test suite passes where there is no display and no tmux server, as in CI: the copy test pins the display it
  stubs xclip for, and the key test gives the capture module a pane. CI installs just from its release (1.59.0):
  Ubuntu's 1.21 cannot read the `[doc]` attributes the tasks tests use, and those tests now skip on a just
  older than 1.37.

## [0.110.2] - 2026-11-10

### Removed

- `FZX_SPLIT_PANE`, which split panes exported but nothing read.

## [0.110.1] - 2026-11-10

### Fixed

- Leaving the menu while its summaries were still being computed (esc, back, a goto) took seconds in a tmux
  split, with the pane blank and keys echoed: the summary refresh kept running beside the next screen. It now
  runs in a process group of its own, without the terminal, and leaving the menu stops it.
- Menu entries without a mode of a module that gives its modes icons (music, github) logged "bad array
  subscript" and lost their icon.

## [0.110.0] - 2026-11-10

### Added

- files: alt-a in files, dirs and grep opens a screen for the fd or rg flags to add: type them (`-t py -w`,
  `-e md -d 2`), the preview checks each as you type and enter applies them, esc leaves them as they were.
  Only flags that keep the rows readable are allowed (the screen lists them). They last for the session,
  through into, up, alt-r and mode changes, and the header shows them.

### Changed

- The cache key of a view can carry a module's own part (`meta/view`), so rows cached under other settings
  are never served for it.

## [0.109.0] - 2026-11-10

### Added

- git: `fzx -m git --dotfiles` opens the dotbare repository (`FZX_GIT_DOTBARE_DIR`, default `$DOTBARE_DIR` or
  ~/.cfg, with its work tree `FZX_GIT_DOTBARE_TREE`, default `$DOTBARE_TREE` or ~) from any directory, in every
  mode; the menu lists it as "Dotfiles" wherever the repository exists. Status shows tracked files only, and
  clean is off there, since the work tree is the home directory.

## [0.108.6] - 2026-11-10

### Fixed

- Menu summaries say "1 buffer", "1 entry", "1 stash" and so on for a count of one, instead of "1 buffers"; the
  manifests share `fzx::plural` (and `plural()` for their awk summaries, from `FZX_AWK_PLURAL`).
- docs/design.md: the table under "Reloading and navigation" lost a stale header row that broke its rendering.

## [0.108.5] - 2026-11-10

### Fixed

- github: directories in a repository's file list get the folder icon and colors; they always showed the plain
  display, because their trailing "/" kept them from matching prettypath's output.

### Changed

- dirs, recent and github decorate their path column with prettypath in one pass (prettypath 0.2.0 and later:
  `--field`) instead of decorating the paths separately and joining the results back by path.

## [0.108.4] - 2026-11-10

### Changed

- With prettypath 0.2.0 or later, the files, dirs and recent displays let prettypath drop the base directory
  (`--base`) and mark zoxide's directories (`--dirs`) instead of fixing up its output with awk and sed. Older
  prettypath versions get the same displays as before.

## [0.108.3] - 2026-11-10

### Changed

- fzx tells whether the installed prettypath handles every path by its `--version` (0.1.0 or later) instead of
  running a test path through it. It is still checked once per prettypath binary; a build too old to have
  `--version`, or a dev build, counts as an old one, as before.

## [0.108.2] - 2026-11-10

### Changed

- The files, dirs and jump displays no longer pass `--stat_file=false` to prettypath: prettypath 0.1.0 stats a file
  only when the format shows its size or dates, which these displays do not. With an older prettypath installed, the
  lists build about three times slower; update it with `luarocks make` in its repo.

## [0.108.1] - 2026-11-05

### Fixed

- An I or O no longer lands in fzf's query when you switch tmux panes with fzf open from any zsh widget, such as
  fzf-tab's completion list. With `shell/fzx.zsh` sourced, the `fzf` function turns the shell's focus reporting off
  around fzf in a widget and back on after it, as fzx's own widgets already did. `FZX_ZSH_NO_FZF=1` opts out of this
  along with the rest of that function.

## [0.108.0] - 2026-11-03

### Added

- kdeconnect: `fzx -m kdeconnect:sms` lists your SMS conversations, newest first or by name, with contacts' names, an
  unread mark and the last message; the preview shows the latest messages, newest first. It only reads, messages are held
  in memory and kept nowhere, and the phone asked for its threads once per list. `FZX_KDECONNECT_SMS_MESSAGES`,
  `FZX_KDECONNECT_SMS_WAIT`.

### Fixed

- kdeconnect: notification titles and message text can no longer reach `fzx.log` through a callback's arguments (the new
  `FZX_LOG_ARGS`, off for this module).
- `fzx --help` now finds the terminal's width by itself, so descriptions really wrap under their column: 0.105.1 only did so
  with `COLUMNS` set. Its green is now a dimmer blue-green.

## [0.107.1] - 2026-11-03

### Fixed

- Prompts inside fzx now show, and what you type at them stays out of `fzx.log`: docker's typed commands and run
  options, firewall rules, dirs bookmarks, music's playlist name and tag edits, task arguments and git's questions
  drew their prompt and echoed typing into the log instead of on screen. Errors still go to the log.

## [0.107.0] - 2026-11-03

### Added

- kdeconnect module: `fzx -m kdeconnect` lists KDE Connect devices, connected first, with their battery; the preview
  adds the certificate's fingerprint and plugins. Ping, ring, send the clipboard, share a file, URL or text, send
  keystrokes, send an SMS (shown and confirmed first), lock and unlock (confirmed), pair and unpair, and look for
  devices again. `fzx -m kdeconnect:notifications` lists the notifications on connected devices, read fresh and kept
  nowhere, and dismisses them; `fzx -m kdeconnect:commands` runs the commands a device offers. A device that is away,
  or lacks the plugin an action needs, is named. What you type for an SMS, text or keys goes in no history file.

## [0.106.0] - 2026-11-03

### Added

- aws: ElastiCache clusters (`fzx -m aws:cache`), and from the menu EBS volumes, VPCs, subnets, security groups, and
  RDS and ElastiCache subnet groups (`aws:volumes`, `aws:vpcs`, `aws:subnets`, `aws:sgs`, `aws:db-subnets`,
  `aws:cache-subnets`), each with a preview, alt-i and alt-O.
- aws: a profile picker (`fzx -m aws:profiles`): the preview shows who a profile signs in as, and alt-u uses it for
  every list from then on, over any keys in the environment. aws-vault's profiles are listed when it is installed
  (`FZX_AWS_VAULT=off` hides them), run through `aws-vault exec`, and alt-L opens one in the console.
- aws: start (alt-s), stop (ctrl-x) and reboot (alt-R) EC2 instances, each confirmed first. These are the module's
  only changes to AWS: nothing terminates or deletes.

### Fixed

- aws: console output and log events no longer clear the screen or move the cursor: a boot's firmware output does.

## [0.105.1] - 2026-11-03

### Changed

- `fzx --help` is easier to read: sections in cool colors on a terminal (`NO_COLOR` turns them off), what to fill in
  marked, each section's descriptions in one column and every `fzx debug` subcommand on its own row. It fits the
  terminal, or `$COLUMNS`: descriptions wrap inside their column, and an entry too wide for it gets a line of its own.

## [0.105.0] - 2026-11-03

### Added

- aws: ECS clusters (`fzx -m aws:ecs`: counts, with the services in the preview), EKS clusters (`aws:eks`: version and
  endpoint, with the node groups in the preview) and RDS instances (`aws:rds`: available first or by name, the
  preview without a request). Read-only like the rest of the module; alt-O and alt-i work on all of them.

### Changed

- aws: moving back to a log group is immediate: what its preview asked AWS is kept in the session for
  `FZX_AWS_PREVIEW_TTL` seconds (60; 0 keeps nothing), as are ECS services and EKS node groups. ctrl-r clears it.

## [0.104.0] - 2026-11-03

### Added

- aws module, read-only, with whatever credentials and Region the AWS CLI resolves: `fzx -m aws` lists EC2
  instances (running first, toggle for running only, by state or name) and `fzx -m aws:logs` CloudWatch log groups
  (by name or stored size). An instance's preview comes from the row, with no request; a log group's shows the
  latest events of its newest stream. ctrl-l shows an instance's console output or follows log groups, several
  merged; alt-i the JSON; alt-O the console page. An empty list names the Region, and a failed read shows the
  error, with `aws login` when the credentials are what failed.

## [0.103.0] - 2026-11-03

### Added

- browser:tabs lists what is open in Firefox and the Chromium family, by window, read from the session files they
  keep on disk: no debug port, no dependency beyond python3. Enter opens the URL as a new tab, since nothing
  outside the browser can switch to a tab. Chrome's format is undocumented: if a browser update changes it, that
  profile shows a row saying so.

## [0.102.0] - 2026-11-03

### Added

- git:grep searches tracked files as you type with `git grep`, over the work tree or a commit (`--rev`); enter
  prints `path:line`.
- git:clean lists what `git clean -d` would remove, with a preview (toggle ignored adds ignored files); alt-x
  removes the selected ones after a question naming them.
- git log and reflog: alt-X resets the branch to the selected commit, asking soft or mixed; hard needs
  `FZX_GIT_DESTRUCTIVE=1` and a second answer.

## [0.101.0] - 2026-11-03

### Added

- dirs: alt-m bookmarks the selected directories, asking each a name, and alt-x removes bookmarks. They live in
  `$FZX_STATE_DIR/dirs/bookmarks`, alongside `FZX_DIRS_BOOKMARKS` from config, and the bookmarks mode is always
  offered.

## [0.100.0] - 2026-11-03

### Added

- applications: alt-a lists an entry's own actions (New Window, New Private Window, ...); enter runs the action's
  Exec line, with field codes removed or filled in, and alt-left comes back.

### Changed

- applications hides what the desktop entry spec hides: a TryExec that is not installed, and OnlyShowIn or
  NotShowIn against `$XDG_CURRENT_DESKTOP`. The hidden toggle lists them, dim.

## [0.99.2] - 2026-11-03

### Changed

- ctrl-y copies what a row is called instead of an internal id: a docker container's or network's name and an
  image's reference, a tmux session's name and a window's or pane's target (`main:1.0`), and the menu entry's
  target (`ps:all`) rather than its icon and label.

## [0.99.1] - 2026-11-03

### Fixed

- ctrl-y reports in the footer in every module: the built-in copy had no key, so in docker, files, ps, tmux and 11
  others it reached the ctrl-y in the user's fzfrc and its notify-send. The menu's ctrl-y and alt-y report there too.

## [0.99.0] - 2026-11-03

### Changed

- alt-y copies the whole line as it shows in every module (the built-in `copy-line`), without the hidden fields.
  What applications, browser, fonts and shell had on alt-y moves to alt-Y.

### Fixed

- An I or O no longer lands in the query when you switch tmux panes with fzx open from a zsh widget (ctrl-r, the
  menu, ...): the widgets turn the shell's focus reporting off while fzx runs, and back on after it.

## [0.98.0] - 2026-11-03

### Changed

- ctrl-w wraps the list's rows (`FZX_KEYS[wrap]`) and alt-w the preview (`FZX_KEYS[preview_wrap]`), everywhere in
  fzx. ctrl-w no longer deletes a word in the query inside fzx; alt-backspace still does.

### Fixed

- The sort keys (ctrl-\_, f11, f12) do nothing in a module or mode with nothing to switch to, instead of falling
  through to fzf's own binding, which wrapped the list.

## [0.97.0] - 2026-11-03

### Added

- `--freeze-left=1` by default in every module (`FZX_FREEZE_LEFT`; 0 for none): the name column stays on
  screen while a long row scrolls to a match. fzx splits each row's display where the frozen part ends
  (`FZX_FREEZE_COL`, `FZX_FREEZE_COLS[mode]`: `gap`, `gap2`, `word`, a column or `none`), with the rest as a
  new last field, so no field a binding reads moves. The menu freezes the icon and entry, files the icon.

### Changed

- files, dirs and recent keep the right end of a long path in view (`--keep-right`), so the name shows.

## [0.96.0] - 2026-11-03

### Changed

- shell:params shows a parameter's type as an icon before its name (`FZX_COLORS[shell_param_icon]`; the word
  with icons off), instead of a column after it.
- The shell:params preview lists the type, the attributes in words (exported, tied, special, readonly, hidden,
  unique, ...), what a tied parameter is tied to, the size and where the value came from, then the value as a
  zsh assignment, highlighted.

## [0.95.0] - 2026-11-03

### Changed

- The footer shows only the toggles the current mode has, by the mode names in each toggle's description; the
  key of any other does nothing there, and it no longer invalidates that mode's cache. files, github, ps,
  network and tmux toggles now name their modes.

## [0.94.0] - 2026-11-03

### Added

- Menu status for the entries that had none: every glyphs and colors entry, tmux's commands, options,
  variables, styles, formats, status and hooks, cron's default entry and systemd's failed units.

### Changed

- packages:available and packages:upgradable read apt's lists for their status when the cache is missing, and
  so fill the cache the modes open from, instead of staying blank until the mode was opened once.
- network:services starts a browse behind the menu when one is due, showing "browsing the network" until its
  count arrives at the next listing. The count leaves out records without a port, as the list does.

## [0.93.0] - 2026-11-03

### Added

- alt-o goes to the main menu from any module (`FZX_KEYS[menu]`): the menu in the path, however deep, or a new
  one under this screen, so alt-left comes back.
- The border title uses a Nerd Font arrow between screens (else `>`), in white where it came from and bold
  bright white on the current screen: `FZX_TITLE_COLOR` and `FZX_TITLE_CURRENT_COLOR`, or `FZX_COLORS[title]`
  and `[title_current]`.
- fonts has an icon.

### Changed

- alt-o moves to alt-O where modules had it: open in browser, capture, claude, fonts, github, network and
  youtube, the open files in ps, the files module in repos.
- The menu opens in its list mode; groups is the second mode.

### Fixed

- A long menu description no longer runs into the status column: it is cut to fit, and the two over the width
  (files:locate, sessions) are shorter.

## [0.92.0] - 2026-11-03

### Changed

- Header rows are the default (`FZX_SORTED_SHOW=header`): every sortable module names its columns, the
  sorted one marked with its arrow, and the rows are no longer underlined. `FZX_SORTED_SHOW=rows` brings
  back the underlined column.
- The header row's columns default to `#007e95` (`FZX_HEADER_COLUMN_COLOR`) rather than fzf's header
  color, and the sorted one to bold and underlined `#00d7ff` (`FZX_SORTED_HEADER_STYLE`).

## [0.91.0] - 2026-11-03

### Added

- `FZX_SORTED_SHOW=header` (or `both`): every module that sorts by a column (ps, network, docker, tmux,
  systemd, recent, dirs, logs, git, github, repos, history, claude, cron, browser, packages) shows a header
  row naming its columns, the sorted one marked with an arrow for its direction; with `header` the rows stay
  plain. `rows`, the default, keeps the marking in the rows as before.
- Header row settings: `FZX_HEADER_COLUMN_COLOR` (the other columns; empty keeps fzf's header color),
  `FZX_SORTED_HEADER_STYLE` (default bold) and `FZX_SORTED_HEADER_COLOR` (default `#00d7ff`) for the sorted
  column, `FZX_SORTED_ARROWS` (default `↑ ↓`, empty for none); `FZX_COLORS[header_column]` and
  `[header_sorted]` override them.
- Sort rows take a `desc` flag (the arrow points down); the built-in modules set it where they sort the
  largest or newest first.

### Changed

- ps's and network's header rows use fzf's header color instead of a fixed gray.
- Switching between a mode with a header row and one without restarts fzf.
- The git, network, packages, systemd and tmux sources read the config layers when run on their own, as the
  other modules' sources do.

## [0.90.0] - 2026-11-03

### Added

- shell:completions: every zsh completion binding from zsh-complete, one row per command you have (alt-4:
  all of them) with its provider, function and file; the preview shows where it came from (upstream,
  revision) and the completion code. The list is kept a day, since zsh-complete takes a while to make it:
  alt-R asks again, alt-i shows `zsh-complete status` for the command, ctrl-e edits the file.

## [0.89.0] - 2026-11-03

### Added

- todos: the all mode also lists the TODO.md files your dotbare repository tracks (~/.config/tmux,
  ~/.config/i3 ...) and those of git repositories directly under ~ such as ~/.shell, which ghq does not
  know (`FZX_TODOS_DOTBARE_DIR`, `FZX_TODOS_HOME_REPOS`). ctrl-r rescans, as before.

## [0.88.0] - 2026-11-03

### Added

- bluetooth: alt-s in the all mode is now a toggle that keeps a scan running, so devices show up in the
  list as they are found; it stops when you turn it off, leave the mode or close fzx.

### Fixed

- bluetooth: once a scan had found devices with manufacturer data (common for lamps, sensors and speakers),
  the list showed "no bluetooth controller", since busctl cannot write that data as JSON. Its text form is
  read instead.
- bluetooth: a device name with a tab in it no longer breaks the list's columns.

### Removed

- bluetooth: the blocking scan action and `FZX_BLUETOOTH_SCAN_SECONDS` (the scan toggle replaces them;
  `FZX_BLUETOOTH_SCAN_RUN` sets how long each scan client runs before the next starts).

## [0.87.0] - 2026-11-03

### Added

- cron: with a cached sudo, the all and system modes list every other user's crontab too; ctrl-e edits one
  with `sudo crontab -u`.
- cron: alt-d disables and enables system entries and anacron jobs (the line commented out) and run-parts
  scripts (made non-executable), through a cached sudo; disabled system entries stay listed.
- cron: alt-enter runs system entries, anacron jobs and scripts too, as their user through sudo.
- cron: `CRON_TZ=` lines put the next runs in that zone where the cron daemon honors it (cronie); on
  Debian's cron, which ignores it, the preview says so.

### Changed

- cron: run-now runs your own entries as cron would as well: in your home with only cron's environment
  (HOME, LOGNAME, SHELL, PATH=/usr/bin:/bin, then the crontab's variables), not your shell's.

## [0.86.0] - 2026-11-03

### Added

- firewall: alt-n adds a rule you type (`allow 8080/tcp from 192.168.1.0/24`, with readline and the earlier
  rules on up and down), checked with `ufw --dry-run` before it is applied; alt-I inserts one above the
  focused rule.

### Changed

- The prompt with a history behind docker's alt-E moved into fzx itself, so modules share it.

## [0.85.0] - 2026-11-03

### Added

- browser module: history and bookmarks of every Chrome, Chromium, Brave, Vivaldi and Firefox profile in one
  list (toggles per browser; history newest or most visited first). Enter opens the URLs in the browser and
  profile they came from and closes, ctrl-o opens them and stays, alt-o uses xdg-open. The databases are
  copied first, so a running browser does not get in the way.
- applications module: desktop entries by name with their icon in the preview; enter launches the selection
  detached (gtk-launch) and closes, so `fzx -m applications --popup` bound in the window manager works as a
  launcher. alt-h lists hidden entries too, alt-e edits the desktop file.
- fonts module: fontconfig's families with a sample drawn in each (ImageMagick and chafa), their styles and
  files; alt-m lists monospace families only.

## [0.84.0] - 2026-11-03

### Changed

- Previews no longer wrap long lines: no module asks for wrapping any more, so your fzf setting applies (off
  by default) and your `toggle-preview-wrap` key turns it on.
- alt-w is reserved for that toggle (`FZX_RESERVED_KEYS`): github's "open the search on github.com" and
  repos' "open the remote in the browser" moved from alt-w to alt-W.

## [0.83.1] - 2026-11-03

### Changed

- TODO.md keeps finished items ticked in their section until the whole section is done, then moves the
  section to a `## Completed` checklist at the end; only items dropped undone are deleted.

## [0.83.0] - 2026-11-03

### Added

- The module refresh hook can turn the reload-as-you-type binding on or off (`FZX_REFRESH_CHANGE`).

### Changed

- packages: switching to or from the registry search happens in place instead of restarting fzf; typing
  searches the registries there and filters the list elsewhere, and the header follows.

## [0.82.0] - 2026-11-03

### Added

- sessions: a kept session resumed from the list can move into or out of a split or float (ctrl-^) like any
  other: the list's process adopts it and relaunches it there. While it is open, other terminals see it as
  live and open a copy instead of resuming the same session; once you leave, it is kept again.

## [0.81.0] - 2026-11-03

### Added

- Floats follow the window as popups do: when the tmux window is resized, a float is resized and moved in
  place for the new size (and the `FZX_POPUP_LAYOUTS` entry it now falls in), without restarting fzf.

## [0.80.0] - 2026-11-03

### Added

- files: search and replace from grep mode. alt-s opens a replace screen for the grep term: what you type
  is the replacement (`$1` for a capture group), the rows show each matching line as it would become, and
  the preview shows the line before and after with its context. Enter replaces the selected matches, or
  every match when none are selected, after a question; only those lines change, the files keep their
  mode, and each changed file is backed up first. alt-u (in grep and the replace screen) puts back the
  files of the last replacement, leaving any edited since.

## [0.79.0] - 2026-11-03

### Added

- files: a locate mode, when plocate (or locate) is installed: as you type, the paths its database has
  that hold every word of the query, under the directory, or anywhere with the everywhere toggle (alt-e).
  Hidden and excluded paths follow the files mode's rules, paths deleted since the last `updatedb` are left
  out, and the header says how old the database is.

## [0.78.0] - 2026-11-03

### Added

- files: a multiline toggle (alt-m) for grep mode: matches may span lines (`\n` in the term, ripgrep's
  `-U --multiline-dotall`), each line of a match its own row. Without ripgrep it does nothing.

## [0.77.3] - 2026-11-03

### Fixed

- logs: a followed preview kept running after its pane or popup was closed under fzf (fzf runs previews in a
  process group of their own, so the hangup never reached them), following a quiet log forever. The
  preview now asks fzf's socket every `FZX_LOGS_FOLLOW_CHECK` seconds (2) whether its row still has focus
  and stops, tail and colorizer included, once it does not or fzf no longer answers. The follow action
  (alt-F) is left alone.

## [0.77.2] - 2026-11-03

### Changed

- docs/design.md lists the youtube module in its modules table and drops the stale note about modules
  missing preview layouts (every module has them). TODO.md reviewed: new items from resources/ and this
  week's work, the versions module dropped (asdf is no longer installed).

## [0.77.1] - 2026-11-02

### Fixed

- firewall: with ufw off, the rules mode was empty, since `ufw status` lists no rules then. It now lists the
  rules added (`ufw show added`), marked as not in effect, under a header that says so; delete removes them
  by rule, and the apps mode marks the profiles they name.

## [0.77.0] - 2026-11-02

### Added

- A module refresh hook: `<module>::refresh` in a module's module.sh sets the header and turns fzf's search
  on or off when a mode, toggle or sort changes in place, so modes that differ only in those no longer need
  a restart.

### Changed

- github: mine, starred, issues, pull requests and notifications, and the everywhere toggle, switch in place
  instead of restarting fzf: the header follows the view, and typing filters in the lists and is the query
  in the searches. A ctrl-t filter left on in repos or code is dropped on the way back, as the restart did.

## [0.76.0] - 2026-11-02

### Added

- sessions module: every other fzx session tree with its screens, newest first, marked kept (`--keep`,
  its terminal gone) or live (open in another terminal). Enter resumes a kept session in this terminal and
  opens a live one as a copy (same module, mode, arguments, query, toggles and sort; back returns to the
  list), so two terminals never share one session. alt-x deletes kept trees.

## [0.75.0] - 2026-11-02

### Added

- alt-^ (`FZX_KEYS[popup_toggle]`) moves between a popup and the plain terminal only: from a popup back
  inline, from anywhere else (inline, a split, a float) into the first popup of `FZX_PLACEMENTS`. ctrl-^
  keeps the whole cycle. An empty `FZX_KEYS[popup_toggle]` leaves the key unbound.

## [0.74.0] - 2026-11-02

### Added

- firewall module (ufw): the numbered rules and the application profiles, under a header row with ufw's
  state, default policies and logging. ufw answers only root, so the module reads it through a cached
  sudo; without one the header says to run `sudo -v`, and the profiles still list. alt-x deletes rules,
  alt-a and alt-D allow and deny profiles, alt-e and alt-d turn ufw on and off. Each change runs through
  sudo in the foreground, so it can ask for the password.

## [0.73.0] - 2026-11-02

### Added

- cron module: your crontab and the system's (/etc/crontab, /etc/cron.d, anacron's jobs) with each
  entry's next run, soonest first, and a scripts mode for cron.daily and the other run-parts
  directories. Next runs come from `systemd-analyze calendar`, with cron's rule that a restricted day of
  month or day of week is enough. The preview lists the next five runs. ctrl-e edits (sudoedit at the
  line for system files), alt-d comments an entry of your crontab out or back in, and alt-enter runs one
  now.

## [0.72.0] - 2026-11-02

### Added

- bluetooth module: paired devices (connected first) and every device bluez knows, under a header row with
  the controller's power. Rows show the device's kind, state, trust, battery and address. alt-c connects,
  alt-d disconnects, alt-p pairs (then trusts and connects), alt-t flips trust, alt-x removes, alt-s scans
  (the all mode) and alt-P powers the controller on or off. The preview shows `bluetoothctl info` with the
  services by name.

## [0.71.0] - 2026-11-02

### Added

- music: alt-* rates the selected songs (the queue and an album's or playlist's songs) through
  `musicman edit`, asking for 0 to 5 in half steps with the first song's rating to edit.
- music: alt-t edits the songs' context, mood and picks (`FZX_MUSIC_EDIT_FIELDS`) in an fzf of the values in
  use, from `musicman values` (musicman 1.61 or later). Each value is marked by how many of the songs have
  it, and the ones every song has start selected; enter writes the difference to every song, alt-enter also
  adds the query as a new `field:value`. Previews read the new values right away.

## [0.70.0] - 2026-11-02

### Added

- docker: alt-E runs a typed command in each selected container, under a header naming it, and keeps the
  output on screen. It goes through the container's sh when it has one (pipes and globs work), else runs as
  words. The prompt has readline editing and a history of earlier commands (up and down).
- docker: a df action (actions menu) shows `docker system df` and its per-item `-v` listing in the pager.

## [0.69.0] - 2026-11-02

### Added

- github: a pull request's preview shows its review threads after the timeline, by file and line: a header
  line per thread (`path:line`, outdated, resolved), the last lines of the diff it comments on
  (`FZX_GITHUB_HUNK_LINES`, 4) and its comments with their reactions. Resolved threads show as their header
  line alone. Read through GraphQL and cached with the pull request's last update.

### Removed

- TODO: the tmux marked-pane round trip moved to the tmux config's TODO.md (a tmux key, not an fzx action).

## [0.68.0] - 2026-11-02

### Added

- claude: alt-t opens the project's TODO.md items in the todos module (alt-left comes back).
- todos: `--dir DIR` makes the here mode read the nearest TODO.md from that directory instead of the
  current one (`fzx -m todos -- --dir ~/project`).

## [0.67.0] - 2026-11-02

### Added

- claude: a module for Claude Code projects, over `claude-projects --tsv` from ~/.shell: your projects with
  a CLAUDE.md and every directory Claude has run in, with kind (git, dotbare, plain), version, branch,
  changes, ahead/behind, open TODO items and P1s, the last session and the session count. Modes all, own
  and active (`FZX_CLAUDE_ACTIVE_DAYS`); sort by last session or name. The scan is cached and refreshed in
  the background (`FZX_CLAUDE_TTL`). Enter prints the path; ctrl-o starts Claude Code there (in tmux, a
  window per project named after it), alt-o continues the last session, alt-i shows the full
  `claude-projects show` card, alt-l and alt-d open the git and files modules on it. The preview shows git
  state, the top TODO items and the newest sessions' titles and prompts.
- zsh: `fzx-claude-widget` cds into a Claude Code project (unbound by default, `FZX_ZSH_KEYS[claude]`).

## [0.66.1] - 2026-11-02

### Added

- docs: a README: what fzx is, requirements, install, use, the modules, where the docs are.

### Changed

- docs: PLAN.md, the brief the project started from, moved to `docs/brief.md` as history.

### Fixed

- github: comment and review headers in issue and pull request previews are lines of their own (a rule
  with the author, association, verdict and date, `FZX_COLORS[github_author]`) instead of `###` headings, which
  a body's own headings looked like.
- actions menu: no enter mark on the default action when the module binds enter itself (`tasks --paste`,
  where enter pastes).
- tasks: a just recipe documented by several comment lines shows them all, not just the last one
  (a `[doc]` attribute still wins).
- stats: `fzx stats` works with an awk that has no `strftime` (mawk before 1.3.4): the dates come from
  date(1) then.

## [0.66.0] - 2026-11-02

### Added

- git: alt-x (drop) in branches deletes remote branches too, on their remote (`git push REMOTE --delete`,
  one push per remote). Local and remote ones are asked about separately, so a mixed selection never
  pushes a delete under the local question.
- Action rows take an `asks` flag: the action asks its own questions on the terminal (listed as asking
  first in f1 and the actions menu; fzx asks nothing). `fzx::confirm` reads `FZX_TTY` when set.

### Changed

- github: issue and pull request previews in the style of octo.nvim: the state as its icon and word in its
  color, labels as chips in their GitHub colors, the review decision with an icon (approved, changes
  requested, review required), reactions under the body and each comment, and the comments and a pull
  request's reviews in one timeline, each under a heading with its author, the author's association with
  the repository, the review's verdict and the date. Previews cached before this fetch again once.

### Fixed

- github: after alt-7 (everywhere) the issues and prs header kept naming the repository; the toggle now
  restarts fzf (query kept) and the header names the list's scope, with the key back to the repository.

## [0.65.0] - 2026-11-02

### Added

- youtube: the preview shows the video's thumbnail (chafa; fetched once with curl into the cache;
  `FZX_YOUTUBE_THUMBS=0` leaves it out).
- youtube: alt-F lists the formats of the video under the cursor (resolution, fps, codecs, size, bitrate),
  best first; enter or alt-d downloads the selected ones: a video and an audio format are merged, a
  video-only format alone gets the best audio, audio-only formats go to the audio directory. alt-d in the
  search results downloads the videos at their best (`FZX_YOUTUBE_VIDEO_DIR`, else the XDG videos
  directory).
- logs: a dot before each file in the color of its age (`FZX_LOGS_AGE_DOT`; "" leaves it out).
- logs: the preview follows the log while its row has focus (`FZX_LOGS_PREVIEW_FOLLOW=0` for a snapshot).
- logs: files and container logs are colored by `FZX_LOGS_COLORIZER` (ccze -A by default; grcat works too),
  in the preview and when following; journals keep systemd's colors. A unit's preview pins the top of its
  `systemctl status` above the journal (`FZX_LOGS_STATUS_LINES`, 8); entering or leaving units mode
  restarts fzf.
- ps: top mode, every process reloaded every `FZX_PS_TOP_INTERVAL` seconds (2 by default); the cursor and
  the selection stay on their pids as the rows reorder.

### Changed

- ps: PIDs are right-aligned like the other numeric columns.

## [0.64.0] - 2026-11-02

### Added

- capture: alt-o in urls mode opens the selected URLs in the browser.
- capture: ips mode also finds IPv6 addresses, with their zone (`%eth0`) and prefix length; code such as
  `fzx::cb`, MAC addresses and times are left out.
- capture and tmux buffers: ctrl-e edits the selection in `$EDITOR` before pasting it into the origin
  pane; emptying the text (or quitting with `:cq`) pastes nothing.
- tmux keys: alt-enter runs the binding under the cursor as if its key were pressed, after fzx (and its
  popup) has closed. Copy-mode bindings are refused, and bindings that kill something ask first unless
  they already use tmux's confirm-before.

## [0.63.0] - 2026-11-02

### Added

- music module: MPD's queue, artists, albums and playlists through mpc. Enter goes from an artist to their
  albums to an album's songs (and from a playlist to its songs), each a child session that back returns
  from; enter on a song plays its album or playlist from there. Play, add, play next, remove, delete
  playlists, clear and save the queue, and play/pause, next and previous. The preview shows the cover,
  the song's tags, musicman's rating, grouping, mood and context when musicman is installed, and the
  player's state in the queue.

## [0.62.0] - 2026-11-02

### Added

- packages: snap-available and flatpak-available list the snap store's names and the flatpak remotes'
  applications to install from; a search mode asks crates.io, npm and rubygems.org as you type (and PyPI
  for an exact name), with a toggle per registry. Packages that are not installed are previewed from the
  network, cached a day each. Install handles snaps that need --classic and installs flatpaks from their
  remote.

### Changed

- packages: remove asks first itself for every manager but apt, which lists what else it would remove and
  asks on its own (no more double prompt); purge leaves the asking to apt.

## [0.61.0] - 2026-11-02

### Added

- packages module: installed packages of apt, snap, flatpak, pipx, cargo, pnpm and gem (a mode for each
  manager on PATH), apt's available and upgradable packages (cached until apt's lists change), with
  install, upgrade, remove and purge (sudo where the manager needs it) and previews read locally.

## [0.60.1] - 2026-11-02

### Changed

- Actions menu: the reload mark sits a space after the run icon (Nerd Font glyphs drew over each other) in
  a dimmer teal, and the preview lists each flag on its own line with what it means.

## [0.60.0] - 2026-11-02

### Added

- tasks: `--paste PANE` makes enter paste the task's command line into a tmux pane without submitting it
  (`cd DIR && CMD` for another repository's task; several tasks joined with `&&`), and alt-x runs it in
  place. The tmux config binds alt-t to the tasks module in a popup with it.
- tasks: the preview highlights the definition in its file's language (package.json as JSON, Makefile,
  Taskfile YAML, cargo and pyproject TOML; just recipes as bash) and the command line as bash.
- The actions menu (ctrl-\) is drawn in color: an icon for how each action runs (in the terminal, in the
  background, in fzf's place, asking first) with a reload mark, names in bold and fzx's own built-ins
  dimmer, keys as keycaps, ⏎ on the default action; the preview colors the key, the flags and the
  arguments. Colors in `FZX_COLORS[actions_*]`, icons in lib/icons.sh (`action_*`).

### Changed

- A module whose opts hook binds enter itself keeps it: its default action no longer takes enter over.

## [0.59.0] - 2026-11-02

### Added

- ctrl-_ (what ctrl-shift-_ and ctrl-/ send) also selects the next sort, next to f12; it takes ctrl-/ from
  fzf's toggle-wrap-word.
- The sorted column's look is configurable: `FZX_SORTED_STYLE` takes decorations (bold, dim, italic,
  underline, blink, reverse, overline, underdouble, undercurl, underdotted, underdashed) and
  `FZX_SORTED_UNDERLINE_COLOR` the underline's color (#rrggbb or 0-255). Setting `FZX_COLORS[sorted]`
  directly still wins.

### Changed

- The sorted column is drawn with a dim gray (#6e6e6e) dashed underline instead of a plain underline.
- Markdown previews no longer use glow: the user's viewer, else nvcat, else bat.

### Fixed

- tmux lists and the keybindings preview strip SGR sequences with colons (`4:5`) too.

## [0.58.0] - 2026-11-01

### Changed

- The prompt shows the current mode's icon (`FZX_ICON_MODES`, for example files:grep and glyphs:emoji)
  instead of the module's, and follows in-place mode switches (alt-0 / alt-9).

## [0.57.0] - 2026-11-01

### Changed

- Preview layouts for colors, dirs, docker, git, keybindings, logs, man, network, ps, recent, shell,
  systemd, tasks, tmux and youtube, tuned to what each shows: long lines (logs, diffs, unit status, pane
  captures) keep the preview below until the terminal is wide, short details (colors, tasks, keybindings)
  move it to the right early, and logs keeps it below at every width. Checked at 80, 120 and 200 columns.
- logs, git, docker, systemd, tmux and man open in larger popups than the default (95% by 90% from 140
  columns, 90% by 85% from 220).

## [0.56.0] - 2026-11-01

### Added

- Popups follow the tmux window: when the window is resized, an open popup is reopened at the size its
  module's `FZX_POPUP_LAYOUTS` calls for at the new width (and for the new size, with percentages), keeping
  the query and position. A drag reopens it once, after the size has held for `FZX_RESIZE_SETTLE_MS` (300).
  Before, a popup stayed at its old size when the window grew and was clipped when it shrank.

## [0.55.0] - 2026-11-01

### Added

- Popup geometry per module: a plain popup or float is sized by `FZX_POPUP_LAYOUTS`, `MINCOLS:SPEC`
  entries (`--popup` syntax) picked by the width of the whole tmux window, not the calling pane, since the
  popup covers its splits. Modules can set their own in `config.sh`; the default is `center,100%` below
  140 columns, `center,90%,85%` to 220 and `center,80%` above. Moving to another module in a popup opens
  it at that module's size.

### Changed

- `FZX_POPUP_OPTS` and `FZX_FLOAT_OPTS` are empty by default. When set, they are one fixed size that wins
  over every module's layouts, so a size set in your config.sh keeps applying everywhere.

## [0.54.0] - 2026-11-01

### Added

- audio: a new module for outputs, inputs, playing streams and media players, through pactl (PulseAudio
  or PipeWire) and playerctl. Enter makes an output or input the default, plays or pauses a player, or on
  a stream opens the outputs to move it to. alt-up and alt-down change the volume (capped at
  `FZX_AUDIO_MAX`), alt-m mutes, alt-n and alt-p skip tracks. The preview shows a device's channels, port,
  bus and codec and what plays on it.

## [0.53.0] - 2026-11-01

### Added

- glyphs: a new module for picking characters. Nerd Font glyphs by name (Nerd Fonts 3.5.1, shipped with the
  module; alt-U downloads the latest names), named Unicode characters with their block, the Unicode blocks
  (enter opens one), and emoji by name with their group. Enter prints the glyph; alt-c, alt-n and alt-e
  copy its code points, name or `\u` escape. The preview shows the glyph, its codes, UTF-8 bytes and HTML
  reference, and a grid of its neighbours. Replaces ~/.shell's nerdfont-symbols, unicode-symbols and
  unicode-all; the Unicode modes read the unicode-data package's files.

## [0.52.0] - 2026-11-01

### Added

- colors: a 16 mode, the terminal's own colors (30-37 and 90-97) in normal, bold, faint and inverted, with
  the background twin, the 256-color index and every attribute in the preview (from ~/.shell's colorcodes).
- colors: the names preview ends in a true-color gradient: banding means the terminal or tmux maps true
  color to the 256 palette (from ~/.shell's termcolors_16).

## [0.51.0] - 2026-11-01

### Added

- github: a repository's hub (`github:repo --repo OWNER/REPO`, else the repository here), opened with ctrl-o
  on any repository row: its files, open issues, open pull requests and workflow runs, with their counts and
  the last run's state; enter or ctrl-o opens the row's list. The preview shows the README, the first issues
  or pull requests, or the latest runs.
- github: workflow runs (`github:runs`), latest first, with their state, workflow, branch, event, age and
  duration; the preview lists the run's jobs and a failed job's failed steps. alt-l shows the log (only the
  failed jobs' for a failed run; a running one is watched), alt-R reruns (a failed run's failed jobs), alt-x
  cancels (asks first).

### Changed

- github: ctrl-o on a repository opens its hub instead of its files (the hub's first row).

### Fixed

- Navigating to a hidden mode (a drill-down such as github's files) with the same arguments as another
  screen of that module opens a session of its own instead of reusing the other one, whose modes it lacks.

## [0.50.0] - 2026-11-01

### Added

- history: a command over several lines is drawn over several lines, under the command column, instead of
  joined by ↵: up to `FZX_HISTORY_MAX_LINES` (4) of them, then "… +N lines" (the preview has all of it).
  `FZX_HISTORY_MULTILINE=0` joins them again.
- `FZX_READ0=1` for modules whose items are NUL-terminated and may span lines: fzf reads them with
  `--read0 --highlight-line` and the callbacks count items by NUL.

### Changed

- history's cache moves to `$FZX_CACHE_DIR/history/*.v2.rows`; the old files are removed on the first run.

## [0.49.2] - 2026-11-01

### Fixed

- history: a run that exited 130 (ctrl-c, or esc in fzf and fzx) or 141 (a closed pipe) is interrupted, not
  failed: it gets an icon of its own instead of red, the failed toggle leaves it out, and the preview counts
  it apart and leaves it out of the success rate. `FZX_HISTORY_INTERRUPTED` sets the codes.

## [0.49.1] - 2026-11-01

### Changed

- logs and systemd have test files of their own (test/logs.bats, test/systemd.bats), covering their
  previews, every action, the menu entries and summaries, and the bindings under fzx.

## [0.49.0] - 2026-11-01

### Added

- history: rows show how long ago the latest run was (fading with age), its duration (yellow over a minute,
  red over five), the host in global mode (other hosts colored), and the command colored by its parts
  (command words, options, quoted text, variables, operators). Only the command is searched.
- history: the succeeded toggle (alt-s), the runs toggle (alt-a: every run, not one row per command) and
  the frecent sort (runs weighted by how recent they are).
- history: alt-c puts `cd DIR && COMMAND` on the command line, the directory it last ran in; ctrl-y copies.
- history preview: the success rate, the median duration and the last 8 runs (when, status, duration, host,
  directory).
- history: host and global keep their rows in `$FZX_CACHE_DIR/history` and read only the runs added since,
  so the list starts showing at once.
- zsh: `FZX_ZSH_HISTORY_MODE` picks the history widget's first mode.

### Changed

- history: global (every host) is the default mode, of `fzx -m history` and of the zsh widget, which no
  longer follows `SHELL_HISTORY_SCOPE`. The menu lists every host's history and this machine's.

## [0.48.0] - 2026-11-01

### Added

- files: a trash action (alt-x, confirmed) for files and directories, through trash-put or else gio trash;
  in grep mode it trashes the files of the selected matches. Offered only when one of the two is installed.

## [0.47.0] - 2026-11-01

### Added

- ps: trace (alt-t, strace of every call) and trace-errors (alt-T, failing calls only) follow the process and
  its threads until ctrl-c; through sudo unless ptrace allows tracing it directly.
- ps: alt-o opens the process's open files (the network module's files mode).
- ps: sudo-term and sudo-kill (from the actions menu) signal other users' processes, asking sudo for the
  password.

### Changed

- ps: term and kill retry a process that is not yours through `sudo -n` (a cached sudo); when that fails
  too, term says why in the footer.

## [0.46.0] - 2026-11-01

### Added

- systemd: timers and sockets modes, both managers in one list: a timer's next and last run and the unit it
  activates, a socket's addresses. The journal action on a timer or socket follows the unit it activates.
- systemd: a reload action (alt-L, reload-or-restart) and daemon-reload (from the actions menu, once per
  manager of the selection).
- systemd: the files toggle (alt-u) lists static, masked, generated and alias unit files as well.

### Fixed

- systemd lists unit files that are not loaded (disabled, or enabled but never started), so they can be
  started and enabled from fzx; they sort last by state. Template units are left out.

## [0.45.1] - 2026-11-01

### Added

- `just test-live` (test/live.bats, opt-in with `FZX_TEST_LIVE=1`): the docker module's containers, volumes,
  networks and previews and the systemd module's user-unit actions run against the real daemon and user
  manager, with throwaway fzx-live-* objects removed afterwards. Nothing is pulled.

## [0.45.0] - 2026-11-01

### Added

- The menu has two modes. `groups` (the default) lists the five most used entries first under "recent"
  (from the usage stats, recent use weighing most), then the rest under group headers (files, shell,
  development, system, terminal, other), most used first. `list` is the old flat list in module order:
  `fzx -m menu:list`, or alt-0 / alt-9 in the menu. Headers vanish while typing a query; enter on one moves
  down. Settings: `FZX_MENU_RECENT`, `FZX_MENU_GROUPS`, `FZX_MENU_HALF_LIFE_DAYS`, `FZX_MENU_STATS_DAYS`,
  a module's `FZX_MENU_GROUP`, `FZX_COLORS[menu_group]`.

## [0.44.0] - 2026-11-01

### Added

- zsh: `fzx-menu-popup-widget` opens the menu in a tmux or Zellij popup (inline elsewhere) and inserts what it
  returns, like the menu widget. Unbound by default; bind it with `FZX_ZSH_KEYS[menu-popup]`.

## [0.43.1] - 2026-11-01

### Added

- docs/design.md: a new-module checklist (components, previews and their layouts, icon and menu color,
  menu entries and summaries within their timeouts, tests, docs), with the modules still missing parts.

## [0.43.0] - 2026-11-01

### Added

- Copying says so in the footer: under fzx, the copy and copy-line actions show "copied ITEM" (or "copied
  N items") for `FZX_NOTIFY_SECONDS` (2), then the component line comes back. A failure shows its first
  error line instead (no clipboard tool, say).
- The action flag `notify` does the same for a module's own actions ("✓" and the action's description);
  history's copy, shell's value copy (alt-y) and the colors module's hex, SGR and escape copies use it.
- `FZX_COLORS[notify_ok]` and `[notify_fail]` color those messages.

## [0.42.1] - 2026-11-01

### Changed

- Colors move off bright yellow toward white, aqua and turquoise: the dirs, tasks and logs icons, files'
  dirs mode, tasks' python runners and tmux option values. The network module's middling signal and
  github's pending checks are a muted tan. GitHub stars stay gold.
- Highlighted backgrounds are dark tints now: selected items in the `round` and `triangle` component
  styles (`FZX_COLORS[pill_on]` 24, text 195 instead of a bright blue fill) and github's code matches
  (dark teal instead of yellow).

## [0.42.0] - 2026-11-01

### Added

- `FZX_COMPONENT_STYLE=icon`: the component line with on/off markers on the toggles; `FZX_TOGGLE_ICONS`
  picks them, `switch` (the icon set's) or `dot` (● / ○).

### Changed

- The component line's style setting is `FZX_COMPONENT_STYLE` now, and `bubble` is called `round`; the old
  `FZX_HEADER_STYLE` and `bubble` still work.
- `minimal`, the default, draws toggles without markers (their color shows the state), and so do `round`
  and `triangle`; the sort keeps its icon in every style.

### Fixed

- With `FZX_ICONS=none` the sort read `↓name`; it has its space now.

## [0.41.0] - 2026-11-01

### Added

- Toggles flip with alt-1 .. alt-8 as well, numbered by their order in `components.tsv` (alt-9 and alt-0 stay
  the mode keys). A number that another component row or an `FZX_KEYS` entry already has is skipped;
  `FZX_TOGGLE_DIGIT_KEYS=0` turns the numbers off.

## [0.40.0] - 2026-10-31

### Added

- `files` grep mode: ctrl-t (`FZX_KEYS[files.filter]`) switches from grepping as you type to filtering the
  matches with fzf, the grep term frozen and shown in the header (reloads and toggles keep grepping it);
  ctrl-t again puts the term back in the query and greps.

## [0.39.0] - 2026-10-31

### Changed

- Markdown previews use nvcat instead of mdpreview (then glow, then bat), in the files module, `fzx preview`
  and the github and todos previews alike.
- Files that `nvcat-dispatch --print` claims (kitty, tmux, systemd units, justfiles, *.conf and the other
  formats bat has no syntax for) preview through nvcat with their filetype; a grep hit's line stays on bat,
  which highlights it.
- Files over `FZX_PREVIEW_NVCAT_MAX_LINES` source lines (300) skip nvcat and preview with bat: nvcat stops
  at 1000 screen rows and failing there took seconds.
- Every module preview (github, history, logs, man, shell, todos) renders through one set of renderers
  (lib/render.sh): `FZX_PREVIEW_VIEWERS` applies to their markdown, and `NO_COLOR` turns bat's colors off
  everywhere.

### Removed

- `FZX_GITHUB_MARKDOWN`: set a markdown viewer in `FZX_PREVIEW_VIEWERS` instead (`markdown=glow`).

## [0.38.2] - 2026-10-31

### Fixed

- The free keys on the f1 page include every key fzf can bind: ctrl-space, ctrl-\, ctrl-], ctrl-^,
  ctrl-/, ctrl-alt-a..z, alt- with punctuation (- _ = . , / ; ' ]) and ctrl/alt/shift with the
  navigation keys (arrows, home, end, page-up, page-down, delete). The grid shows the punctuation keys too.
- A key bound under one of fzf's synonyms (ctrl-_, ctrl-6, ctrl-backspace, alt-backspace) counts as taken
  under its other name.
- Free key rows in the glyph style wrap at the preview's width instead of early.

## [0.38.1] - 2026-10-28

### Fixed

- A run ended by a closed terminal (SIGHUP) or SIGTERM records its `exit` row (`hangup`, `term`; counted
  as aborts in `fzx stats`); before, only the cleanup ran.
- `persist=none` sources record their line count in stats (a copy of the stream is counted).
- A float is the size a popup is for the same options: the spec sizes the inside, the border is added.
- Previews of a line that is not a path try its first field (`path  size  date` listings); with
  ~/.config/fzf/fzfrc passing the whole line, paths with spaces preview in plain fzf.

### Added

- `fzx gc` rotates the log to `fzx.log.1` once it passes `FZX_LOG_MAX_KB` (1024).

## [0.38.0] - 2026-10-28

### Added

- File previews by type (lib/preview.sh), shared by the files module and plain fzf: `fzx preview PATH`
  (~/.shell/scripts/fzf-preview runs it). Besides code (bat) and images (chafa, now with a size line):
  markdown through mdpreview, mp3 tags (named, in a fixed order, cover summarised, under the duration and
  bitrate), audio and video through mediainfo, PDFs (first pages as text), archives and .deb listings,
  compressed files (decompressed and highlighted), JSON through jq, SQLite tables and schema, certificates
  through openssl (private keys are named, never shown), office documents and epub through pandoc, and a
  hex dump for other binaries.
- Grep hits (`path:line:col:text`) preview the file at that line, also from plain fzf.
- `FZX_PREVIEW_VIEWERS` picks the command per type or file-name glob (`markdown=glow -s dark;*.log=lnav`),
  `FZX_PREVIEW_TEXT` the text viewer.
- `FZX_PREVIEW_DEBUG=1` starts each file preview with how the file was detected, what drew it and how long
  it took; the same goes to the log at debug level.
- `fzx preview` in the zsh completion.

### Changed

- The files module's directory tree, images and text come from the shared previewer; directories show
  hidden entries two levels deep as before.

## [0.37.0] - 2026-10-28

### Added

- The `shell` module (menu: `shell`, `shell:aliases`, `shell:functions`, `shell:params`): commands on PATH
  and zsh's builtins and reserved words, aliases, functions and parameters. The preview shows a command's
  locations and its tldr or man page (a builtin's zshbuiltins entry), an alias's definition and what it
  runs, a function's definition, and a parameter's whole value (arrays and associations an element a line,
  `*PATH` values a directory a line).
- Values of parameters whose names look secret (`FZX_SHELL_SECRETS`: TOKEN, SECRET, PASSWORD, `_KEY`, ...)
  are masked and never written to disk; the `reveal` toggle (alt-3) shows exported ones.
- Actions: ctrl-e opens a function's file at its definition (or a command's script) in $EDITOR, alt-n the
  tldr or man page in the pager, alt-y copies parameter values.
- zsh: `fzx-shell-widget` (alt-s) dumps the shell, so its current aliases, functions and parameters show,
  and inserts the picked names; shell/fzx.zsh also dumps the shell at the first prompt
  (`FZX_ZSH_NO_SHELL_DUMP=1` turns both off).

## [0.36.0] - 2026-10-28

### Added

- github: a `notifications` mode (menu: `github:notifications`) with your unread notifications, the latest
  50; the `read` toggle (alt-8) adds read ones. Each row shows an unread mark, the subject's type, the
  repository, the title, why you got it and its age, and links to the subject's page: an issue's or pull
  request's preview and actions (checkout, comment, close, reopen) work on it.
- github action alt-u: mark the selected notifications read.

## [0.35.1] - 2026-10-28

### Fixed

- github issues and prs involving you: repository names longer than the column (32) are cut with "…", so
  the rest of their row lines up with the others.
- github previews rendered with glow (READMEs, issues, pull requests) no longer hang when the preview's
  stdin is an open pipe: glow 3 reads stdin even when given a file.

## [0.35.0] - 2026-10-28

### Added

- github: `issues` and `prs` modes (menu: `github:issues`, `github:prs`). They list the repository you are
  in (from its origin remote), or `--repo OWNER/REPO`'s; outside a GitHub repository, or with the
  `everywhere` toggle (alt-7), the ones involving you anywhere. Open ones by default; the `closed` toggle
  (alt-6) adds closed and merged ones. Rows show a state icon, the labels in their GitHub colors, the
  author and age, and for a repository's pull requests their size and review decision.
- github preview of an issue or pull request: its details, a pull request's branches, size, review and
  checks, then the body and comments rendered as markdown (cached until the item changes).
- github actions on issues and pull requests: alt-k checkout (`gh pr checkout`, or a branch for an issue,
  in the repository here or its ghq clone), alt-m comment in $EDITOR, alt-x close and alt-X reopen (both
  ask first).
- `FZX_GITHUB_ISSUES_TTL` (2m): how long issue and pull request lists are kept; their actions drop them.

## [0.34.1] - 2026-10-27

### Changed

- tasks: the menu's three tasks entries have colored icons of their own (here, chosen projects, every
  repository) and the prompt shows the tasks icon; colors are `FZX_COLORS[tasks_icon]`,
  `[tasks_icon_repos]` and `[tasks_icon_all]`.

## [0.34.0] - 2026-10-27

### Added

- tasks: each row shows its runner (make, just, npm, go-task, cargo, pdm/poe/hatch) as a colored Nerd Font
  icon before the runner's name, and the projects mode counts tasks by icon. Colors are
  `FZX_COLORS[tasks_kind_<runner>]`; with `FZX_ICONS=unicode` or `none` the rows are as before.

## [0.33.1] - 2026-10-27

### Fixed

- tmux 3.4 (no `list-keys -F`): the keys mode shows the bindings' notes again (`list-keys -N`).
- CI passes: it installs fzf (0.74.5), tmux and sqlite3, and the tests no longer depend on where
  ripgrep is installed or on SIGPIPE being delivered.

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
