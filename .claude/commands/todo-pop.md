---
description: Pick TODO.md items in a tmux popup and paste them into the prompt
allowed-tools: Bash(tmux display-popup:*), Bash(tmux display-message:*), Bash(echo:*)
---

!`tmux display-popup -E -w 90% -h 80% -d "$PWD" -t "${TMUX_PANE:-$(tmux display-message -p '#{pane_id}')}" "$(command -v fzx >/dev/null && echo 'fzx -m todos --' || echo ~/.shell/scripts/todo-fzf) --paste ${TMUX_PANE:-$(tmux display-message -p '#{pane_id}')}"; echo "todo picker popup closed (exit $?)"`

(Normally claude/hooks/claude-todo-pop-hook runs /todo-pop locally and this command
never expands; it is the fallback when the hook isn't installed.)

The todo picker popup above (`fzx -m todos`, or todo-fzf without fzx) ran in tmux and has closed. Items the user picked
were pasted into their input box (not sent); they will add to them and submit
when ready. Reply with one short line, without guessing which items were
picked. If the exit status is non-zero, the repo may have no TODO.md: check, and offer to create one as /todo describes; otherwise say
the popup failed and suggest running `~/.shell/scripts/todo-fzf` directly in a
terminal.
