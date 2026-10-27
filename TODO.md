# fzx TODO

Status (0.24.0): the six steps of `docs/design.md` are done. Modules: actions, capture, colors, dirs,
docker, files, git, github, history, keybindings, logs, man, menu, ps, recent, repos, systemd, tmux, todos,
youtube; zsh widgets in `shell/fzx.zsh`. What has shipped is in CHANGELOG.md, so ticked items are removed
here once they are released. Keep this file current: tick items off, add what you find.

Every item carries a priority in its first line, `(p1)` high, `(p2)` normal or `(p3)` low, and a
category: `[bug]` `[feature]` `[refactor]` `[docs]` `[test]` `[chore]` `[perf]`, plus this repo's own below.
`(due YYYY-MM-DD)` adds a date and an OVERDUE flag. `/todo` (`~/.shell/scripts/todo-status`) and `/todo-pop`
(`fzx -m todos`) sort and mark by them; `todo-status --check` lists untagged items.

Categories: module

## 1. Next up

- [ ] **Query-driven sources share the mode cache** (p1) [bug]: `files` is `cache:5m`, so every `files:grep`
      keystroke writes its hits through to the persistent entry for the mode (`fzx::_cb_persistent_path`
      keys on module, args, cwd and mode, not the query). A new `files:grep` launch within 5 minutes starts
      with the previous query's hits under an empty prompt. Fix: a per-mode persist override (`none` for
      query-driven modes), or key the entry on `FZF_QUERY` when the mode is `--disabled`.
- [ ] **Widget keys that fit** (p1) [chore]: the alt-f/d/j/g/p/m defaults took over the user's alt-f
      (edit-command-line), alt-d (_close-shell) and alt-g (Telescope projects) in ~/.shell/zsh/keymaps.zsh, so
      the postloader sets FZX_ZSH_NO_BIND=1 (widgets defined, unbound): the widgets go unused. Pick free keys
      (`fzx -m keybindings` shows the zsh side, `fzx keys` fzf's) and set FZX_ZSH_KEYS, or bind by hand.
- [ ] **Menu ordering by use** (p1) [feature]: the menu lists about 70 entries in module order. Sort by
      `stats.tsv` (recent and frequent first), with a "recent" group on top, and consider group headers
      (shell, system, development) for the rest.
- [ ] **`fzx --version`** (p2) [bug]: falls through to fzf and fails ("inappropriate ioctl for device").
      Print the VERSION file; show it at the top of the f1 page too.
- [ ] **Summaries keyed by more than the directory** (p2) [bug]: the cache is per directory, so git
      summaries (ahead/behind, changes) stay stale for up to `FZX_SUMMARY_TTL` (5m) after a commit or stage,
      and the capture entries have no summary because they depend on the pane. Let a manifest add to the
      key (`<module>::summary_key`: HEAD and the index mtime for git, the pane for capture), or give a
      module its own TTL.

## 2. Menu and presentation

- [ ] **Styled menu previews** (p2) [feature]: the menu's preview of each module entry is plain text now; give it
      color and layout (the icon and title, the entry's description, its summary, the module's modes and keys).
- [ ] **Mode icon in the prompt** (p3) [feature]: the prompt shows the module's `FZX_ICON` even in a mode with
      its own menu icon (`FZX_ICON_MODES`, files:grep). The `load:change-prompt(...)` bind is fixed when fzf
      starts, so an in-place mode switch needs the load bind to follow the mode (a `transform-prompt`
      callback on load, or the mode switch rebinding it).
- [ ] **Theme selector** (p2) [feature]: building on `colors:fzx`, a screen listing every color setting
      (fzf's `--color` keys and fzx's `FZX_COLORS`) with their current values; pick one, change it
      interactively, and see it in a live sample fzf launched with the new colors; save to the user config.
- [ ] **Theme presets** (p3) [feature]: presets generated from common color schemes (the 182 base16 schemes
      in fzf-rsc/colors as a start), browsable and previewed in the theme selector.
- [ ] **New-module checklist** (p2) [docs]: what a module ships with now: components, previews and their
      layouts (`FZX_PREVIEW_LAYOUTS`, tuned to its content; done for files, todos, menu, repos, history,
      capture), an icon and its menu color, menu summaries that stay under the timeout, tests. Put it in
      design.md's module contract and CLAUDE.md, then fill the gaps in the existing modules (layouts for
      git, logs, ps, systemd, docker, tmux, man, colors, keybindings).
