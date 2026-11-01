#!/usr/bin/env bats
# the shell module: the zsh dump (in a clean zsh), the modes' rows from it and from PATH, the environment
# fzx started with, masking, previews, actions and the zsh widget

load test_helper

SH="$(readlink -f "$BATS_TEST_DIRNAME/../modules/shell")"
ZSH_INT="$(readlink -f "$BATS_TEST_DIRNAME/../shell/fzx.zsh")"

setup() {
  command -v zsh > /dev/null || skip "zsh not installed"
  setup_fzx
  export NO_COLOR=1
  # a PATH of two directories (the first one's tool wins), stubs for tldr, man and the editor
  BIN1="$BATS_TEST_TMPDIR/bin1" BIN2="$BATS_TEST_TMPDIR/bin2" STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$BIN1" "$BIN2" "$STUBS" "$BATS_TEST_TMPDIR/fn"
  printf '#!/bin/sh\necho one\n' > "$BIN1/tool"
  printf '#!/bin/sh\necho two\n' > "$BIN2/tool"
  printf '\177ELF\0\0' > "$BIN2/bin"
  printf 'not executable\n' > "$BIN2/plain"
  chmod +x "$BIN1/tool" "$BIN2/tool" "$BIN2/bin"
  ln -s "$BIN2/tool" "$BIN2/linked"
  printf '#!/usr/bin/env bash\n[[ "$*" == *tool* ]] || exit 1\necho "tldr page of ${*: -1}"\n' > "$STUBS/tldr"
  printf '#!/usr/bin/env bash\n[[ "$1" == -f ]] && { echo "tool (1)              - does tool things"; echo "Tool (3pm)            - other"; exit 0; }\nexit 16\n' > "$STUBS/man"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$BATS_TEST_TMPDIR/editor.args"\n' > "$STUBS/vi"
  printf '#!/usr/bin/env bash\ncat > "$BATS_TEST_TMPDIR/clip"\n' > "$STUBS/pbcopy"
  chmod +x "$STUBS"/*
  # an autoloadable function
  printf 'echo lazy\n' > "$BATS_TEST_TMPDIR/fn/lazyfn"
  ZSHENV_PATH="$PATH"
  export PATH="$BIN1:$BIN2:$STUBS:$PATH" EDITOR=vi
  unset WAYLAND_DISPLAY DISPLAY TMUX
}

# the dump of a clean zsh with a known setup, written where the module reads it
dump_shell() {
  zsh -f -c "
    source '$SH/dump.zsh'
    fpath=('$BATS_TEST_TMPDIR/fn' \$fpath); autoload -Uz lazyfn
    alias ll='ls -l' q=\"it's\"; alias -g G='| grep'; alias -s txt=less
    greet() { print -r -- hello \$1 }
    _comp_x() { : }
    arr=(a 'b c' ''); typeset -A hh; hh=(k 'v w' z 1); s=\$'x\ty\nz'
    export MY_TOKEN=s3cret DUMPONLY_EXPORT=d; typeset NOTE_PASSWORD=hidden
    fzx-shell-dump-file
  " 2> /dev/null
}

src() { FZX_MODE="$1" "$SH/source.sh"; }

@test "dump.zsh: aliases of each kind, functions with their files, parameters quoted, secrets without a value" {
  dump_shell
  local d="$FZX_STATE_DIR/shell"
  [ "$(stat -c %a "$d/dump.tsv")" = 600 ] && [ "$(stat -c %a "$d/functions.zsh")" = 600 ]
  grep -qxF $'alias\tregular\tll\t\'ls -l\'' "$d/dump.tsv"
  grep -qxF $'alias\tregular\tq\t\'it\'\\\'\'s\'' "$d/dump.tsv"
  grep -qxF $'alias\tglobal\tG\t\'| grep\'' "$d/dump.tsv"
  grep -qxF $'alias\tsuffix\ttxt\tless' "$d/dump.tsv"
  grep -qxF $'function\tgreet\t\t0' "$d/dump.tsv"
  grep -qxF $'function\tlazyfn\t'"$BATS_TEST_TMPDIR/fn/lazyfn"$'\t1' "$d/dump.tsv"
  grep -qxF $'param\tarr\tarray\t( a \'b c\' \'\' )\t0' "$d/dump.tsv"
  grep -qxF $'param\thh\tassociation\t( [k]=\'v w\' [z]=1 )\t0' "$d/dump.tsv"
  grep -qxF $'param\ts\tscalar\t$\'x\\ty\\nz\'\t0' "$d/dump.tsv"
  grep -qxF $'param\tMY_TOKEN\tscalar-export\t\t1' "$d/dump.tsv"
  grep -qxF $'param\tNOTE_PASSWORD\tscalar\t\t1' "$d/dump.tsv"
  ! grep -q s3cret "$d/dump.tsv"
  # zsh/parameter's tables are left out; builtins and reserved words are listed
  ! grep -qP '^param\t(parameters|functions|aliases|commands)\t' "$d/dump.tsv"
  # nor the dump function's own context: positional and punctuation parameters, the call stack
  ! grep -qP '^param\t([^A-Za-z_][^\t]*|argv|ARGC|funcstack)\t' "$d/dump.tsv"
  grep -qxF $'builtin\techo' "$d/dump.tsv" && grep -qxF $'reserved\tif' "$d/dump.tsv"
  # definitions: loaded, non-completion functions only
  grep -qx 'greet () {' "$d/functions.zsh"
  ! grep -q '_comp_x\|lazyfn' "$d/functions.zsh"
}

@test "commands: the first of each name on PATH (not plain files), then zsh's builtins and reserved words" {
  dump_shell
  run src commands
  [ "$status" -eq 0 ]
  [[ "$output" == *$'tool\tcommand\ttool'*"$BIN1/tool"* ]]
  ! grep -q "$BIN2/tool" <<< "$output"
  grep -q $'^linked\tcommand\t' <<< "$output" && grep -q $'^bin\tcommand\t' <<< "$output"
  ! grep -q $'^plain\t' <<< "$output"
  [[ "$output" == *$'\necho\tbuiltin\techo'*builtin* && "$output" == *$'\nif\treserved\tif'* ]]
}

@test "aliases and functions: kinds, expansions without their quotes; completion functions with the toggle" {
  dump_shell
  run src aliases
  [[ "$output" == *$'G\tgalias\tG'*"global | grep"* ]]
  [[ "$output" == *$'ll\talias\tll '*' ls -l'* ]]
  [[ "$output" == *$'q\talias\tq'*"'it'\\''s'"* ]]
  [[ "$output" == *$'txt\tsalias\t'*"suffix less"* ]]
  run src functions
  [[ "$output" == *$'greet\tfunction\tgreet'* && "$output" == *$'lazyfn\tfunction\tlazyfn'*"autoload "*"/fn/lazyfn"* ]]
  ! grep -q '^_comp_x' <<< "$output"
  FZX_TOGGLES=completion run src functions
  grep -q $'^_comp_x\tfunction' <<< "$output"
}

@test "params: the dump's, exported values from the environment fzx started with; masked; exported, reveal" {
  dump_shell
  load_libs log session
  fzx::session_create shell "$SH"
  # the environment fzx started with: fzx's own variables left out
  export MY_TOKEN=fromenv ENV_ONLY=$'line1\nline2' DUMPONLY_EXPORT=newer FZX_MODE=params
  source "$SH/source.sh" || :
  shell::save_env "$FZX_SESSION_DIR/data/env"
  [ "$(stat -c %a "$FZX_SESSION_DIR/data/env")" = 600 ]
  ! tr '\0' '\n' < "$FZX_SESSION_DIR/data/env" | grep -q '^FZX_\(SESSION\|MODE\|STATE_DIR\)='
  unset ENV_ONLY
  run src params
  [[ "$output" == *$'arr\tparam\tarr'*"array "*"( a 'b c' '' )"* ]]
  [[ "$output" == *$'s\tparam\ts'*"\$'x\\ty\\nz'"* ]]
  # exported: the environment's value; one the dump lacks is listed; a dump-only secret stays masked
  [[ "$output" == *$'DUMPONLY_EXPORT\tparam\t'*"newer"* ]]
  [[ "$output" == *$'ENV_ONLY\tparam\t'*'line1\nline2'* ]]
  [[ "$output" == *$'MY_TOKEN\tparam\t'*"(masked)"* && "$output" == *$'NOTE_PASSWORD\tparam\t'*"(masked)"* ]]
  FZX_TOGGLES=reveal run src params
  [[ "$output" == *$'MY_TOKEN\tparam\t'*"fromenv"* && "$output" == *$'NOTE_PASSWORD\tparam\t'*"(masked)"* ]]
  FZX_TOGGLES=exported run src params
  ! grep -q $'^arr\t' <<< "$output"
  grep -q $'^ENV_ONLY\t' <<< "$output" && grep -q $'^DUMPONLY_EXPORT\t' <<< "$output"
}

@test "dump: a stale or missing one is read again from an interactive zsh" {
  # no dump: one from an interactive zsh (a private ZDOTDIR's zshrc), kept
  mkdir -p "$BATS_TEST_TMPDIR/zdot"
  printf "alias fromrc='echo rc'\n" > "$BATS_TEST_TMPDIR/zdot/.zshrc"
  ZDOTDIR="$BATS_TEST_TMPDIR/zdot" run src aliases
  [[ "$output" == *$'fromrc\talias\tfromrc'*"echo rc"* ]]
  touch -d '2 days ago' "$FZX_STATE_DIR/shell/dump.tsv"
  printf "alias second='x'\n" >> "$BATS_TEST_TMPDIR/zdot/.zshrc"
  ZDOTDIR="$BATS_TEST_TMPDIR/zdot" run src aliases
  grep -q $'^second\talias' <<< "$output"
}

@test "preview: commands (locations, whatis, tldr), aliases, functions, parameters" {
  dump_shell
  run "$SH/preview.sh" tool command
  [ "${lines[0]}" = tool ]
  [ "${lines[1]}" = "$BIN1/tool" ] && [ "${lines[2]}" = "$BIN2/tool" ]
  [ "${lines[3]}" = "tool (1)              - does tool things" ]
  [ "${lines[4]}" = "tldr page of tool" ]
  run "$SH/preview.sh" linked command
  [ "${lines[1]}" = "$BIN2/linked  -> $BIN2/tool" ]
  run "$SH/preview.sh" if reserved
  [[ "${lines[0]}" == "if  zsh reserved word"* ]]
  run "$SH/preview.sh" q alias
  [ "${lines[0]}" = "alias q='it'\\''s'" ]
  run "$SH/preview.sh" ll alias
  [[ "${lines[1]}" == "runs ls  "* ]]
  run "$SH/preview.sh" greet function
  [ "${lines[0]}" = 'greet () {' ]
  run "$SH/preview.sh" lazyfn function
  [[ "${lines[0]}" == *"/fn/lazyfn  (autoload, not loaded yet)" && "${lines[1]}" = "echo lazy" ]]
  FZX_MODE=params run "$SH/preview.sh" hh param
  [ "${lines[0]}" = "hh  association" ]
  [[ "${lines[1]}" == *"1"$'\t'"k -> v w" && "${lines[2]}" == *"2"$'\t'"z -> 1" ]]
  FZX_MODE=params run "$SH/preview.sh" arr param
  [[ "${lines[2]}" == *"2"$'\t'"b c" ]]
  FZX_MODE=params run "$SH/preview.sh" s param
  [ "${lines[1]}" = $'x\ty' ] && [ "${lines[2]}" = z ]
  FZX_MODE=params run "$SH/preview.sh" MY_TOKEN param
  [[ "${lines[1]}" == "masked: "* ]]
  export DEMO_PATH=/a:/b
  FZX_MODE=params run "$SH/preview.sh" DEMO_PATH param
  [ "${lines[1]}" = /a ] && [ "${lines[2]}" = /b ]
}

@test "actions: edit a function at its definition, a script; help through tldr; copy values, not masked ones" {
  dump_shell
  printf 'greet() {\n  :\n}\n' > "$BATS_TEST_TMPDIR/fn/greetfile"
  sed -i "s|^function\tgreet\t\t0|function\tgreet\t$BATS_TEST_TMPDIR/fn/greetfile\t0|" "$FZX_STATE_DIR/shell/dump.tsv"
  FZX_MODE=functions "$SH/actions.sh" edit greet
  [[ "$(head -1 "$BATS_TEST_TMPDIR/editor.args")" == "+/"*"greet"* ]]
  [ "$(tail -1 "$BATS_TEST_TMPDIR/editor.args")" = "$BATS_TEST_TMPDIR/fn/greetfile" ]
  FZX_MODE=commands "$SH/actions.sh" edit tool
  [ "$(tail -1 "$BATS_TEST_TMPDIR/editor.args")" = "$BIN1/tool" ]
  run env FZX_MODE=commands "$SH/actions.sh" edit bin
  [[ "$output" == *"is a binary"* ]]
  run env FZX_MODE=commands PAGER=cat "$SH/actions.sh" help tool
  [ "$output" = "tldr page of tool" ]
  export MY_TOKEN=fromenv
  FZX_MODE=params "$SH/actions.sh" value hh MY_TOKEN s
  [ "$(cat "$BATS_TEST_TMPDIR/clip")" = $'k -> v w\nz -> 1\nx\ty\nz' ]
}

@test "under fzx: names are accepted, the preview gets the kind; the environment is saved once per session" {
  stub_fzf
  run "$FZX" -m shell:params
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --with-nth=3 "* && " ${FZF_ARGS[*]} " == *" --accept-nth=1 "* ]]
  [[ "$(fzf_bind alt-y)" == *"_cb notify value {+1}"* ]]
  [[ "$(fzf_bind alt-3)" == *reveal* ]]
}

@test "menu: four entries; summaries from the saved dump only" {
  load_libs log config menu
  fzx::menu_entries shell "$SH"
  [ "${FZX_ENTRY_TARGETS[*]}" = "shell shell:aliases shell:functions shell:params" ]
  run shell::summary shell:aliases
  [ -z "$output" ]
  dump_shell
  run shell::summary shell:aliases
  # (zsh -f has run-help and which-command too)
  [[ "$output" =~ ^[0-9]+\ aliases$ ]]
  run shell::summary shell:functions
  [[ "$output" =~ ^[0-9]+\ functions,\ 1\ for\ completion$ ]]
  run shell::summary shell
  [[ "$output" == *" on PATH" ]]
}

@test "fzx.zsh: the dump at the first prompt and in the widget, off with FZX_ZSH_NO_SHELL_DUMP" {
  zsh -f -i -c "source '$ZSH_INT'; alias widgetalias=x; _fzx_shell_first_prompt; sleep 1" 2> /dev/null
  grep -q $'^alias\tregular\twidgetalias' "$FZX_STATE_DIR/shell/dump.tsv"
  rm -f "$FZX_STATE_DIR/shell/dump.tsv"
  FZX_ZSH_NO_SHELL_DUMP=1 zsh -f -i -c "source '$ZSH_INT'; _fzx_shell_first_prompt; sleep 1" 2> /dev/null
  [ ! -e "$FZX_STATE_DIR/shell/dump.tsv" ]
  run zsh -f -i -c "source '$ZSH_INT'; whence -w fzx-shell-widget; zle -l | grep -c '^fzx-shell-widget'" 2> /dev/null
  [ "${lines[0]}" = "fzx-shell-widget: function" ] && [ "${lines[1]}" = 1 ]
}
