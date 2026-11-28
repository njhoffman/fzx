#!/usr/bin/env bash
# colors sample: the theme's sample fzf, run in a tmux split by colors::theme_sample. <session dir> is the
# colors session: its state/theme_sample_colors holds the --color items to lay over the user's fzf options
# (fzf reads those itself), and the pane closes itself once that session's owner is gone.
# `bash sample.sh SESSION_DIR`; respawn-pane -k restarts it with new colors.

dir="${1:?usage: sample.sh SESSION_DIR}"
colors=""
[[ -r "$dir/state/theme_sample_colors" ]] && IFS= read -r colors < "$dir/state/theme_sample_colors"
owner=""
[[ -r "$dir/meta/owner_pid" ]] && IFS= read -r owner < "$dir/meta/owner_pid"

# the pane goes with fzx: the owner ended, or the session was removed
(
  while [[ -d "$dir" ]] && { [[ -z "$owner" ]] || kill -0 "$owner" 2> /dev/null; }; do sleep 1; done
  tmux kill-pane -t "${TMUX_PANE:-}" 2> /dev/null
) &

items=(
  "apple pie with cinnamon" "banana bread" "cantaloupe and lime" "date squares" "elderflower cordial"
  "fig and walnut tart" "grape sorbet" "honeydew salad" "jackfruit curry" "kiwi and mango smoothie"
  "lemon meringue" "nectarine crumble" "orange marmalade" "papaya salsa" "quince paste"
)
# shellcheck disable=SC2054  # the commas are fzf's, inside one option
args=(
  --multi --style=full --query=an --info=inline-right --ghost=ghost
  --border-label=" border label " --list-label=" list label " --input-label=" input label "
  --header="the header: a line above the list" --header-label=" header label " --header-border
  --footer="the footer: a line below the list" --footer-label=" footer label " --footer-border
  --preview='printf "preview of\n\n  %s\n\nscroll for more\n" {}; seq 40' --preview-label=" preview label "
  --preview-window=down,40%
  # two selected lines, the cursor on a third
  --bind 'load:toggle+down+toggle+down+unbind(load)'
  # enter, esc and the rest do nothing here: it is a sample
  --bind enter:ignore --bind esc:ignore --bind ctrl-c:ignore --bind ctrl-g:ignore --bind ctrl-q:ignore
)
[[ -n "$colors" ]] && args+=("--color=$colors")
printf '%s\n' "${items[@]}" | fzf "${args[@]}"
