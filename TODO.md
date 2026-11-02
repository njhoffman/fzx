# fzx TODO

Status (0.60.0): the six steps of `docs/design.md` are done. Modules: actions, audio, capture, colors, dirs,
docker, files, git, github, glyphs, history, keybindings, logs, man, menu, network, ps, recent, repos, shell, systemd, tasks, tmux,
todos, youtube; zsh widgets in `shell/fzx.zsh`. What has shipped is in CHANGELOG.md, so ticked items are removed
here once they are released. Keep this file current: tick items off, add what you find.

Every item carries a priority in its first line, `(p1)` high, `(p2)` normal or `(p3)` low, and a
category: `[bug]` `[feature]` `[refactor]` `[docs]` `[test]` `[chore]` `[perf]`, plus this repo's own below.
`(due YYYY-MM-DD)` adds a date and an OVERDUE flag. `/todo` (`~/.shell/scripts/todo-status`) and `/todo-pop`
(`fzx -m todos`) sort and mark by them; `todo-status --check` lists untagged items.

Categories: module

Reviewed: 2026-10-28

## 1. Next up

## 2. Menu and presentation

- [ ] **Theme selector** (p2) [feature]: building on `colors:fzx`, a screen listing every color setting
      (fzf's `--color` keys and fzx's `FZX_COLORS`) with their current values; pick one, change it
      interactively, and see it in a live sample fzf launched with the new colors; save to the user config.
- [ ] **Theme presets** (p3) [feature]: presets generated from common color schemes (the 182 base16 schemes
      in fzf-rsc/colors as a start), browsable and previewed in the theme selector.
- [ ] **Floats follow the window** (p3) [feature]: popups are reopened on a window resize (`fzx _resized`,
      `nav relayout`); a float keeps its first size. `tmux resize-pane -x/-y` plus a move to the new
      position (if new-pane floats can be moved) would do it without a relaunch.
- [ ] **Summary wording** (p3) [chore]: summaries print "1 buffers", "1 recent searches"; a small plural
      helper for the manifests.

## 3. Keys and help

- [ ] **Keys from i3, tmux and autokey** (p2) [feature]: scan ~/.config/i3/config, tmux's root table (-n binds;
      the keybindings module already reads tmux) and ~/.config/autokey for keys they take before fzf sees
      them; show them in f1 as their own section, highlighted differently, and keep them out of the free
      keys. A setting chooses whether a remapped key is shown as what it is remapped to or as the original.
- [ ] **ctrl-backspace goes back** (p3) [feature]: bind it with alt-left (`FZX_KEYS[back]="alt-left,ctrl-bspace"`). fzf
      knows `ctrl-bspace` (default: backward-delete-char), but check what the terminal sends: many send ctrl-h
      or plain backspace for it, and binding those would stop backspace deleting query characters.
- [ ] **All keys list** (p3) [feature]: a mode of the keybindings module listing fzf's `--keys` names (every
      key fzf knows), marking the bound ones with their action.

- [x] **ctrl-_ for the next sort** (p3) [feature]: bound with f12 (`FZX_KEYS[sort_next]="f12,ctrl-_"`; fzf
      calls it ctrl-/, terminals send ctrl-_ for both).
- [ ] **alt-^ flips popup and inline** (p3) [feature]: a second placement key that switches only between the
      popup and the plain terminal, skipping split and float (ctrl-^, `FZX_KEYS[popout]`, keeps the full cycle).
      Check what the terminal sends for alt-shift-6 and that fzf accepts `alt-^`.

## 4. Core features

- [ ] **Grepper and finder arguments in the prompt** (p2) [feature]: in files (grep and the finder modes), a
      key that puts the rg/fd arguments into the query, enter applies them; show the current arguments in
      the preview's top line or a label. Prior art: resources/ (older setups). Grep mode's switch between
      grepping and fzf filtering (ctrl-t) shipped in 0.40.0; fd and ripgrep are already the tools used.
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
- [ ] **github: octo.nvim styling** (p3) [feature]: borrow from pwntester/octo.nvim's look: more icons
      (state, review, draft, merged), labels drawn as colored chips, nicer issue/PR rows and previews.
- [ ] **top in ps** (p3) [feature]: a refreshing mode of `ps` (`every(N):reload`) rather than a module.
      Refs: system/fzf.top.zsh, fzf-scripts/fztop.
- [ ] **ps: plain-left PIDs** (p3) [refactor]: since ~/.config/fzf/fzfrc dropped its `--delimiter`, the ps source no
      longer needs left-aligned PIDs for `{1}`; right-align them like the other numeric columns.

## 6. New modules

