#!/usr/bin/env bats
# the workspaces module against a stub workspace command (its scripts/ directory beside a layouts/ one, as in
# ~/.config/tmux), a stub family-stay.sh and a stub tmux

load test_helper

WS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/workspaces")"

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none TMUX=/tmp/tmux-test,1,0
  local root="$BATS_TEST_TMPDIR/tmux"
  mkdir -p "$root/scripts" "$root/layouts" "$BATS_TEST_TMPDIR/bin" "$HOME_REPO"
  export FZX_WORKSPACE_CMD="$root/scripts/workspace" WS_CALLS="$BATS_TEST_TMPDIR/calls"
  # KEY NAME TYPE ROOT STATE
  printf '%s\n' \
    $'main-nvim\tmain-nvim\tmain-nvim\t'"$HOME"$'/.config/nvim\tclosed' \
    $'main-fzx\tmain-fzx\tclaude\t'"$HOME_REPO"$'\topen' \
    $'main-shell\tmain-shell\tsession\t'"$HOME"$'\topen' \
    "$HOME/src/site"$'\tmain-site\tgit\t'"$HOME/src/site"$'\tclosed' \
    "$HOME/notes"$'\tmain-notes\tgeneric\t'"$HOME/notes"$'\tclosed' > "$BATS_TEST_TMPDIR/list"
  cat > "$FZX_WORKSPACE_CMD" << 'STUB'
#!/usr/bin/env bash
echo "workspace $*" >> "$WS_CALLS"
L="$BATS_TEST_TMPDIR/list"
case "$1" in
  list) cat "$L" ;;
  type) awk -F'\t' -v k="$2" '$1 == k { print $2 "\t" $3 "\t" $4 "\t" $5; f = 1 } END { exit !f }' "$L" ;;
  predefined) [[ "$2" == main-nvim ]] && echo "$BATS_TEST_TMPDIR/tmux/layouts/main-nvim.sh" || exit 1 ;;
esac
exit 0
STUB
  printf '#!/usr/bin/env bash\necho "family-stay $*" >> "$WS_CALLS"\n' > "$root/scripts/family-stay.sh"
  printf '# shellcheck shell=bash\n# main-nvim: the neovim configuration. nvim on the left,\n# the log on the right.\n\nROOT=x\n' > "$root/layouts/main-nvim.sh"
  printf '# shellcheck shell=bash\n# git: any other git work tree. nvim on the left, a shell on the right.\ndetect() { :; }\n' > "$root/layouts/20-git.sh"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" << 'STUB'
#!/usr/bin/env bash
case "$1" in
  show-options) echo main ;;
  list-panes) printf '1\tzsh\t1\tzsh\t%s\t10\n1\tzsh\t2\tclaude\t%s/x\t11\n2\tlogs\t1\ttail\t/var/log\t00\n' "$HOME" "$HOME" ;;
  *) echo "tmux $*" >> "$WS_CALLS" ;;
esac
STUB
  chmod +x "$root/scripts/"* "$BATS_TEST_TMPDIR/bin/tmux"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# a claude project with a branch, a change and two open TODO items
HOME_REPO="$BATS_TEST_TMPDIR/repo"
repo() {
  git -C "$HOME_REPO" init -q -b main
  printf -- '- [ ] one\n- [x] done\n- [ ] two\n' > "$HOME_REPO/TODO.md"
}

src() { FZX_MODE="$1" "$WS/source.sh"; }

