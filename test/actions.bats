#!/usr/bin/env bats
# actions: bindings from action rows, built-ins, the action callback, the actions menu

load test_helper

setup() {
  setup_fzx
  stub_fzf
  # counter gets its actions through the user's override table
  mkdir -p "$FZX_CONFIG_DIR/modules/counter"
  cat > "$FZX_CONFIG_DIR/modules/counter/components.tsv" << 'EOF2'
action  mark   alt-m  mark the items      silent,reload
action  edit   alt-e  edit the items      foreground,restart
action  pick   alt-p  print a value       print
action  zap    alt-z  zap the items       silent,reload,confirm
action  open   -      open the item       become,default
EOF2
}

# a kept session, attached in the test shell
kept() {
  "$FZX" --keep -m counter "$@"
  SID="$(basename "$(session_dirs)")"
  load_libs log session components
  fzx::session_attach "$SID"
  DIR="$FZX_SESSION_DIR"
}

# a fake clipboard: wl-copy writes what it gets to $BATS_TEST_TMPDIR/clip
fake_clipboard() {
  printf '#!/usr/bin/env bash\ncat > "%s/clip"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/wl-copy"
  chmod +x "$BATS_TEST_TMPDIR/bin/wl-copy"
  export WAYLAND_DISPLAY=test
}

@test "flags pick the fzf action: silent, foreground, print/become; reload and restart afterwards" {
  run "$FZX" -m counter
  [ "$(fzf_bind alt-m)" = "alt-m:execute-silent($FZX _cb action mark {+1})+reload($FZX _cb source)" ]
  [ "$(fzf_bind alt-e)" = "alt-e:execute($FZX _cb action edit {+1})+transform($FZX _cb nav restart)" ]
  [ "$(fzf_bind alt-p)" = "alt-p:become($FZX _cb action pick {+1})" ]
  # confirm needs the terminal, so it runs in the foreground even when flagged silent
  [ "$(fzf_bind alt-z)" = "alt-z:execute($FZX _cb action zap {+1})+reload($FZX _cb source)" ]
  # the default action takes enter; without a key it has no other binding
  [ "$(fzf_bind enter)" = "enter:become($FZX _cb action open {+1})" ]
}

@test "without a default action enter is left alone" {
  echo 'action  open  -  =  become' >> "$FZX_CONFIG_DIR/modules/counter/components.tsv"
  run "$FZX" -m counter
  run fzf_bind enter
  [ "$status" -eq 1 ]
}

@test "standalone: actions.sh and fzx builtin directly, the binding asks to confirm, restart reloads" {
  run "$FZX_REPO/test/fixtures/modules/counter/module.sh"
  local dir="$FZX_REPO/test/fixtures/modules/counter"
  [ "$(fzf_bind alt-m)" = "alt-m:execute-silent($dir/actions.sh mark {+1})+reload($dir/source.sh)" ]
  [ "$(fzf_bind alt-e)" = "alt-e:execute($dir/actions.sh edit {+1})+reload($dir/source.sh)" ]
  [ "$(fzf_bind alt-z)" = "alt-z:execute($FZX builtin confirm zap {+1} && $dir/actions.sh zap {+1})+reload($dir/source.sh)" ]
  # no actions menu without a session
  run fzf_bind 'ctrl-\'
  [ "$status" -eq 1 ]
}

@test "built-ins: copy, copy-line and view, with arguments; view takes the preview's" {
  echo 'action  copy  alt-c  =  =' >> "$FZX_CONFIG_DIR/modules/counter/components.tsv"
  run "$FZX" -m counter
  # copy reports in the footer, so under fzx it runs through the notify callback
  [ "$(fzf_bind alt-c)" = "alt-c:transform($FZX _cb notify copy {+1})" ]
  local bind
  bind="$(fzf_bind 'ctrl-\')"
  [ "$bind" = "ctrl-\\:transform:$FZX _cb nav goto actions mark,edit,pick,zap,open,copy {+1} --fzx-- copy-line {+} --fzx-- view {1} --fzx--" ]
}