- [ ] **Popup geometry per module** (p2) [feature]: popup size and position from the module's content and
      purpose, measured against the whole tmux window (`#{window_width}`/`#{window_height}`), not the
      calling pane, since the popup covers split panes. Per-module settings like the preview layouts.
- [ ] **Resize the popup with the window** (p3) [feature]: on `resize`, recompute the popup geometry; fzf
      cannot resize a running popup, so this likely means a relaunch (become with the new --popup options).
- [ ] **Copy feedback in the footer** (p3) [feature]: replace the copy notify-send (fzx actions and ctrl-y/alt-y
      in ~/.fzf/.fzfrc) with a footer message that pops in and clears itself:
      `enter:execute-silent(...)+bell`, `+transform-footer(echo Copied {})`, `+bg-cancel+bg-transform-footer(sleep 1)`.
- [ ] **Summary wording** (p3) [chore]: summaries print "1 buffers", "1 recent searches"; a small plural
      helper for the manifests.

## 3. Keys and help

- [ ] **Several keys per action** (p2) [feature]: fzf takes `key1,key2:action`, but `FZX_KEYS` holds one key per
      action and `fzx::bind` (lib/opts.sh) records the joined string as one help row, so f1, the free keys
      and the "bound twice" check do not see the individual keys. Allow lists in `FZX_KEYS` and split them
      in `fzx::bind`.
- [ ] **Keys from i3, tmux and autokey** (p2) [feature]: scan ~/.config/i3/config, tmux's root table (-n binds;
      the keybindings module already reads tmux) and ~/.config/autokey for keys they take before fzf sees
      them; show them in f1 as their own section, highlighted differently, and keep them out of the free
      keys. A setting chooses whether a remapped key is shown as what it is remapped to or as the original.
- [ ] **Keys grid in f1** (p2) [feature]: an alternate keys layout grouped by modifier prefix, like the free keys
      section (`ctrl-  up down left right home end`, `shift-  ...`), with the used ones highlighted; shift-f1
      opens it instead of the usual page.
- [ ] **Actions menu key toggles back** (p2) [feature]: pressing the actions menu key while in the actions
      menu returns to the screen it was opened from.
- [ ] **ctrl-backspace goes back** (p3) [feature]: bind it with alt-left (needs several keys per action). fzf
      knows `ctrl-bspace` (default: backward-delete-char), but check what the terminal sends: many send ctrl-h
      or plain backspace for it, and binding those would stop backspace deleting query characters.
- [ ] **Key name style** (p3) [feature]: a setting for full key names (`ctrl-x`) or short ones / glyphs
      (`^X`, `⌃X`, `⌥`), after what-key.nvim (~/git/what-key.nvim, ~/.config/nvim/lua/configs/what-key).
- [ ] **Components at the top of the keys page** (p3) [feature]: move the components section of the f1
      keybindings preview to the top.
- [ ] **All keys list** (p3) [feature]: a mode of the keybindings module listing fzf's `--keys` names (every
      key fzf knows), marking the bound ones with their action.
- [ ] **FZX_ variables in the debug views** (p3) [feature]: the preview debug screen (alt-_) and f2 show
      `FZF_*` only in places; list every `FZX_*` parameter in both.

## 4. Core features

- [ ] **Preferred finder and grepper** (p2) [feature]: config values for the file/directory finder and the
      grepper (the user wants `fdfind` and `ripgrep`). In grep mode, a toggle between the query driving the
      grepper (reload per keystroke) and filtering the grepped results within fzf; show which one is active
      (the grep term moves to the header label or after the prompt) and freeze the grep term while in fzf
      search mode (switch back to edit it). A key that puts the grepper/finder arguments into the prompt,
      enter applies them; show the current arguments in the preview's top line or a label.