@test "rows: the list's order, a state mark, names without the family prefix, the type, roots under ~" {
  run src all
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  IFS=$'\t' read -r key state type root display <<< "${lines[0]}"
  [ "$key" = main-nvim ] && [ "$state" = closed ] && [ "$type" = main-nvim ] && [ "$root" = "$HOME/.config/nvim" ]
  [[ "$display" == *" nvim   main-nvim  ~/.config/nvim" ]]
  [[ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" == "main-nvim main-fzx main-shell $HOME/src/site $HOME/notes " ]]
  [[ "${lines[3]}" == *" site   git        ~/src/site" ]]
}

@test "modes: open sessions, recent directories, predefined sessions" {
  [ "$(src open | cut -f1 | tr '\n' ' ')" = "main-fzx main-shell " ]
  [ "$(src recent | cut -f1 | tr '\n' ' ')" = "$HOME/src/site $HOME/notes " ]
  [ "$(src predefined | cut -f1)" = main-nvim ]
  FZX_WORKSPACE_CMD=/nonexistent run src all
  [ "$status" -eq 2 ] && [[ "$output" == *"no workspace command"* ]]
}

@test "preview: an open session's windows and panes; a closed one's layout; a claude root's git and TODO" {
  repo
  run "$WS/preview.sh" main-fzx open claude "$HOME_REPO"
  [ "${lines[0]}" = main-fzx ]
  [[ "$output" == *"state   open"* ]]
  [[ "$output" == *"1: zsh"*"   1 zsh  ~"*"  *2 claude  ~/x"*"2: logs"*"   1 tail  /var/log"* ]]
  [[ "$output" == *"branch  main, 1 changed"*"?? TODO.md"* ]]
  [[ "$output" == *"todo    2 open in TODO.md"* ]]
  run "$WS/preview.sh" main-nvim closed main-nvim "$HOME/.config/nvim"
  [[ "$output" == *"layout  "*"/layouts/main-nvim.sh"* ]]
  [[ "$output" == *"  main-nvim: the neovim configuration. nvim on the left,"$'\n'"  the log on the right." ]]
  [[ "$output" != *shellcheck* && "$output" != *ROOT=* ]]
  run "$WS/preview.sh" "$HOME/src/site" closed git "$HOME/src/site"
  [[ "$output" == *"20-git.sh"*"  git: any other git work tree."* ]]
}

@test "actions: open the first (on WORKSPACE_CLIENT), reset and kill open sessions, forget recent directories" {
  "$WS/actions.sh" open -- main-shell main-fzx
  WORKSPACE_CLIENT=/dev/pts/9 "$WS/actions.sh" open -- "$HOME/notes"
  "$WS/actions.sh" reset -- main-fzx
  "$WS/actions.sh" kill -- main-fzx main-shell
  "$WS/actions.sh" forget -- "$HOME/notes"
  [ "$(grep -v ' type ' "$WS_CALLS")" = "workspace open main-shell
workspace open -c /dev/pts/9 $HOME/notes
workspace reset --yes main-fzx
family-stay kill main-fzx
family-stay kill main-shell
workspace forget $HOME/notes" ]
  # closed ones are not killed or reset; sessions are not forgotten
  : > "$WS_CALLS"
  run "$WS/actions.sh" kill -- main-nvim "$HOME/notes"
  [ "$status" -eq 1 ] && [[ "$output" == *"main-nvim is not an open session"* ]]
  run "$WS/actions.sh" forget -- main-fzx
  [ "$status" -eq 1 ] && [[ "$output" == *"not a recent directory"* ]]
  [ -z "$(grep -v ' type ' "$WS_CALLS")" ]
  # without family-stay.sh: tmux kill-session
  rm "$BATS_TEST_TMPDIR/tmux/scripts/family-stay.sh"
  "$WS/actions.sh" kill -- main-shell
  grep -qx 'tmux kill-session -t =main-shell' "$WS_CALLS"
}

@test "under fzx: --dry-run exits 0 (workspace pick's check), enter prints the key, the actions bound" {
  run "$FZX" -m workspaces --dry-run
  [ "$status" -eq 0 ]
  stub_fzf
  run "$FZX" -m workspaces
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=1 "* && " ${FZF_ARGS[*]} " == *" --with-nth=5 "* ]]
  [[ "$(fzf_bind alt-enter)" == *"open"* && "$(fzf_bind alt-enter)" == *"become"* ]]
  [[ "$(fzf_bind alt-x)" == *"kill"* && "$(fzf_bind alt-d)" == *"forget"* && "$(fzf_bind alt-R)" == *"reset"* ]]
  [[ "$(fzf_bind enter)" != *"_cb"* ]]
}

@test "menu: applicable inside tmux with the command; summary counts open sessions and recent directories" {
  source "$WS/manifest.sh"
  workspaces::applicable workspaces
  [ "$(workspaces::summary workspaces)" = "2 open, 2 recent" ]
  TMUX="" run workspaces::applicable workspaces
  [ "$status" -ne 0 ]
  FZX_WORKSPACE_CMD=/nonexistent run workspaces::applicable workspaces
  [ "$status" -ne 0 ]
}

@test "repos and dirs: open as a workspace (alt-O) where the command is, not without it" {
  local m
  for m in repos dirs; do
    run "$FZX_REPO/modules/$m/components.tsv"
    [[ "$output" == *$'action\tworkspace\talt-O\t'* ]]
    FZX_WORKSPACE_CMD=/nonexistent run "$FZX_REPO/modules/$m/components.tsv"
    [[ "$output" != *workspace* ]]
  done
  "$FZX_REPO/modules/dirs/actions.sh" workspace "$HOME/notes"
  repo
  "$FZX_REPO/modules/repos/actions.sh" workspace "$HOME_REPO"
  [ "$(cat "$WS_CALLS")" = "workspace open $HOME/notes
workspace open $HOME_REPO" ]
}