@test "the module's opts hook sets the arguments: FZX_ACTION_ARGS and FZX_ACTION_ARGS_FOR" {
  mkdir -p "$BATS_TEST_TMPDIR/mods/argy"
  cp -r "$FZX_REPO/test/fixtures/modules/counter/." "$BATS_TEST_TMPDIR/mods/argy/"
  sed -i 's/counter::/argy::/g' "$BATS_TEST_TMPDIR"/mods/argy/*.sh
  sed -i "s/^  \[\[ -n \"\${COUNTER_OPTS_FAIL/  FZX_ACTION_ARGS='--x {+2}'; FZX_ACTION_ARGS_FOR[copy]='{+3}'\n&/" "$BATS_TEST_TMPDIR/mods/argy/module.sh"
  mkdir -p "$FZX_CONFIG_DIR/modules/argy"
  echo 'action  mark  alt-m  mark  silent' > "$FZX_CONFIG_DIR/modules/argy/components.tsv"
  FZX_MODULE_PATH="$BATS_TEST_TMPDIR/mods:$FZX_MODULE_PATH" run "$FZX" -m argy
  [ "$(fzf_bind alt-m)" = "alt-m:execute-silent($FZX _cb action mark --x {+2})" ]
  [[ "$(fzf_bind 'ctrl-\')" == *"mark --x {+2} --fzx-- copy {+3} --fzx--"* ]]
}

@test "a user row switches a built-in off" {
  echo 'action  view  -  -  off' >> "$FZX_CONFIG_DIR/modules/counter/components.tsv"
  run "$FZX" -m counter
  [[ "$(fzf_bind 'ctrl-\')" != *view* ]]
}

@test "the menu and the actions menu itself have no actions" {
  run "$FZX" -m menu
  run fzf_bind 'ctrl-\'
  [ "$status" -eq 1 ]
}

@test "callback: module actions get their arguments; built-ins run from lib/builtin.sh" {
  fake_clipboard
  kept
  FZX_SESSION="$SID" run "$FZX" _cb action mark a b
  [ "$status" -eq 0 ]
  [ "$(< "$COUNTER_FILE.actions")" = "mark a b" ]
  FZX_SESSION="$SID" run "$FZX" _cb action copy x y
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/clip")" = $'x\ny' ]
  [ "$(< "$COUNTER_FILE.actions")" = "mark a b" ]
}

@test "notify: a row flagged notify runs through the callback; standalone it stays execute-silent" {
  echo 'action  ping  alt-n  ping the items  silent,notify,reload' >> "$FZX_CONFIG_DIR/modules/counter/components.tsv"
  run "$FZX" -m counter
  [ "$(fzf_bind alt-n)" = "alt-n:transform($FZX _cb notify ping {+1})+reload($FZX _cb source)" ]
  run "$FZX_REPO/test/fixtures/modules/counter/module.sh"
  local dir="$FZX_REPO/test/fixtures/modules/counter"
  [ "$(fzf_bind alt-n)" = "alt-n:execute-silent($dir/actions.sh ping {+1})+reload($dir/source.sh)" ]
}

@test "notify callback: copies, then the message and the timed return of the component line" {
  fake_clipboard
  echo 'FZX_NOTIFY_SECONDS=0.5' > "$FZX_CONFIG_DIR/config.sh"
  kept
  FZX_SESSION="$SID" run "$FZX" _cb notify copy 'a (b)'
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/clip")" = 'a (b)' ]
  [[ "$output" == "change-footer["*"copied a (b)"*"]+bg-cancel+bg-transform-footer(sleep 0.5; $FZX _cb footer)" ]]
  FZX_SESSION="$SID" run "$FZX" _cb notify copy x y z
  [[ "$output" == "change-footer("*"copied 3 items"*")+"* ]]
}

@test "notify callback: module actions show their description, failures the first stderr line" {
  echo 'action  ping  -  ping the items  silent,notify' >> "$FZX_CONFIG_DIR/modules/counter/components.tsv"
  echo 'action  fail  -  -               silent,notify' >> "$FZX_CONFIG_DIR/modules/counter/components.tsv"
  kept
  FZX_SESSION="$SID" run "$FZX" _cb notify ping a b
  [[ "$output" == "change-footer"?*"✓ ping the items (2)"*"+bg-cancel+"* ]]
  [ "$(< "$COUNTER_FILE.actions")" = "ping a b" ]
  FZX_SESSION="$SID" run "$FZX" _cb notify fail a
  [ "$status" -eq 0 ]
  [[ "$output" == "change-footer"?*"✗ fail failed: action stderr"*"+bg-cancel+"* ]]
  grep -q "action stderr" "$LOG"
}

@test "footer callback: the component line from the current state; nothing when it is in the header" {
  printf '%s\n' 'toggle  hidden  -  hidden  -' >> "$FZX_CONFIG_DIR/modules/counter/components.tsv"
  kept
  FZX_SESSION="$SID" "$FZX" _cb toggle hidden > /dev/null
  FZX_SESSION="$SID" run "$FZX" _cb footer
  [[ "$output" == *hidden* ]]
  echo 'FZX_HEADER_POSITION=header' > "$FZX_CONFIG_DIR/config.sh"
  FZX_SESSION="$SID" run "$FZX" _cb footer
  [ -z "$output" ]
}

@test "callback: view pages the module's preview" {
  kept
  PAGER=cat FZX_SESSION="$SID" run "$FZX" _cb action view item
  [ "$output" = "preview:item" ]
}

@test "callback: confirm without an answer does not run the action" {
  kept
  # no terminal here, so the question cannot be answered: treated as no
  FZX_SESSION="$SID" run "$FZX" _cb action zap a < /dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$COUNTER_FILE.actions" ]
  grep -q "action zap: not confirmed" "$LOG"
}

@test "builtin: unknown names fail, copy without a clipboard tool fails" {
  run "$FZX" builtin bogus
  [ "$status" -eq 2 ]
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" WAYLAND_DISPLAY= DISPLAY= TMUX= run "$FZX" builtin copy a
  [ "$status" -eq 1 ]
  [[ "$output" == *"no clipboard tool"* ]]
}

@test "nav restart drops the cache: the next load runs the source" {
  kept
  FZX_SESSION="$SID" "$FZX" _cb load > /dev/null
  FZX_SESSION="$SID" "$FZX" _cb load > /dev/null
  [ "$(< "$COUNTER_FILE")" = 1 ]
  FZX_SESSION="$SID" run "$FZX" _cb nav restart
  [[ "$output" == "become:$FZX --resume $SID" ]]
  FZX_SESSION="$SID" "$FZX" _cb load > /dev/null
  [ "$(< "$COUNTER_FILE")" = 2 ]
  [ ! -f "$DIR/state/fresh" ]
  FZX_SESSION="$SID" "$FZX" _cb load > /dev/null
  [ "$(< "$COUNTER_FILE")" = 2 ]
}

# open the actions menu of a kept counter session on a selection: CHILD is the menu's session
menu_open() {
  kept
  local out
  out="$(FZX_SESSION="$SID" "$FZX" _cb nav goto actions mark,edit,pick,open a b --fzx-- copy-line 'a line' --fzx--)"
  [[ "$out" == "become:$FZX --resume "* ]]
  CHILD="${out#become:"$FZX" --resume }"
}

@test "actions menu: lists the parent's actions that came with arguments" {
  menu_open
  FZX_SESSION="$CHILD" run "$FZX" _cb source
  [ "$status" -eq 0 ]
  local names
  names="$(printf '%s\n' "$output" | cut -f1 | tr '\n' ' ')"
  [ "$names" = "mark edit pick open copy-line " ]
  [[ "${lines[0]}" == *"alt-m"*"mark the items"* ]]
  NO_COLOR=1 FZX_SESSION="$CHILD" run "$FZX" _cb preview edit
  [[ "$output" == *"flags foreground restart"* && "$output" == *$'runs on:\n  a\n  b'* ]]
}

@test "actions menu: rows show how each runs, the key as a keycap and the default mark; columns line up" {
  menu_open
  NO_COLOR=1 FZX_ICONS=unicode FZX_SESSION="$CHILD" run "$FZX" _cb source
  [ "$status" -eq 0 ]
  # silent+reload, foreground+restart, print, become+default (no key), a built-in (no key)
  [ "${lines[0]}" = $'mark\t↯↻ mark          alt-m    mark the items' ]
  [ "${lines[1]}" = $'edit\t▶↻ edit          alt-e    edit the items' ]
  [ "${lines[2]}" = $'pick\t⇥  pick          alt-p    print a value' ]
  [ "${lines[3]}" = $'open\t⇥  open                 ⏎ open the item' ]
  [ "${lines[4]}" = $'copy-line\t↯  copy-line              copy the whole lines' ]
  # no icons: the name starts the row
  NO_COLOR=1 FZX_ICONS=none FZX_SESSION="$CHILD" run "$FZX" _cb source
  [ "${lines[0]}" = $'mark\tmark          alt-m    mark the items' ]
}

@test "actions menu: colors from FZX_COLORS[actions_*]; built-ins dimmer; NO_COLOR draws none" {
  menu_open
  FZX_SESSION="$CHILD" run "$FZX" _cb source
  [[ "${lines[0]}" == *$'\e[1;38;5;255mmark '* && "${lines[0]}" == *$'\e[38;5;180;48;5;236m alt-m \e[0m'* ]]
  [[ "${lines[4]}" == *$'\e[38;5;248mcopy-line '* ]]
  [[ "${lines[3]}" == *$'\e[38;5;114m⏎\e[0m'* ]]
  NO_COLOR=1 FZX_SESSION="$CHILD" run "$FZX" _cb source
  [[ "$output" != *$'\e['* ]]
  NO_COLOR=1 FZX_SESSION="$CHILD" run "$FZX" _cb preview pick
  [[ "$output" != *$'\e['* && "$output" == *"flags print"* && "$output" == *"key    alt-p"* ]]
}

@test "actions menu: mode-scoped descriptions show the parent's mode's part; idle actions are left out" {
  menu_open
  printf 'mode\tone\t-\t-\tdefault\nmode\ttwo\t-\t-\t-\n' >> "$DIR/meta/components"
  sed -i 's/\tmark the items\t/\tone: mark the items; two: mark them twice\t/; s/\tedit the items\t/\tone: edit the items\t/' "$DIR/meta/components"
  printf two > "$DIR/state/mode"
  FZX_SESSION="$CHILD" run "$FZX" _cb source
  [ "$(printf '%s\n' "$output" | cut -f1 | tr '\n' ' ')" = "mark pick open copy-line " ]
  [[ "${lines[0]}" == *"mark them twice"* && "${lines[0]}" != *"one:"* ]]
}

@test "actions menu: its own key goes back to the screen it was opened from" {
  menu_open
  FZX_SESSION="$CHILD" "$FZX" --resume > /dev/null
  [ "$(fzf_bind 'ctrl-\')" = "ctrl-\:transform:$FZX _cb nav back" ]
}

@test "actions menu: enter runs the action and goes back, or hands over for print/become" {
  menu_open
  FZX_SESSION="$CHILD" run "$FZX" _cb transform run mark
  [ "$output" = "execute($FZX _cb action run mark)+transform($FZX _cb nav back)" ]
  FZX_SESSION="$CHILD" run "$FZX" _cb transform run pick
  [ "$output" = "become($FZX _cb action run pick)" ]
}

@test "actions menu: run calls the parent's action with the menu's arguments and refreshes it" {
  menu_open
  FZX_SESSION="$CHILD" run "$FZX" _cb action run mark
  [ "$status" -eq 0 ]
  [ "$(< "$COUNTER_FILE.actions")" = "mark a b" ]
  # mark reloads: the parent's next load runs the source
  [ -f "$DIR/state/fresh" ]
  rm -f "$DIR/state/fresh"
  FZX_SESSION="$CHILD" run "$FZX" _cb action run pick
  [ "$(tail -n1 "$COUNTER_FILE.actions")" = "pick a b" ]
  [ ! -f "$DIR/state/fresh" ]
  FZX_SESSION="$CHILD" run "$FZX" _cb action run nope
  [ "$status" -eq 2 ]
}

@test "actions menu: without a parent screen it says so" {
  run "$FZX_REPO/modules/actions/source.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"only runs as a child"* ]]
}
