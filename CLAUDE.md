# fzx

fzf module manager in bash. Design, process model and module contract: `docs/design.md` (read it before
changing lib/ or adding a module).

## Commands

- `just test` (or `bats test`): full suite, ~2 minutes; `bats test/<file>.bats` for one area
- `bin/fzx -m <module> --dry-run`: the resolved fzf command
- `bin/fzx config -m <module>`: resolved config layers, keys, colors, settings
- `FZX_LOG_LEVEL=debug` then `bin/fzx debug tail`: callbacks, their durations and the fzf actions they return

## Conventions

- Module scripts define `<module>::<fn>` functions and end with a `[[ "${BASH_SOURCE[0]}" == "$0" ]]` guard
  so they are importable and runnable on their own.
- Bind strings are built with `fzx::cb <verb>`; logic lives behind `fzx _cb`, never inline in binds.
- `fzx _cb preview` runs on every focus change: keep its load path minimal (core, log, session, config).
- Functions returning through a variable name prefix their locals with `_`.
- Tests are isolated through `setup_fzx` (runtime, state, config and cache dirs under `$BATS_TEST_TMPDIR`).
- Verify UI changes live in a detached tmux server (`tmux -L <name>`); drive popups through the session's
  `fzf.sock`, since `send-keys` only reaches the pane underneath.

## Roadmap and known issues

`TODO.md`. Its open items are shown at session start (SessionStart hook in `.claude/settings.local.json`)
and on demand with `/todo [section]`; both use `~/.shell/scripts/todo-status`. Tick items off as they
land.
