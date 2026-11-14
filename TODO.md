# fzx TODO

Status (0.114.1): the six steps of `docs/design.md` are done. Modules: actions, applications, audio, aws, bluetooth, browser, capture, claude, colors, cron, dirs,
docker, files, firewall, fonts, git, github, glyphs, history, kdeconnect, keybindings, logs, man, menu, music, network, packages, ps, recent, repos, sessions, shell, systemd, tasks, tmux,
todos, youtube; zsh widgets in `shell/fzx.zsh`. What has shipped is in CHANGELOG.md. Keep this file current:
add what you find, and tick items off (`- [x]`) as they land, never delete them; once every item of a section
is ticked, the section moves to `## Completed` at the end as a `### <heading> (completed YYYY-MM-DD)` block
and its heading leaves the open part. Only items dropped undone are deleted.

Every item carries a priority in its first line, `(p1)` high, `(p2)` normal or `(p3)` low, and a
category: `[bug]` `[feature]` `[refactor]` `[docs]` `[test]` `[chore]` `[perf]`, plus this repo's own below.
`(due YYYY-MM-DD)` adds a date and an OVERDUE flag. `/todo` (`~/.shell/scripts/todo-status`) and `/todo-pop`
(`fzx -m todos`) sort and mark by them; `todo-status --check` lists untagged items.

Categories: module

Reviewed: 2026-11-11

## 1. Next up

## 2. Menu and presentation

- [ ] **Theme selector** (p2) [feature]: building on `colors:fzx`, a screen listing every color setting
      (fzf's `--color` keys and fzx's `FZX_COLORS`) with their current values; pick one, change it
      interactively, and see it in a live sample fzf launched with the new colors; save to the user config.
- [ ] **Theme presets** (p3) [feature]: presets generated from common color schemes (the 182 base16 schemes
      in fzf-rsc/colors as a start), browsable and previewed in the theme selector.
- [x] **Floats follow the window** (p3) [feature]: popups are reopened on a window resize (`fzx _resized`,
      `nav relayout`); a float keeps its first size. `tmux resize-pane -x/-y` plus a move to the new
      position (if new-pane floats can be moved) would do it without a relaunch.