- [ ] **Preview script upgrade** (p2) [feature] (~/.fzf/core/preview.sh): handle more file types, and report
      which detector and renderer it chose (to fzx's log, or a debug header) so it is clear why content
      looks the way it does. The same detection then serves piping (below): what kind of content is piped in.
- [ ] **Previewer command setting** (p2) [feature]: an env variable / config value for the syntax viewer command
      line (preferred: `nvimpager -c`; default `bat`), plus per-file-type viewers (e.g. a map of glob or mime
      to command). The logic belongs in the preview script (above), with fzx passing the setting through.
- [ ] **Sort by column in every module** (p2) [feature]: sort rows for as many modules as possible (not just
      ps), and highlight the sorted column with `change-nth` plus `--color nth:regular,fg:dim`. ps:tree keeps
      `--no-sort` (its order is the tree); decide whether tree sorts siblings only or disables the sort keys.
- [ ] **Sessions module** (p3) [module]: a picker over `fzx debug ls` that resumes a kept or running session from
      another terminal.
- [ ] **Piping** (p3) [feature]: when stdin is not a tty and no module is given, match each manifest's `detect`
      against the first lines and pick the module (design.md, "Piping").
- [ ] **Completion integration** (p3) [feature]: `**<TAB>` completion (`_fzf_complete_<cmd>`) backed by fzx
      modules for kill, ssh, docker, systemctl, git (fzf-rsc/completions).
- [ ] **fzf sandbox** (p3) [feature]: a mode for trying fzf options live: a target fzf started with `--listen`,
      the sandbox picks options to change and actions to send (POST to the socket), and reads the target's
      event log (a bind on each event writing to a file) to show what fired. Options that cannot change at
      runtime need a wrapper that relaunches the target. A walkthrough mode that steps through fzf's
      CHANGELOG and runs its code examples.

## 5. Module improvements

- [ ] **ps: trace, open files, root processes** (p2) [feature]: from fzf.top.zsh/fztop: strace/ltrace actions
      (errors only, all calls; foreground, ctrl-c returns), the process's open files (lsof -p; or ctrl-o into
      the network module once it exists), and term/kill through sudo for other users' processes (systemd's
      sudo pattern). Refs: widgets/system/fzf.top.zsh, fzf.lsof.zsh, fzf-rsc/modules/system/fztop.
- [ ] **systemd: unit kinds and states** (p2) [feature]: inactive/disabled/static units (list-unit-files) as a
      toggle, timers (next/last run) and sockets as modes, a reload action, sort by state or name. Refs:
      widgets/system/fzf.systemd.zsh (toggles system/user/inactive), fzf-rsc/modules/system/fzsystemd (sysz).
- [ ] **files: search and replace from grep mode** (p3) [feature]: preview and apply a replacement over the
      matches (fzfmenu files/sad).
- [ ] **files: multiline grep** (p3) [feature]: a toggle in `files:grep` for multiline matching
      (`rg -U --multiline-dotall`) that reloads.
- [ ] **git: remote branch delete** (p3) [feature]: drop on a remote-tracking branch pushes the delete
      (`git push REMOTE --delete BRANCH`); left out of 0.18.0 as an outward action.
- [ ] **logs: colored previews** (p3) [feature]: ccze -A or grcat (conf.tail) over log files and journals (both
      installed here), and a unit's `systemctl status` above its journal in the units preview; the preview
      window in follow mode. Refs: widgets/system/logs/logs.preview.sh, logs.fzf.sh.
- [ ] **logs: age dots** (p3) [feature]: a colored dot per log entry showing how recently it was modified
      (the user has this in one of their scripts; get its path to reuse the colors and thresholds).
