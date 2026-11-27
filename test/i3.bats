#!/usr/bin/env bats
# the i3 module against a stub i3-msg (commands logged) serving a fixture tree, workspaces and outputs

load test_helper

I3M="$(readlink -f "$BATS_TEST_DIRNAME/../modules/i3")"

setup() {
  command -v jq > /dev/null || skip "jq not installed"
  setup_fzx
  export NO_COLOR=1 CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # output DP-3: a dock (polybar), workspace 1 (a focused terminal, a floating browser), workspace web (an urgent
  # chat); __i3: the scratchpad with one window
  cat > "$BATS_TEST_TMPDIR/tree.json" << 'EOF'
{"nodes": [
  {"name": "__i3", "type": "output", "nodes": [{"type": "con", "name": "content", "nodes": [
    {"type": "workspace", "name": "__i3_scratch", "nodes": [], "floating_nodes": [
      {"type": "floating_con", "id": 50, "floating": "user_on", "nodes": [
        {"type": "con", "id": 51, "window": 5001, "name": "btop", "window_properties": {"class": "Alacritty"}, "floating": "user_on", "rect": {"x": 0, "y": 0, "width": 800, "height": 600}}]}]}]}]},
  {"name": "DP-3", "type": "output", "nodes": [
    {"type": "dockarea", "name": "topdock", "nodes": [{"type": "con", "id": 9, "window": 900, "name": "polybar", "window_properties": {"class": "Polybar"}}]},
    {"type": "con", "name": "content", "nodes": [
      {"type": "workspace", "name": "1", "nodes": [
        {"type": "con", "id": 11, "window": 1101, "focused": true, "name": "zsh: ~/src", "window_properties": {"class": "Alacritty", "instance": "Alacritty"}, "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}, "marks": ["main"]}],
       "floating_nodes": [
        {"type": "floating_con", "id": 12, "floating": "user_on", "nodes": [
          {"type": "con", "id": 13, "window": 1301, "name": "Docs - Browser", "window_properties": {"class": "firefox"}, "floating": "user_on", "rect": {"x": 10, "y": 10, "width": 900, "height": 700}}]}]},
      {"type": "workspace", "name": "web", "nodes": [
        {"type": "con", "id": 21, "window": 2101, "urgent": true, "name": "Chat", "window_properties": {"class": "Slack"}, "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080}}]}]}]}]}
EOF
  printf '[{"num":1,"name":"1","visible":true,"focused":true,"urgent":false,"output":"DP-3"},{"num":-1,"name":"web","visible":false,"focused":false,"urgent":true,"output":"DP-3"}]' \
    > "$BATS_TEST_TMPDIR/workspaces.json"
  cat > "$BATS_TEST_TMPDIR/bin/i3-msg" << 'STUB'
#!/usr/bin/env bash
case "$*" in
  "-t get_tree") cat "$BATS_TEST_TMPDIR/tree.json" ;;
  "-t get_workspaces") cat "$BATS_TEST_TMPDIR/workspaces.json" ;;
  "-t get_outputs") printf '[{"name":"DP-3","active":true},{"name":"eDP-1","active":false}]' ;;
  "-t get_version") printf '{"human_readable":"4.24"}' ;;
  *)
    printf 'i3-msg %s\n' "$*" >> "$CALLS"
    [[ "$*" == *nosuch* ]] && { printf '[{"success":false,"error":"No such workspace"}]'; exit 2; }
    printf '[{"success":true}]'
    ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/i3-msg"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

src() { FZX_MODE="$1" "$I3M/source.sh"; }

@test "windows: every workspace's windows (docks and the scratchpad left out), the focused, floating and urgent marked" {
  run src windows
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == $'11\t● 1        DP-3   Alacritty        zsh: ~/src' ]]
  [[ "${lines[1]}" == $'13\t◇ 1        DP-3   firefox          Docs - Browser' ]]
  [[ "${lines[2]}" == $'21\t! web      DP-3   Slack            Chat' ]]
}

@test "workspaces with their output and window count; the scratchpad's windows" {
  run src workspaces
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == $'1\t● 1            DP-3   2 windows' ]]
  [[ "${lines[1]}" == $'web\t! web          DP-3   1 window' ]]
  run src scratchpad
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == $'51\t◇ scratch         Alacritty        btop' ]]
}

@test "actions: focus, show, switch, scratch, float, kill; names are quoted for i3" {
  "$I3M/actions.sh" focus 13 11
  "$I3M/actions.sh" show 51
  "$I3M/actions.sh" switch 'my "ws"'
  "$I3M/actions.sh" scratch 11 13
  "$I3M/actions.sh" float 11
  "$I3M/actions.sh" kill 21
  [ "$(cat "$CALLS")" = 'i3-msg -- [con_id=13] focus
i3-msg -- [con_id=51] scratchpad show
i3-msg -- workspace "my \"ws\""
i3-msg -- [con_id=11] move scratchpad
i3-msg -- [con_id=13] move scratchpad
i3-msg -- [con_id=11] floating toggle
i3-msg -- [con_id=21] kill' ]
}

@test "actions: an error i3 reports fails the action and says why" {
  run "$I3M/actions.sh" switch nosuch
  [ "$status" -eq 1 ]
  [[ "$output" == *"No such workspace"* ]]
}

@test "preview: a window's properties; a workspace's windows" {
  FZX_MODE=windows run "$I3M/preview.sh" 11
  [[ "$output" == *"title      zsh: ~/src"* && "$output" == *"size       1920x1080+0+0"* && "$output" == *"marks      main"* ]]
  FZX_MODE=workspaces run "$I3M/preview.sh" 1
  [ "${lines[0]}" = "workspace 1" ]
  [[ "$output" == *"Alacritty"*"zsh: ~/src"* && "$output" == *"firefox"* && "$output" != *Slack* ]]
}

@test "under fzx: enter focuses a window, switches a workspace, shows a scratchpad window" {
  stub_fzf
  run "$FZX" -m i3
  [ "$(fzf_bind enter)" = "enter:become($FZX _cb action focus {+1})" ]
  run "$FZX" -m i3:workspaces
  [ "$(fzf_bind enter)" = "enter:become($FZX _cb action switch {+1})" ]
  run "$FZX" -m i3:scratchpad
  [ "$(fzf_bind enter)" = "enter:become($FZX _cb action show {+1})" ]
}

@test "menu: applicable when i3 answers; the counts" {
  load_libs log
  source "$I3M/manifest.sh" || :
  i3::applicable i3
  [ "$(i3::summary i3)" = "3 windows" ]
  [ "$(i3::summary i3:workspaces)" = "2 workspaces" ]
  [ "$(i3::summary i3:scratchpad)" = "1 window" ]
}

@test "components: every row has its five fields" {
  local bad
  bad="$(grep -v '^#' "$I3M/components.tsv" | awk -F'  +|\t' 'NF != 5')"
  [ -z "$bad" ] || { printf 'rows without five fields:\n%s\n' "$bad"; return 1; }
}
