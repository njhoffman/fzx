# fzx

An fzf module manager in bash. Each module is a list (processes, git refs, files, GitHub issues, tmux panes,
packages, ...) with its own modes, toggles, sort orders, previews and actions, and `fzx` runs them all with
one interface: the same keys, help, placements (inline, split, tmux popup or float) and navigation between
lists, which keeps each screen's query and position when you go back.

Modules are directories of small scripts. Each script also runs on its own (`modules/ps/source.sh` prints
the list, `modules/ps/module.sh` opens it in plain fzf), so a module can be tested without the interface.

## Requirements

- bash 5 and a recent fzf (developed against fzf 0.74; fzx uses `--popup`, `--footer` and `--listen`)
- tmux for popups, floats and the tmux and capture modules
- the tools a module wraps: fd and ripgrep (files), git, gh and jq (github), docker, mpc (music), yt-dlp
  (youtube), zsh-histdb (history), and so on. The menu lists a module's entries only where they apply (the
  github ones once gh is installed and logged in, for example).

## Install

```sh
just install                          # symlinks bin/fzx into ~/.local/bin (or $XDG_BIN_HOME)
source /path/to/fzx/shell/fzx.zsh     # in your zshrc: the widgets below
fzx completion zsh > "${fpath[1]}/_fzx"
```

`shell/fzx.zsh` binds alt-f (files), alt-d (dirs), alt-j (jump), alt-g (git), alt-p (ps), alt-m (the menu),
alt-r (repos), alt-s (shell) and ctrl-r (history), each putting its result on the command line. It also
adds `g`/`gg` (cd to a frecent directory) and `v` (open a frecent file). The top of the file lists the
settings that change or turn off each part (`FZX_ZSH_KEYS`, `FZX_ZSH_NO_BIND`, ...).

## Use

```sh
fzx                            # the menu of every module's entries
fzx -m git                     # a module
fzx -m git:branches            # a module in one of its modes
fzx -m files --popup -- ~/src  # in a tmux popup, with the module's own arguments
fzx -m ps --dry-run            # print the fzf command instead of running it
fzx config -m git              # the resolved config: layers, keys, colors, settings
```

Inside any module, f1 shows every key, mode, toggle and action. The common ones:

| Key | Does |
|---|---|
| f1 | help: the keys in use, the module's components |
| ctrl-\ | the actions menu |
| ctrl-o / alt-left | into the row where a module has a level below (a branch's log, a directory) / back |
| alt-9 / alt-0 | previous / next mode |
| alt-1 .. alt-8 | the module's toggles, in table order |
| f11 / f12 | previous / next sort order |
| alt-o | the main menu, from anywhere (`FZX_KEYS[menu]`) |
| ctrl-y / alt-y | copy the selection's value (what the module calls it) / the whole line as it shows |
| ctrl-w / alt-w | wrap the list's rows / the preview (ctrl-shift-w in alacritty sends alt-w) |
| ctrl-^ | next placement: inline, split, popup, float |
| alt-^ | a popup or the plain terminal, nothing else |

## Modules

| Module | Lists |
|---|---|
| actions | the actions menu of the screen it was opened from |
| applications | desktop entries with their icons: launch one (a launcher for a window-manager popup) |
| aws | EC2 instances, CloudWatch log groups, ECS and EKS clusters and RDS instances, read-only: details, recent events, following a group, the console |
| audio | outputs, inputs, playing streams and media players |
| bluetooth | paired and nearby devices: connect, pair, trust, remove |
| browser | Chrome, Chromium, Brave, Vivaldi and Firefox history and bookmarks, opened in their own profile |
| claude | Claude Code projects: git state, version, open TODOs and sessions; start or resume Claude there |
| capture | URLs, paths, words, hashes, IPs or lines out of a tmux pane |
| colors | the 256-color palette, the terminal's 16 colors, X11 names and fzx's own colors |
| cron | crontab and system cron entries with their next runs, anacron jobs and cron scripts |
| dirs | directories under ~, and bookmarks |
| docker | containers, images, volumes, networks and compose projects |
| files | files and directories, or a grep of their contents |
| firewall | ufw rules and application profiles |
| fonts | font families with a sample drawn in each |
| git | status, log, branches, tags, stash, reflog and work trees |
| github | repository and code search, your repositories and stars, issues, pull requests, runs, notifications |
| glyphs | Nerd Font glyphs, Unicode characters and blocks, emoji |
| history | zsh-histdb commands |
| keybindings | zsh and tmux key bindings, and fzf's own |
| logs | log files, systemd journals and docker container logs |
| man | man pages and tldr pages |
| menu | every module's entries (what `fzx` opens) |
| music | MPD's queue, artists, albums and playlists |
| network | ports, connections, interfaces, routes, wifi and mDNS services |
| packages | apt, snap, flatpak, pipx, cargo, pnpm and gem packages; registry search |
| ps | processes: user, all, top and tree |
| recent | frecent files and directories |
| repos | git repositories with their branch, changes, ahead/behind and open TODOs |
| sessions | fzx's own session trees: resume kept ones, open a copy of live ones |
| shell | commands on PATH, zsh builtins, aliases, functions, parameters and completions (zsh-complete) |
| systemd | user and system units, failed ones, timers and sockets |
| tasks | project scripts: make, just, npm, Taskfile, cargo aliases, pdm/poe/hatch |
| tmux | sessions, windows, panes and buffers; reference browsers for keys, options, formats and more |
| todos | open items of TODO.md files |
| youtube | YouTube search: play, open or save as mp3 |

Your own modules go in `~/.config/fzx/modules/<name>/` (`FZX_MODULE_PATH`). Configuration layers from
`config/defaults.sh` through the module's `config.sh` to `~/.config/fzx/config.sh` and
`~/.config/fzx/modules/<name>/config.sh`.

## Docs

- `docs/design.md`: the design, the process model, the module contract and the new-module checklist, every
  setting, and each module's modes, keys and actions
- `docs/tmux.md`: the tmux module in detail; `docs/components.md`: the components table's design
- `CHANGELOG.md`: what changed in each version; `TODO.md`: the roadmap and known issues
- `docs/brief.md`: the brief the project started from

## Development

```sh
just test         # the bats suite (in parallel with GNU parallel)
just lint         # shellcheck over every bash file
FZX_LOG_LEVEL=debug fzx -m git; fzx debug tail   # callbacks, their durations and the actions they return
```