Built from the reference repos in `resources/` (fzfmenu widgets, proto-widgets, vendored widgets and
completers, the fzf attempt's modules, fzf-scripts) and checked against what is installed here
(2026-10-20). "has" lists tools found on PATH, "missing" what the old code used that is not installed.

- [ ] **github: header after the everywhere toggle** (p3) [bug]: the issues and prs header is set when fzf
      starts ("issues of o/r ..."), so after alt-7 it still names the repository while the list shows
      everything involving you. Toggles reload in place with no header hook; the fix is a toggle flag or
      change-header in the reload (lib/opts.sh).
- [x] **shell** (p2) [module]: modes for executables on PATH, aliases and shell functions (man/tldr or
      definition preview, the man module's renderer), and environment variables and parameters with values.
      Done in 0.37.0 (modules/shell).
- [ ] **packages** (p2) [module]: installed and available packages with info preview, install/remove/upgrade
      (sudo in execute): apt/dpkg modes, plus snap, flatpak, pip/pipx, cargo, npm/pnpm globals, gem.
      Refs: packages/fzf.apt.zsh, system/fzapt-{search,rm,up}, ref/mods/apt.sh, fzf-scripts/pkgsearch,
      pkgup, fzaur. Has: apt, dpkg, snap, flatpak, pip, pipx, cargo, pnpm/npm, gem. Missing: brew, aur.
- [ ] **repl** (p2) [module]: live jq/awk/sed/grep/sh filter over a file with the result in the preview
      (`change:reload`). Refs: ref/mods/repl.sh + repl-data, development/fzr-*, fzf/_scratch/repl.*.
      Has: jq, awk, sed. Missing: yq (fzr-yq mode).
- [ ] **pass** (p2) [module]: password-store entries, copy password or a field with a clear timer.
      Refs: system/fzpass.sh, fzpass2.sh, ffpass.sh. Has: pass, gpg, ~/.password-store.
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
- [ ] **fonts** (p3) [module]: fc-list families with a sample preview. Has: fc-list.
- [ ] **displays** (p3) [module]: xrandr outputs and modes. Has: xrandr.
- [ ] **bluetooth** (p3) [module]: devices (connect, disconnect, pair). Has: bluetoothctl.
- [ ] **cron** (p3) [module]: crontab entries with their next run (systemd timers: the systemd module's timers mode).
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

- [ ] **menu_scores test flakes under load** (p3) [test]: test/menu.bats "menu_scores: launches by module ..."
      stamps rows "now minus N days" and compares the decayed scores to six decimals; under the parallel suite
      a second's delay gives 0.999999 (seen 2026-11-01, passes alone). Compare rounded to 3 decimals.
- [ ] **Zellij popups untested** (p3) [test]: popups are only checked on tmux; zellij is not installed here.
- [ ] **Undocumented fzf behaviour we depend on** (p3) [test]: `become()` inside a `--popup` runs in the original
      terminal, so every launch re-requests the popup (`fzx::_placement`). Observed on fzf 0.74 (devel);
      re-check on every fzf upgrade with the popup test in design.md's popout notes.
- [ ] **grep mode stats noise** (p3) [bug]: every keystroke in `files:grep` records a `source reload` row;
      record live-search reloads as their own event or not at all.
- [ ] **tmux formats screen is slow** (p3) [perf]: `fzx -m tmux:formats` takes 1-7s on the main server: one
      `display-message` per template (21 here), each running the status line's `#(...)` jobs. Joining the
      templates into one `display-message` mis-splits (tmux's parser runs across them), and a `;` command
      sequence of display-messages also came back short; find out why (modules/tmux/reference.py
      `tmux_sequence`), or skip `#(...)` when rendering samples.
- [ ] **`files` alt-up** (p3) [bug]: each parent directory becomes a new child session instead of reusing an
      existing ancestor in the tree; harmless (cleaned on exit) but deep trees and long labels.
- [ ] **Stats prune** (p3) [bug] can drop rows appended while the file is being rewritten.
- [ ] **`fzx stats` needs `strftime` in awk** (p3) [bug] (gawk, or mawk 1.3.4+).
- [ ] **man preview fails on `[`** (p3) [bug]: the first row of `fzx -m man`, `[ (1)`, logs
      `cb preview [(1) rc=16` and shows nothing; the page name needs quoting or `--` (modules/man/preview.sh).
- [ ] **nvcat is slow for previews** (p3) [perf]: about 300-1200ms per focus change (it starts Neovim), for
      markdown and every filetype `nvcat-dispatch` claims (any *.conf, systemd units, ...); files over
      FZX_PREVIEW_NVCAT_MAX_LINES already go to bat. Cache its output under $FZX_CACHE_DIR keyed by path,
      mtime and width (lib/render.sh, fzx::_render_nvcat), or keep one Neovim running.
- [ ] **Actions menu marks run as default under `tasks --paste`** (p3) [bug]: with `--paste` enter pastes
      (the module binds it, lib/actions.sh skips the default's enter), but the actions menu still draws ⏎ on
      `run` since it reads the flags from `meta/components`. Record the override in the session (a meta key)
      and drop the mark (modules/actions/source.sh).
- [ ] **tasks: multi-line just docs show their last line** (p3) [bug]: `just --dump` keeps only the comment
      line right above a recipe, so a two-line comment shows its tail (`lint`: "idioms trip most checks)").
      Read the comment block from the justfile instead (modules/tasks/source.sh, tasks::scan).
- [ ] **No README** (p3) [docs]: the repo has CLAUDE.md, PLAN.md and docs/, but nothing a new reader lands on:
      what fzx is, install (`just install`, sourcing shell/fzx.zsh), the module list, where docs live.
- [ ] **PLAN.md is the original brief** (p3) [docs]: the 106-line prompt that started the project, now covered by
      docs/design.md; move it to docs/ as history (or drop it) so it is not read as the current plan.

## 8. Outside this repo

- [ ] **prettypath follow-ups** (p3) [chore] (~/git/prettypath): moved to ~/git/prettypath/TODO.md (speed,
      `--base`, `--dirs`, a field of tabbed input, NO_COLOR, packaging bugs). When `--base` and `--dirs` land,
      drop fzx::pretty's prefix-strip awk and slash sed; when stat is automatic, drop `--stat_file=false`.