- [ ] **dirs: bookmark from the list** (p3) [feature]: add and remove bookmarks with keys (fzf-marks' mark/unmark),
      kept in a file under FZX_STATE_DIR instead of only FZX_DIRS_BOOKMARKS in config. Ref: fzf-marks.plugin.zsh.
- [ ] **tmux follow-ups** (p3) [feature]: Codex's list in docs/tmux.md: snippet history (snippetdb), edit the text
      before pasting, open URLs from the urls mode (tmux-url), IPv6 extraction, marked-pane round trips, and
      running a binding from the keys list (run-binding; today rows are never executed, by design).
- [ ] **docker: exec a command** (p3) [feature]: fzf-runinc: exec a typed command (not a shell) in the container,
      output kept on screen; and docker system df as the images/volumes summary. Ref: fzf-rsc/modules/docker.
- [ ] **youtube follow-ups** (p3) [feature]: thumbnails in the preview; after a result is chosen, list its
      formats (`yt-dlp <url> --list-formats`) to pick the download from. The mp3 action
      (`yt-dlp -x --audio-format mp3`) already covers the audio case.
- [ ] **top in ps** (p3) [feature]: a refreshing mode of `ps` (`every(N):reload`) rather than a module.
      Refs: system/fzf.top.zsh, fzf-scripts/fztop.
- [ ] **ps: plain-left PIDs** (p3) [refactor]: since ~/.fzf/.fzfrc dropped its `--delimiter`, the ps source no
      longer needs left-aligned PIDs for `{1}`; right-align them like the other numeric columns.

## 6. New modules

Built from the reference repos in `resources/` (fzfmenu widgets, proto-widgets, vendored widgets and
completers, the fzf attempt's modules, fzf-scripts) and checked against what is installed here
(2026-10-20). "has" lists tools found on PATH, "missing" what the old code used that is not installed.

- [ ] **tasks** (p2) [module]: project scripts, named `project:task` (`musicman:build`, `musicman:run`,
      `audit:lint`), run with execute. Three modes:
      - all: every task found in the git repos (scan ghq/~/git for Makefile, justfile, package.json scripts,
        and similar: Taskfile.yml, Cargo aliases, pyproject scripts);
      - repos: every task of the selected repos;
      - selected: the selected tasks of the selected repos (the default view).
      - A repos view lists the repos found with task definitions; the preview shows that repo's definitions,
        and selecting toggles the repo in or out; tasks are selected the same way from the other modes.
      - The chosen projects persist (state outside the session, e.g. $FZX_STATE_DIR/tasks/projects) and the scan
        is cached (`cache:<ttl>`), since walking every repo is slow.
      - Task preview: the definition itself (the make target's rule, the just recipe, the npm script line).
      Refs: vendors/completers/{make,npm,yarn}.zsh, list.md "asynctasks". Has: just, make, pnpm.
- [ ] **network** (p2) [module]: listening sockets and connections (ss), open files per process (lsof),
      interfaces and routes (ip), wifi networks (nmcli connect), mDNS services (avahi-browse), kill the
      process on a port. Refs: system/fzf.netstat.zsh, system/fzf.lsof.zsh, system/fzwifi, fzf-scripts/wifi,
      avahi-browse.sh, ref/mods/avahi.sh, fzf-rsc/completions/system/kill-proc-by-port.zsh.
      Has: ss, netstat, lsof, ip, nmcli, avahi-browse.
- [ ] **github: issues, PRs, notifications** (p2) [module]: phase 2 of modules/github (search, files and
      fetch shipped in 0.24.0): issues and PRs of the repository here, or involving you elsewhere (view,
      checkout, comment, close), and notifications (open, mark read). Refs: vendors/widgets/fzf-github-*,
      gh-fzf (`gh fzf`), gh-dash's key hints.
- [ ] **github: your repositories and stars** (p3) [module]: phase 3: `mine` (`gh repo list`, toggles for
      private, public, sources and forks; actions: its PRs, issues and workflow runs, fork, `gh repo edit`)
      and `starred` modes; menu summaries for unread notifications and this repository's open PRs and
      issues; emoji shortcodes in descriptions (`:cherry_blossom:`); GitHub's status
      (githubstatus.com) in the menu. From gh-gitman's references (api.sh `repo_cmd`, gh-find-code).
- [ ] **github: search follow-ups** (p3) [feature]: from gh-find-code: a key that narrows a code search to
      the repository under the cursor (`repo:o/r` added to the query), and a toggle that filters the
      results with fzf instead of searching; all rate limits (not only search) in the f2 view.
- [ ] **shell** (p2) [module]: modes for executables on PATH, aliases and shell functions (man/tldr or
      definition preview, the man module's renderer), and environment variables and parameters with values.
      The function and parameter lists come from zsh, so reuse the keybindings module's dump approach
      (shell/fzx.zsh writes them, `zsh -ic` as the fallback). Refs: fzfmenu system/fz-commands,
      system/fz-funcs, system/fzf.params.zsh, vendors/completers/env.zsh. Has: man, tldr.
- [ ] **packages** (p2) [module]: installed and available packages with info preview, install/remove/upgrade
      (sudo in execute): apt/dpkg modes, plus snap, flatpak, pip/pipx, cargo, npm/pnpm globals, gem.
      Refs: packages/fzf.apt.zsh, system/fzapt-{search,rm,up}, ref/mods/apt.sh, fzf-scripts/pkgsearch,
      pkgup, fzaur. Has: apt, dpkg, snap, flatpak, pip, pipx, cargo, pnpm/npm, gem. Missing: brew, aur.
- [ ] **repl** (p2) [module]: live jq/awk/sed/grep/sh filter over a file with the result in the preview
      (`change:reload`). Refs: ref/mods/repl.sh + repl-data, development/fzr-*, fzf/_scratch/repl.*.
      Has: jq, awk, sed. Missing: yq (fzr-yq mode).
- [ ] **pass** (p2) [module]: password-store entries, copy password or a field with a clear timer.
      Refs: system/fzpass.sh, fzpass2.sh, ffpass.sh. Has: pass, gpg, ~/.password-store.
- [ ] **audio** (p2) [module]: pactl/wpctl sinks and sources (set default, volume), playerctl players.
      Refs: widgets/audio/*. Has: pactl, wpctl, playerctl.
- [ ] **music** (p2) [module]: a navigable interface to mpc or musicman (~/ghq/github.com/njhoffman/musicman,
      its cli/), moving forward and back between areas (artists -> albums -> tracks, queue, playlists) as
      child sessions, so back and the cached lists come from the session tree. Play, add, remove as action
      rows; cover/info preview. Earlier attempts in resources/: fzf/modules/music/fmpc,
      fzfmenu/proto-widgets/audio/{fz-mpc,mpc.sh,fmui/mpc.sh}, fzfmenu/ref/mods/mpc.sh,
      fzf-rsc/modules/audio/fz-mpc. Has: mpc, mpd, ncmpcpp.
- [ ] **browser** (p3) [module]: Chrome and Firefox history and bookmarks from their sqlite/JSON files (copy the
      db first, it is locked while the browser runs). Refs: chrome/{history,bookmarks}.sh,
      vendors/widgets/fzf-chrome-history.sh, fzf-bookmarks.{sh,rb}. Has: google-chrome, firefox, sqlite3.
      Missing: buku (chrome/buku*.sh, fzf-scripts/fzbuku).
- [ ] **zsh docs** (p3) [module]: the zsh manual index (option, builtin, parameter) opening the right section;
      possibly a mode of the man module. Refs: fzfmenu system/zman*, zmandata.tsv.
- [ ] **i3** (p3) [module]: windows and workspaces (focus, move), scratchpads. Refs: list.md "i3". Has: i3-msg.
- [ ] **fonts** (p3) [module]: fc-list families with a sample preview; a glyph search mode would have
      helped pick the menu icons. Has: fc-list.
- [ ] **displays** (p3) [module]: xrandr outputs and modes. Has: xrandr.
- [ ] **bluetooth** (p3) [module]: devices (connect, disconnect, pair). Has: bluetoothctl.
- [ ] **cron** (p3) [module]: crontab entries and systemd timers with next run (or a timers mode of systemd).
      Has: crontab, systemctl.
- [ ] **firewall** (p3) [module]: ufw rules. Has: ufw (needs sudo).
- [ ] **ssh** (p3) [module]: hosts from ~/.ssh/config and known_hosts, connect or scp. Refs: vendors/widgets/
      fzf-exec-ssh, system/fzscp, fzf-scripts/sshget. Has: ssh, scp, rsync. No ~/.ssh/config here.
- [ ] **kubernetes** (p3) [module]: contexts, namespaces, pods (logs, exec, describe). Refs: kubectl_fzf.plugin.zsh,
      kubernetes/fz-k, vendors/completers/kubectl.zsh. Has: kubectl. Missing: helm.
- [ ] **aws** (p3) [module]: EC2, ECS, EKS, RDS and CloudWatch logs. Refs: widgets/aws/*. Has: aws. Missing: vault
      (aws-vault.zsh).
- [ ] **versions** (p3) [module]: asdf plugins and installed versions. Refs: system/asdf*, fzasdf-plugins. Has: asdf.
- [ ] **llm** (p3) [module]: ollama models (list, pull, rm). Has: ollama.
- [ ] **tasks-personal** (p3) [module]: taskwarrior tasks and calcurse appointments. Has: task, calcurse.
- [ ] **web search** (p3) [module]: DuckDuckGo, GitHub, Stack Overflow queries opening in the browser.
      Refs: fz-surfraw.sh, fzf-scripts/ddgsearch, ref/mods/stack.sh, wiki.sh. Missing: surfraw.
- [ ] **emoji** (p3) [module]: emoji and gitmoji picker, copy or insert. Refs: fz-emoji.sh, other/fz-gitmoji.
- [ ] **torrents** (p3) [module]: transmission queue. Refs: other/transmission.zsh. Missing: transmission-remote.

## 7. Known issues

- [ ] **Menu `applicable` runs synchronously** (p2) [perf] for every entry on every open; one slow check slows the
      menu. Log per-module timing, or time-box it like summaries.
- [ ] **Untested against the real thing** (p2) [test]: docker (stubbed only), systemd start/stop/enable (stubbed
      systemctl and sudo), Zellij popups (tmux only).
- [ ] **Slow suite** (p2) [test]: about 500 tests take several minutes serially; `bats -j` needs GNU parallel
      (this machine has the moreutils `parallel`). Install it or run files in parallel from the Justfile.
- [ ] **Undocumented fzf behaviour we depend on** (p3) [test]: `become()` inside a `--popup` runs in the original
      terminal, so every launch re-requests the popup (`fzx::_placement`). Observed on fzf 0.74 (devel);
      re-check on every fzf upgrade with the popup test in design.md's popout notes.
- [ ] **Log rotation** (p3) [bug]: `$XDG_STATE_HOME/fzx/fzx.log` is never rotated or pruned (260K after a week at
      the info level); add it to `fzx gc` like the stats file.
- [ ] **grep mode stats noise** (p3) [bug]: every keystroke in `files:grep` records a `source reload` row;
      record live-search reloads as their own event or not at all.
- [ ] **tmux formats screen is slow** (p3) [perf]: `fzx -m tmux:formats` takes 1-7s on the main server: one
      `display-message` per template (21 here), each running the status line's `#(...)` jobs. Joining the
      templates into one `display-message` mis-splits (tmux's parser runs across them), and a `;` command
      sequence of display-messages also came back short; find out why (modules/tmux/reference.py
      `tmux_sequence`), or skip `#(...)` when rendering samples.
- [ ] **Float is two cells smaller than a popup** (p3) [bug]: for the same spec (`center,80%` in a 200x49
      window) the fzf popup's content is 160x39 and the float's is 158x37, because `fzx::float_geometry` gives
      new-pane the outer size and the border takes a cell on each side. Add the border to the size (clamped
      to the window) so cycling popup -> float does not shrink the list.
- [ ] **`files` alt-up** (p3) [bug]: each parent directory becomes a new child session instead of reusing an
      existing ancestor in the tree; harmless (cleaned on exit) but deep trees and long labels.
- [ ] **`persist=none` sources have no item count** (p3) [bug] in stats (output streams straight to fzf).
- [ ] **Exit row missing** (p3) [bug] when the terminal is killed (SIGHUP); the dead tree is swept by gc but
      the run never gets an `exit` stat.
- [ ] **Stats prune** (p3) [bug] can drop rows appended while the file is being rewritten.
- [ ] **`fzx stats` needs `strftime` in awk** (p3) [bug] (gawk, or mawk 1.3.4+).

## 8. Outside this repo

- [ ] **Retire todo-fzf** (p3) [chore]: once fzx todos has been in daily use, drop the todo-fzf fallback
      from /todo-pop, `todo.pop` and Alt-i and remove ~/.shell/scripts/todo-fzf with its tests. Kept for
      now at the user's request (2026-10-26).
- [ ] **prettypath follow-ups** (p3) [chore] (~/git/prettypath): moved to ~/git/prettypath/TODO.md (speed,
      `--base`, `--dirs`, a field of tabbed input, NO_COLOR, packaging bugs). When `--base` and `--dirs` land,
      drop fzx::pretty's prefix-strip awk and slash sed; when stat is automatic, drop `--stat_file=false`.
- [ ] **Global CLAUDE.md test command** (p3) [docs]: `~/.claude/CLAUDE.md` says to run `npm run test` before
      commits; this repo uses `just test` (bats). "Run the project's test command" fits all repos.
