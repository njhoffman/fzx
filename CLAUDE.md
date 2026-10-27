# fzx

fzf module manager in bash. Design, process model and module contract: `docs/design.md` (read it before
changing lib/ or adding a module).

## Commands

- `just test`: full suite, in parallel with GNU parallel installed (`FZX_TEST_JOBS=1`: serially, ~4 minutes);
  `bats test/<file>.bats` for one area
- `just lint`: shellcheck over every bash file (keep it clean; CI runs it); `.bats` files are not linted
- `bin/fzx -m <module> --dry-run`: the resolved fzf command
- `bin/fzx config -m <module>`: resolved config layers, keys, colors, settings
- `just install`: symlink `bin/fzx` into ~/.local/bin; `shell/fzx.zsh`: zsh widgets (source from zshrc)
- `bin/fzx completion zsh`: the zsh completion (lists come from `fzx _complete` at completion time)
- `FZX_LOG_LEVEL=debug` then `bin/fzx debug tail`: callbacks, their durations and the fzf actions they return
- `bin/fzx debug attach` (or `debug state` / `debug send ACTION`): inspect and drive the fzf on screen

## Conventions

- Module scripts define `<module>::<fn>` functions and end with a `[[ "${BASH_SOURCE[0]}" == "$0" ]]` guard
  so they are importable and runnable on their own.
- Bind strings are built with `fzx::cb <verb>`; logic lives behind `fzx _cb`, never inline in binds.
- Key bindings use `fzx::bind <key> <action> <description>` so they appear in the f1 help.
- `fzx _cb preview` runs on every focus change: keep its load path minimal (core, log, session, config).
- Functions returning through a variable name prefix their locals with `_`.
- Tests are isolated through `setup_fzx` (runtime, state, config and cache dirs under `$BATS_TEST_TMPDIR`).
- Verify UI changes live in a detached tmux server (`tmux -L <name>`); drive popups through the session's
  `fzf.sock`, since `send-keys` only reaches the pane underneath.
- Live checks that need an attached client (popups) must not use `script ... < /dev/zero`: it floods the client
  with NUL (ctrl-space) keystrokes and once pegged the CPU until a hard reboot. Attach from a second detached
  server (`tmux -L outer new-session -d "env -u TMUX tmux -L <name> attach"`) and run the whole check under
  `systemd-run --user --wait --pipe --collect -p CPUQuota=50% -p MemoryMax=1G -p RuntimeMaxSec=60`, so the
  cgroup, daemonized tmux servers included, is killed when it ends. Keep the runtime dir path short: the
  fzf.sock path must stay under 108 characters.

## Roadmap and known issues

`TODO.md`. Its open items are shown at session start (SessionStart hook in `.claude/settings.local.json`)
and on demand with `/todo [section]`; both use `~/.shell/scripts/todo-status`. `/todo-pop` picks items
in a tmux popup (`fzx -m todos --paste`, this repo's todos module) and pastes them into the prompt. Tick
items off as they land.
