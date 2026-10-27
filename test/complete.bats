#!/usr/bin/env bats
# shell completion: `fzx completion zsh` and the lists `fzx _complete` gives it

load test_helper

setup() {
  setup_fzx
}

@test "_complete targets: every module with its description, then its modes; hidden modes left out" {
  run "$FZX" _complete targets
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n'"files"$'\t'"find files and directories, or grep their contents"$'\n'* ]]
  [[ "$output" == *$'\n'"files:grep"$'\t'"search file contents as you type"$'\n'* ]]
  [[ "$output" == *$'\n'"github:mine"$'\t'* ]]
  # hidden: reached from another screen only
  [[ "$output" != *"git:commit"* && "$output" != *"github:tree"* ]]
  # fixture modules on FZX_MODULE_PATH count too; the first on the path wins
  [[ "$output" == *$'\n'"counter"$'\t'* ]]
  [ "$(printf '%s\n' "$output" | grep -c "^ps"$'\t')" -eq 1 ]
}

@test "_complete modules and sessions; an unknown list fails" {
  run "$FZX" _complete modules
  [[ " ${lines[*]} " == *" github "* && " ${lines[*]} " == *" ps "* ]]
  load_libs log session
  fzx::session_create ps "$FZX_REPO/modules/ps"
  run "$FZX" _complete sessions
  [ "$output" = "$FZX_SESSION"$'\t'ps ]
  run "$FZX" _complete bogus
  [ "$status" -eq 2 ]
}

@test "completion zsh: a #compdef function zsh parses; other shells are refused" {
  run "$FZX" completion zsh
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "#compdef fzx" ]
  command -v zsh > /dev/null || skip "zsh not installed"
  "$FZX" completion zsh > "$BATS_TEST_TMPDIR/_fzx"
  zsh -n "$BATS_TEST_TMPDIR/_fzx"
  run "$FZX" completion bash
  [ "$status" -eq 2 ]
}

@test "completion zsh: in a real shell, tab lists commands, module:mode targets and options" {
  command -v zsh > /dev/null || skip "zsh not installed"
  mkdir -p "$BATS_TEST_TMPDIR/fpath"
  "$FZX" completion zsh > "$BATS_TEST_TMPDIR/fpath/_fzx"
  # an interactive zsh in a pseudo-terminal: type the line and a tab, read what it lists
  cat > "$BATS_TEST_TMPDIR/drive.zsh" << 'EOF'
zmodload zsh/zpty
complete_line() {
  local out="" chunk
  zpty -b z zsh -f -i
  zpty -w z "PS1='> '; fpath=($FPATH_DIR \$fpath); autoload -Uz compinit; compinit -u -D; path=($BIN_DIR \$path); unsetopt beep; LISTMAX=0"
  zpty -w -n z "$1"$'\t'
  sleep 2
  while zpty -r -t z chunk 2> /dev/null; do out+="$chunk"; done
  zpty -d z
  print -r -- "$out" | tr -d '\r' | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g'
}
print "== commands"; complete_line 'fzx '
print "== targets"; complete_line 'fzx -m files:'
print "== options"; complete_line 'fzx stats --'
EOF
  FPATH_DIR="$BATS_TEST_TMPDIR/fpath" BIN_DIR="$FZX_REPO/bin" run timeout 60 zsh -f "$BATS_TEST_TMPDIR/drive.zsh"
  local commands targets options
  commands="${output#*== commands}" commands="${commands%%== targets*}"
  targets="${output#*== targets}" targets="${targets%%== options*}"
  options="${output#*== options}"
  [[ "$commands" == *"completion  -- print a shell completion script"* && "$commands" == *"stats "*"-- runs, callbacks"* ]]
  [[ "$targets" == *"files:grep"*"-- search file contents as you type"* && "$targets" == *"files:dirs"* ]]
  [[ "$options" == *"--since"*"-- only what ran since"* && "$options" == *"--module"* ]]
}
