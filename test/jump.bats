#!/usr/bin/env bats
# fzx jump (g / gg), the recent module's zlua mode and the dirs module's all mode, with z.lua and fd stubbed

load test_helper

DIRS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/dirs")"
RECENT="$(readlink -f "$BATS_TEST_DIRNAME/../modules/recent")"

setup() {
  setup_fzx
  stub_fzf
  T="$(mkdir -p "$BATS_TEST_TMPDIR/d" && cd "$BATS_TEST_TMPDIR/d" && pwd -P)"
  mkdir -p "$T/one/proj" "$T/two/proj" "$T/three/proj"
  # z.lua -l [words]: best match last, like the real one; -x <dir>: forget it. $ZL_OUT replaces the list.
  cat > "$BATS_TEST_TMPDIR/z.lua" << STUB
echo "zlua \$*" >> "$BATS_TEST_TMPDIR/calls"
case "\$1" in
  -l)
    if [[ -n "\${ZL_OUT+set}" ]]; then printf '%b' "\$ZL_OUT"; exit 0; fi
    printf '%-10s %s\n' 2 "$T/three/proj" 3 "$T/gone/proj" 10 "$T/two/proj" 120.5 "$T/one/proj" ;;
esac
STUB
  export FZX_RECENT_ZLUA="$BATS_TEST_TMPDIR/z.lua" FZX_RECENT_ZLUA_LUA=bash
  # no recent files source, so recent's first mode is a directory one
  export FZX_RECENT_NVIM_DB=/nonexistent
  # fd: a fixed walk; its arguments are recorded
  cat > "$BATS_TEST_TMPDIR/bin/fd" << STUB
#!/usr/bin/env bash
echo "fd \$*" >> "$BATS_TEST_TMPDIR/calls"
printf '%s/\n' "\$HOME/a" "\$HOME/a/b"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/fd"
  cd "$T"
}

@test "zlua mode: best match first, scores rounded, missing directories dropped" {
  FZX_MODE=zlua run bash -c "'$RECENT/source.sh' proj | cut -f1"
  [ "$output" = "$T/one/proj"$'\n'"$T/two/proj"$'\n'"$T/three/proj" ]
  grep -q "zlua -l proj" "$BATS_TEST_TMPDIR/calls"
}

@test "zlua mode is offered only when z.lua is found; remove forgets with -x" {
  FZX_RECENT_ZLUA=none run "$FZX" -m recent
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" != zlua ]
  FZX_MODE=zlua run "$RECENT/actions.sh" remove "$T/one/proj"
  grep -q "zlua -x $T/one/proj" "$BATS_TEST_TMPDIR/calls"
}

@test "all mode: fd over ~ with the depth limit and excludes; words become the fzf query" {
  # a home of its own: the stub lists $HOME/a and $HOME/a/b
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/a/b"
  FZX_MODE=all run bash -c "'$DIRS/source.sh' | cut -f1"
  [ "$output" = "$HOME/a"$'\n'"$HOME/a/b" ]
  grep -q -- "--max-depth 6 .*--exclude node_modules" "$BATS_TEST_TMPDIR/calls"
  run "$FZX" -m dirs:all foo bar
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --query=foo bar "* && " ${FZF_ARGS[*]} " != *" --select-1 "* ]]
}

@test "g: the best match" {
  run "$FZX" jump proj
  [ "$status" -eq 0 ]
  [ "$output" = "$T/one/proj" ]
}

@test "g: from inside a match, the next one, wrapping; a symlinked PWD counts" {
  cd "$T/one/proj"
  run "$FZX" jump proj
  [ "$output" = "$T/two/proj" ]
  cd "$T/three/proj"
  run "$FZX" jump proj
  [ "$output" = "$T/one/proj" ]
  ln -s "$T/two/proj" "$BATS_TEST_TMPDIR/link"
  cd "$BATS_TEST_TMPDIR/link"
  run "$FZX" jump proj
  [ "$output" = "$T/three/proj" ]
}

@test "g: a directory given as is wins, ~ expanded" {
  run "$FZX" jump one
  [ "$output" = "$T/one" ]
  run "$FZX" jump "~"
  [ "$output" = "$(cd ~ && pwd)" ]
}

@test "g: no match opens the picker over every directory with the words as its query" {
  STUB_FZF_OUT="$HOME" ZL_OUT= run "$FZX" jump nothing here
  [ "$output" = "$HOME" ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = all ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --query=nothing here "* ]]
  grep -q "jump: no zlua match for 'nothing here'" "$LOG"
}

@test "g: no words opens the picker over every frecent directory" {
  STUB_FZF_OUT="$T/two/proj" run "$FZX" jump
  [ "$output" = "$T/two/proj" ]
  [ "$(< "$BATS_TEST_TMPDIR/fzf.mode")" = zlua ]
}

@test "gg: a single match without a picker; several open the picker over them" {
  ZL_OUT="5 $T/two/proj\n" run "$FZX" jump --pick proj
  [ "$output" = "$T/two/proj" ]
  [ ! -f "$BATS_TEST_TMPDIR/fzf.args" ]
  STUB_FZF_OUT="$T/three/proj" run "$FZX" jump --pick proj
  [ "$output" = "$T/three/proj" ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --select-1 --exit-0 "* ]]
}

@test "FZX_RECENT_DIRS_JUMP_MODE picks the tracker, in recent or another module; bad options fail" {
  mkdir -p "$FZX_CONFIG_DIR/modules/dirs" "$FZX_CONFIG_DIR/modules/recent"
  echo 'FZX_DIRS_BOOKMARKS=([x]='"$T/three"')' > "$FZX_CONFIG_DIR/modules/dirs/config.sh"
  echo 'FZX_RECENT_DIRS_JUMP_MODE=dirs:bookmarks' > "$FZX_CONFIG_DIR/modules/recent/config.sh"
  run "$FZX" jump x
  [ "$output" = "$T/three" ]
  run "$FZX" jump --bogus
  [ "$status" -eq 2 ]
}

@test "zsh: g cds and shows where; repeating steps on; gg reuses the last words" {
  command -v zsh > /dev/null || skip "zsh not installed"
  local zint
  zint="$(readlink -f "$BATS_TEST_DIRNAME/../shell/fzx.zsh")"
  run script -qec "zsh -f -i -c \"FZX_ZSH_BIN='$FZX'; source '$zint'; cd '$T'; g proj; pwd; g proj; pwd; cd /; gg; pwd\"" /dev/null
  output="$(printf '%s' "$output" | tr -d '\r' | sed 's/\x1b\[[0-9;]*m//g')"
  [[ "$output" == *"$T/one/proj"$'\n'*"$T/two/proj"* ]]
  # gg with no words: "proj" again, several matches, the stub fzf picks nothing -> stays in /
  [[ "$output" == *$'\n/' || "$output" == *$'\n'"/"$'\n'* ]]
  run script -qec "zsh -f -i -c \"FZX_ZSH_NO_JUMP=1; source '$zint'; whence -w g\"" /dev/null
  [[ "$output" != *"g: function"* ]]
}
