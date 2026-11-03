# fzx TODO

Status (0.66.0): the six steps of `docs/design.md` are done. Modules: actions, audio, capture, colors, dirs,
docker, files, git, github, glyphs, history, keybindings, logs, man, menu, music, network, packages, ps, recent, repos, shell, systemd, tasks, tmux,
todos, youtube; zsh widgets in `shell/fzx.zsh`. What has shipped is in CHANGELOG.md, so ticked items are removed
here once they are released. Keep this file current: tick items off, add what you find.

Every item carries a priority in its first line, `(p1)` high, `(p2)` normal or `(p3)` low, and a
category: `[bug]` `[feature]` `[refactor]` `[docs]` `[test]` `[chore]` `[perf]`, plus this repo's own below.
`(due YYYY-MM-DD)` adds a date and an OVERDUE flag. `/todo` (`~/.shell/scripts/todo-status`) and `/todo-pop`
(`fzx -m todos`) sort and mark by them; `todo-status --check` lists untagged items.

Categories: module

Reviewed: 2026-11-02

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
- [ ] **alt-^ flips popup and inline** (p3) [feature]: a second placement key that switches only between the
      popup and the plain terminal, skipping split and float (ctrl-^, `FZX_KEYS[popout]`, keeps the full cycle).
      Check what the terminal sends for alt-shift-6 and that fzf accepts `alt-^`.

## 4. Core features

- [ ] **Grepper and finder arguments in the prompt** (p2) [feature]: in files (grep and the finder modes), a
      key that puts the rg/fd arguments into the query, enter applies them; show the current arguments in
      the preview's top line or a label. Prior art: resources/ (older setups). Grep mode's switch between
      grepping and fzf filtering (ctrl-t) shipped in 0.40.0; fd and ripgrep are already the tools used.
- [ ] **Header hook for in-place refreshes** (p3) [refactor]: a mode, toggle or sort change refreshes the
      label and component line but never the module's header, so rows that change it are flagged `restart`
      (github's issues, prs, notifications, mine, starred and the everywhere toggle). An optional
      `<module>::header` called from `fzx::_nav_refresh` (writing meta/header, emitting change-header or
      transform-header, as `files::_header` does by hand) would let them switch in place without the flicker.
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
- [ ] **dirs: bookmark from the list** (p3) [feature]: add and remove bookmarks with keys (fzf-marks' mark/unmark),
      kept in a file under FZX_STATE_DIR instead of only FZX_DIRS_BOOKMARKS in config. Ref: fzf-marks.plugin.zsh.
- [ ] **snippets and paste history** (p3) [feature]: both kinds: an automatic history of what capture and tmux
      buffers paste (newest first, under FZX_STATE_DIR), and named snippets saved on purpose (snippetdb's
      put/get/remove/list). Open: a capture mode, or a module of its own that the zsh widgets can use
      outside tmux too. Ref: resources/fzfmenu/proto-widgets/tmux/snippetdb.
- [ ] **tmux: marked-pane round trip** (p3) [feature]: go to `{marked}` and back across sessions, remembering
      the way back in a server option (jump-marked). Probably better as a tmux key binding than an fzx
      action; inside fzx it saves one key over alt-s on the marked pane. Ref: proto-widgets/tmux/jump-marked.
- [ ] **docker: exec a command** (p3) [feature]: fzf-runinc: exec a typed command (not a shell) in the container,
      output kept on screen; and docker system df as the images/volumes summary. Ref: fzf-rsc/modules/docker.
- [ ] **github: review threads** (p3) [feature]: a pull request's preview has its reviews' verdicts and texts,
      but not their inline comments: `gh pr view` lacks them; `gh api repos/O/R/pulls/N/comments` has them with
      path, line and `in_reply_to_id`, to draw as threads under the file and line (octo.nvim's review view).

## 6. New modules

Built from the reference repos in `resources/` (fzfmenu widgets, proto-widgets, vendored widgets and
completers, the fzf attempt's modules, fzf-scripts) and checked against what is installed here
(2026-10-20). "has" lists tools found on PATH, "missing" what the old code used that is not installed.

- [ ] **repl** (p2) [module]: live jq/awk/sed/grep/sh filter over a file with the result in the preview
      (`change:reload`). Refs: ref/mods/repl.sh + repl-data, development/fzr-*, fzf/_scratch/repl.*.
      Has: jq, awk, sed. Missing: yq (fzr-yq mode).
- [ ] **pass** (p2) [module]: password-store entries, copy password or a field with a clear timer.
      Refs: system/fzpass.sh, fzpass2.sh, ffpass.sh. Has: pass, gpg, ~/.password-store.
- [ ] **music: rating and tag edits** (p3) [feature]: rate the selected songs and edit musicman's
      multi-value fields (context, mood, picks) through `musicman edit`, from the tracks and queue modes;
      held back from 0.63.0, which only browses and plays.
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
- [ ] **nvcat is slow for previews** (p3) [perf]: about 300-1200ms per focus change (it starts Neovim), for
      markdown and every filetype `nvcat-dispatch` claims (any *.conf, systemd units, ...); files over
      FZX_PREVIEW_NVCAT_MAX_LINES already go to bat. Cache its output under $FZX_CACHE_DIR keyed by path,
      mtime and width (lib/render.sh, fzx::_render_nvcat), or keep one Neovim running.
- [ ] **Actions menu marks run as default under `tasks --paste`** (p3) [bug]: with `--paste` enter pastes
      (the module binds it, lib/actions.sh skips the default's enter), but the actions menu still draws ⏎ on
      `run` since it reads the flags from `meta/components`. Record the override in the session (a meta key)
      and drop the mark (modules/actions/source.sh).
- [ ] **github: comment headings look like the body's** (p3) [bug]: the preview's timeline puts each comment
      under a `###` heading, so a body or comment using `###` itself reads like a new comment. Draw the
      comment headers some other way that the markdown renderer still styles (a blockquote line, or a level
      the bodies rarely use), or demote the bodies' headings (modules/github/preview.sh, github::item_details).
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