- [x] **Summary wording** (p3) [chore]: summaries print "1 buffers", "1 recent searches", and the newer
      "1 entries" (cron, git reflog), "1 profiles" (firewall), "1 stars", "1 stashes", "1 scripts"; a small
      plural helper for the manifests (about 20 printf lines under modules/*/manifest.sh).

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

## 4. Core features

- [x] **Grepper and finder arguments in the prompt** (p2) [feature]: in files (grep and the finder modes), a
      key that puts the rg/fd arguments into the query, enter applies them; show the current arguments in
      the preview's top line or a label. Prior art: resources/ (older setups). Grep mode's switch between
      grepping and fzf filtering (ctrl-t) shipped in 0.40.0; fd and ripgrep are already the tools used.
- [x] **Refresh hook: bindings too** (p3) [refactor]: `FZX_REFRESH_CHANGE` (0.83.0) rebinds or unbinds the
      change event, so `packages:search` switches in place. `files:grep` stays a restart: its rows have a
      line field the other modes lack, and fzf 0.74 cannot change `--with-nth` or `--accept-nth` while it
      runs; ps:top and ps:tree stay restarts too (the refresh loop, sorting).
- [x] **sessions: resumed trees in a pane** (p3) [feature]: a kept tree resumed from the sessions list runs
      under the list's owner, not its own, so a placement change into or out of a split or float (which needs
      the tree's owner to relaunch) only works in the list's own placement. Handing the tree to the list's
      owner (it relaunches `state/current` of the resumed root) would let it move like any other.
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

- [x] **git: the dotfiles repository** (p2) [feature]: the git module over dotbare's bare repository (`~/.cfg`,
      work tree `~`) through `--git-dir`/`--work-tree` arguments, with a menu entry where `~/.cfg` exists;
      status limited to tracked files (dotbare's `status.showUntrackedFiles no`). dotbare is installed here
      (~/.dotbare) and is how ~/.config projects are versioned.
- [x] **git: grep, reset and clean** (p3) [feature]: a `git grep` mode (as files:grep, over the index or a
      commit), reset to the selected commit (soft, mixed; hard only with FZX_GIT_DESTRUCTIVE=1) and clean
      of untracked files with a dry-run preview. Refs: fzfmenu/proto-widgets/git/fzg-grep, fzg-reset, fzg-clean.
- [x] **dirs: bookmark from the list** (p3) [feature]: add and remove bookmarks with keys (fzf-marks' mark/unmark),
      kept in a file under FZX_STATE_DIR instead of only FZX_DIRS_BOOKMARKS in config. Ref: fzf-marks.plugin.zsh.
- [ ] **snippets and paste history** (p3) [feature]: both kinds: an automatic history of what capture and tmux
      buffers paste (newest first, under FZX_STATE_DIR), and named snippets saved on purpose (snippetdb's
      put/get/remove/list). Open: a capture mode, or a module of its own that the zsh widgets can use
      outside tmux too. Ref: resources/fzfmenu/proto-widgets/tmux/snippetdb.
- [x] **Test fzx::pretty against a real prettypath** (p3) [test]: test/pretty.bats runs every case against a
      stub that reimplements prettypath's `--base`, `--dirs` and `--field` by hand, so a change in prettypath
      (or a stub that drifts from it) goes unnoticed. Add a few cases that use the installed prettypath when
      `prettypath --version` is 0.2.0 or later (skipped otherwise): fzx::pretty with a base and `--dirs`, and
      fzx::pretty_field on a row with a trailing-"/" path, checked with the escapes stripped.
- [x] **Drop support for prettypath before 0.2.0** (p3) [refactor]: lib/pretty.sh keeps three paths (current,
      sound, legacy): the slash sed, the prefix-strip awk, the plain-display fallback and the join in
      fzx::pretty_field exist only for prettypath 0.1.x and older, with their tests and stub modes. Once no
      machine runs one, require 0.2.0 (a `legacy` level shows plain displays and logs why) and remove them.
- [x] **design.md quotes old prettypath speeds** (p3) [docs]: docs/design.md gives "about 13µs per path
      (20k paths in 0.26s)", measured on prettypath under lua 5.1 before 0.1.0. Under luajit (prettypath
      0.3.0's launcher) `make bench` there shows about 3-4µs per path for the default format. Update the
      figure or drop it in favor of pointing at prettypath's `make bench`.

## 6. New modules

Built from the reference repos in `resources/` (fzfmenu widgets, proto-widgets, vendored widgets and
completers, the fzf attempt's modules, fzf-scripts) and checked against what is installed here
(2026-10-20; tools rechecked 2026-11-03). "has" lists tools found on PATH, "missing" what the old code used that is not installed.

- [ ] **repl** (p2) [module]: live jq/awk/sed/grep/sh filter over a file with the result in the preview
      (`change:reload`). Refs: ref/mods/repl.sh + repl-data, development/fzr-*, fzf/_scratch/repl.*.
      Has: jq, awk, sed. Missing: yq (fzr-yq mode).
- [ ] **pass** (p2) [module]: password-store entries, copy password or a field with a clear timer.
      Refs: system/fzpass.sh, fzpass2.sh, ffpass.sh. Has: pass, gpg, ~/.password-store.
- [x] **browser** (p3) [module]: Chrome and Firefox history and bookmarks from their sqlite/JSON files (copy the
      db first, it is locked while the browser runs). Refs: chrome/{history,bookmarks}.sh,
      vendors/widgets/fzf-chrome-history.sh, fzf-bookmarks.{sh,rb}. Has: google-chrome, firefox, sqlite3.
      Missing: buku (chrome/buku*.sh, fzf-scripts/fzbuku). Open tabs too (fzfmenu list.md "chrome:tabs"):
      Chrome only lists them through its remote debugging port (`--remote-debugging-port`, /json).
- [ ] **zsh docs** (p3) [module]: the zsh manual index (option, builtin, parameter) opening the right section;
      possibly a mode of the man module. Refs: fzfmenu system/zman*, zmandata.tsv.
- [ ] **i3** (p3) [module]: windows and workspaces (focus, move), scratchpads. Refs: list.md "i3". Has: i3-msg.
- [x] **applications** (p3) [module]: desktop entries (/usr/share/applications and ~/.local/share/applications,
      489 here) by name with their icon and categories, launched detached (`gtk-launch` or the Exec line); for
      launching from a tmux popup bound in i3. Ref: zaw's applications.
- [ ] **gpg keys** (p3) [module]: public and secret keys (`gpg --list-keys --with-colons`, 44 here): copy the
      fingerprint, export armored, edit trust, delete (confirm). Ref: fzfmenu list.md "pgp". Has: gpg.
- [x] **fonts** (p3) [module]: fc-list families with a sample preview. Has: fc-list.
- [ ] **displays** (p3) [module]: xrandr outputs and modes. Has: xrandr.
- [x] **bluetooth: background scan** (p3) [feature]: the scan action blocks for `FZX_BLUETOOTH_SCAN_SECONDS`
      and lists its finds after. A scan kept running while the all mode shows (`bluetoothctl scan on` in the
      background, a reload as `InterfacesAdded` arrives through `busctl monitor`, stopped when fzf leaves the
      mode or exits) would show devices as they appear.
- [x] **cron: system entries through sudo** (p3) [feature]: disable and run-now act on your crontab only.
      Commenting a line of /etc/cron.d out through `sudo sed`, and running an entry as its user with cron's
      environment (`sudo -u USER env -i SHELL=/bin/sh HOME=... sh -c`), would cover the system's too.
- [x] **cron: CRON_TZ and other users' crontabs** (p3) [feature]: next runs ignore `CRON_TZ=` lines, and
      only your crontab is read; with a cached sudo, /var/spool/cron/crontabs holds every user's.
- [x] **browser: open tabs** (p3) [feature]: Chrome lists its tabs only through the remote debugging port
      (`/json`), and since Chrome 136 `--remote-debugging-port` does nothing on the default user data dir
      (it is set here, and 9222 does not answer): it needs Chrome started with `--user-data-dir` too. Firefox
      keeps open tabs in sessionstore-backups/recovery.jsonlz4 (mozlz4: an lz4 block with a magic header,
      which needs a decoder such as python's lz4).
- [x] **applications: desktop actions** (p3) [feature]: the preview lists an entry's `[Desktop Action]`
      groups (New Window, New Private Window), but neither gtk-launch nor dex starts one. Running the
      action's Exec line (field codes %f %u %F %U removed, %i %c %k expanded) from a second list would.
- [x] **applications: TryExec and OnlyShowIn** (p3) [feature]: entries whose TryExec is not installed and
      those `OnlyShowIn`/`NotShowIn` excludes from this desktop are listed; the spec hides both.
- [x] **firewall: add rules** (p3) [feature]: rules come only from profiles (alt-a, alt-D). A prompt for a
      free rule (`allow 8080/tcp from 192.168.1.0/24`, readline as docker's alt-E has, checked with
      `ufw --dry-run`) would add any rule; inserting at a position (`ufw insert N`) from the focused row too.
- [ ] **ssh** (p3) [module]: hosts from ~/.ssh/config and known_hosts, connect or scp. Refs: vendors/widgets/
      fzf-exec-ssh, system/fzscp, fzf-scripts/sshget. Has: ssh, scp, rsync. No ~/.ssh/config here.
- [ ] **kubernetes** (p3) [module]: contexts, namespaces, pods (logs, exec, describe). Refs: kubectl_fzf.plugin.zsh,
      kubernetes/fz-k, vendors/completers/kubectl.zsh. Has: kubectl. Missing: helm.
- [x] **aws: EC2 and log groups** (p3) [module]: `fzx -m aws[:logs]`, read-only: lists, previews, console output,
      following a log group, the JSON, the console page.
- [x] **aws: ECS, EKS and RDS** (p3) [module]: `fzx -m aws:ecs`, `aws:eks`, `aws:rds`, read-only.
- [x] **aws: the rest of the old widgets** (p3) [module]: EBS volumes, VPCs, subnets, security groups, RDS and
      ElastiCache subnet groups, ElastiCache clusters, the profile picker with aws-vault, and EC2 start, stop and
      reboot behind confirm. RDS security groups left out: DB security groups belong to EC2-Classic, which AWS retired.
- [x] **aws: rows unchecked on real resources** (p3) [test]: every list, preview and JSON action, EC2 console output,
      stop and start with the confirmation, and the profile picker ran against real resources (2026-11-03).
- [ ] **aws: console links and aws-vault unchecked** (p3) [test]: no alt-O URL has been opened (the check needs a
      signed-in browser; the ElastiCache and subnet group pages are the likeliest to be wrong). aws-vault is not
      installed, so its listing, exec and login have run only against a stub, and exec may prompt for MFA inside a
      callback. EKS node group names too: the test cluster had none, so only "no node groups" ran for real.
- [x] **aws: log group preview is slow** (p3) [perf]: two CLI calls per focus change, about 2.5s, most of it the
      CLI's own startup (modules/aws/preview.sh). Answers are kept in the session for FZX_AWS_PREVIEW_TTL seconds.
- [x] **kdeconnect** (p3) [module]: `fzx -m kdeconnect[:notifications|:commands]`: devices with their battery,
      notifications, remote commands; ping, ring, share, text, clipboard, keys, SMS, lock, pair.
- [ ] **kdeconnect: the chat watcher test fails under load** (p3) [test]: test/kdeconnect.bats "chat watcher: a
      reload for each change in its thread" saw fewer than 4 posts in a full parallel run at load ~30 (passes
      alone, even at load 43). Wait for the posts with a bounded poll instead of a fixed sleep.
- [ ] **kdeconnect: actions unchecked on a real device** (p3) [test]: ping, shared text and the lists ran against a
      Galaxy Z Fold7 (2026-11-03). Only stubbed: ring, clipboard, share of a file, keys, sending an SMS, dismiss, pair
      and unpair, which reach the phone or a person. Lock, unlock and commands need a device with lockdevice and
      remotecommands (a desktop's KDE Connect): this phone has neither, and the commands' format is from memory of
      kdeconnect-cli's source.
- [ ] **llm** (p3) [module]: ollama models (list, pull, rm). Has: ollama.
- [ ] **tasks-personal** (p3) [module]: taskwarrior tasks and calcurse appointments. Has: task, calcurse.
- [ ] **web search** (p3) [module]: DuckDuckGo, GitHub, Stack Overflow queries opening in the browser.
      Refs: fz-surfraw.sh, fzf-scripts/ddgsearch, ref/mods/stack.sh, wiki.sh. Missing: surfraw.
- [ ] **emoji** (p3) [module]: emoji and gitmoji picker, copy or insert. Refs: fz-emoji.sh, other/fz-gitmoji.
- [ ] **torrents** (p3) [module]: transmission queue. Refs: other/transmission.zsh. Missing: transmission-remote.

## 7. Known issues

- [x] **test/tmux.bats left two tmux servers running** (p3) [test]: on 2026-11-12, two servers from a run about 32h
      earlier were still up (`tmux -S /tmp/bats-run-qc5pKA/test/983/tmux.sock` and `.../985/`, session `first`
      from `setup()`), their test directories already deleted. `teardown()` does run `tmux kill-server` through the
      stub, so the cause is unconfirmed: the run may have been interrupted between setup and teardown, or a test
      may point the stub at another socket. Have setup record the server PID and teardown kill it if
      `kill-server` left it running.

- [x] **just lint takes two minutes** (p3) [perf]: the Justfile's lint runs one shellcheck over about 250 files, each
      re-reading what it sources, on one core (115s at 0.108.6, 2026-11-10; each file alone takes 0.1-0.4s). Run it
      in parallel batches (`printf '%s\0' "${files[@]}" | xargs -0 -P"$(nproc)" -n 16 shellcheck`), keeping one
      exit status for CI.
- [ ] **A split-pane menu that would not close** (p2) [bug]: on 2026-11-10 a split (`todos:here`, then
      nav goto `menu:list`; lib/run.sh fzx::_fzf_pane) stayed open about 52 minutes until
      its pane was killed by hand; the keys tried are unknown. Not a test: it ran under the real runtime dir and
      history. In the pane fzx execs fzf, so any fzf exit should end it.
      Found live (0.110.1): esc from the menu in a split while its summaries still ran left the pane blank,
      the terminal cooked and keys echoed for 3-5s (the refresh kept running beside the next screen): fixed,
      the refresh now runs in its own group and leaving the menu stops it (1.6s+2s down to 50ms+170ms).
      Not reproduced: a pane stuck for good; every run recovered. The fzf found was the menu's own, alive,
      so keys may not have reached it (focus back in the Claude pane next to it?). Still open: ask what was
      pressed when it happens again; check `tmux display -p '#{pane_active}'` on the split.
- [x] **design.md: broken table under Reloading and navigation** (p3) [docs]: docs/design.md:119-122 has two
      header rows, a stale two-column one above the three-column one, so the table renders wrongly. Delete lines
      119-120.
- [x] **Prompts typed under fzx go to the log** (p2) [bug]: lib/callback.sh:23 sends every action's stderr to the log,
      and `read -e -p` draws its prompt and echoes typing on stderr. Every prompt now goes through `fzx::tty_read`
      (lib/core.sh), a test refuses a bare one, and real errors still reach the log.
- [x] **kdeconnect: read SMS conversations** (p3) [feature]: `fzx -m kdeconnect:sms`, read-only: threads with contacts'
      names, messages in the preview by D-Bus signal, kept in memory only.
- [x] **kdeconnect: reply to a conversation** (p3) [feature]: the sms mode reads only. `replyToConversation` (xsav) on
      the conversations interface handles groups, which `--send-sms` does not; confirm like the SMS action.
- [x] **The flag `off` cannot remove alt-y** (p3) [bug]: docs/design.md says it removes a built-in, and the menu and actions
      modules set it for copy-line, but lib/opts.sh:478 binds alt-y whenever no row has it, so `fzx -m menu` still copies
      lines. Either bind it only for modules that did not switch it off, or say in the docs that the key stays.
- [x] **Timing-sensitive tests under load** (p3) [test]: test/menu.bats "menu_scores: launches by module ..."
      stamps rows "now minus N days" and compares the decayed scores to six decimals; under the parallel suite
      a second's delay gives 0.999999 (seen 2026-11-01, passes alone): compared rounded to 3 decimals since
      0.83.0. The same
      class hit test/modules.bats's applicability test (the 2s FZX_APPLICABLE_TIMEOUT, fixed in 0.77.1 with a
      longer one), and menu.bats's "modules are listed at once" (0.79.0: a 6s timeout); look for other tests that
      run the menu's summary or applicable timeouts and raise theirs.
- [x] **firewall: header with nothing added** (p3) [bug]: with ufw off the header says "rules added, not in
      effect" even when `ufw show added` lists none; say it only when there are some.
- [x] **Undocumented fzf behaviour we depend on** (p3) [test]: `become()` inside a `--popup` runs in the original
      terminal, so every launch re-requests the popup (`fzx::_placement`). Observed on fzf 0.74 (devel);
      re-check on every fzf upgrade with the popup test in design.md's popout notes.
- [x] **grep mode stats noise** (p3) [bug]: every keystroke in `files:grep` records a `source reload` row;
      record live-search reloads as their own event or not at all.
- [x] **tmux formats screen is slow** (p3) [perf]: `fzx -m tmux:formats` takes 1-7s on the main server: one
      `display-message` per template (21 here), each running the status line's `#(...)` jobs. Joining the
      templates into one `display-message` mis-splits (tmux's parser runs across them), and a `;` command
      sequence of display-messages also came back short; find out why (modules/tmux/reference.py
      `tmux_sequence`), or skip `#(...)` when rendering samples.
- [x] **`files` alt-up** (p3) [bug]: each parent directory becomes a new child session instead of reusing an
      existing ancestor in the tree; harmless (cleaned on exit) but deep trees and long labels.
- [x] **Stats prune** (p3) [bug] can drop rows appended while the file is being rewritten.
- [ ] **nvcat is slow for previews** (p3) [perf]: about 300-1200ms per focus change (it starts Neovim), for
      markdown and every filetype `nvcat-dispatch` claims (any *.conf, systemd units, ...); files over
      FZX_PREVIEW_NVCAT_MAX_LINES already go to bat. Cache its output under $FZX_CACHE_DIR keyed by path,
      mtime and width (lib/render.sh, fzx::_render_nvcat), or keep one Neovim running.
- [x] **files: the flags label falls off long paths** (p3) [bug]: the header shows the extra rg/fd flags
      (alt-a, 0.110.0) as "  rg: FLAGS" after the base path, so on a long path the label is cut off at the
      terminal's edge and the flags in effect are hidden. Put the label before the path, or shorten the
      path first.
- [ ] **files: a refused flag does not say why** (p3) [feature]: the flags screen (modules/files/actions.sh)
      rings the bell and names the refused flag in the header, but not the reason (not on the FILES_FLAGS_RG
      or FILES_FLAGS_FD whitelist, which keeps out flags that change the output format fzx parses, or a
      value missing). Add the reason and, for an unknown flag, the nearest allowed one.
- [x] **CI never runs the real-prettypath tests** (p3) [test]: test/pretty.bats's "real prettypath" cases
      (0.111.0) skip without prettypath 0.2.0 or later, and CI does not install it, so only local runs catch
      a prettypath change that breaks the displays. Install it in .github/workflows/ci.yml (luarocks, or
      the repo's launcher), pinned like just.

- [x] **fzf-tab: I or O in the query on a pane switch** (p2) [bug]: `fzx-run` only covered fzx's widgets; fzf from
      any other widget kept the shell's focus reporting on. `fzf` in `shell/fzx.zsh` now does the same around it.
- [x] **github: trees never get a prettypath display** (p3) [bug]: modules/github/source.sh sends tree paths
      with a trailing "/" (so prettypath shows the folder icon) and joins the result back by that key, but
      prettypath's `%path%` drops the slash, so `key in shown` never matches a tree and every directory keeps
      the plain display. Strip the slash from the join key (as recent does with `sub(/\/$/, "", path)`).
- [ ] **Focus guard misses fzf started outside the function** (p3) [bug]: the `fzf` function can't reach scripts a
      widget runs that start fzf themselves, widgets using `$commands[fzf]` or `fzf-tmux`, or
      `ftb-tmux-popup` (popup mode was never tested for this bug). They would get the same I or O in the query
      if focus reports reach them. Fix per case when one shows it. Checked 2026-11-13: none is in use in
      ~/.shell (fzf-tab's fzf-command is plain fzf; fzf completion takes fzf-tmux only with FZF_TMUX set).
- [x] **An empty NO_COLOR turns color off in most of fzx** (p3) [bug]: 100 checks in lib/ and modules/ (54
      files, recounted 2026-11-11) test `${NO_COLOR+x}`, so `NO_COLOR=` (set, empty) drops color, while bin/fzx (`${NO_COLOR:-}`)
      and prettypath treat an empty one as unset, as no-color.org asks ("present and not an empty string").
      One helper (fzx::no_color) used everywhere would make them agree; the fix is mechanical but touches
      every module, so it wants the full suite and a look at each preview.

## Completed

### 8. Outside this repo (completed 2026-11-10)

- [x] **prettypath follow-ups** (p3) [chore] (~/ghq/github.com/njhoffman/prettypath): all landed in prettypath
      (automatic stat 0.1.0; `--base`, `--dirs`, `--field`, NO_COLOR 0.2.0). fzx no longer passes
      `--stat_file=false`, and with prettypath 0.2.0 or later fzx::pretty passes `--base`/`--dirs` instead of
      its prefix-strip awk and slash sed (kept for 0.1.x).
- [x] **Use prettypath --field instead of joining by path** (p3) [refactor]: dirs, recent and github pipe one
      column through fzx::pretty and join the result back by path with awk. With prettypath 0.2.0+ (level
      `current`), `--field=N` decorates that column in place and keeps the others, in order; the join (and its
      "a path prettypath does not return keeps a plain display" case) would go away for current versions.
