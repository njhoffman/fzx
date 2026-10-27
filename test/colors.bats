#!/usr/bin/env bats
# the colors module: palette, X11 names (a fixture rgb.txt), fzx's colors, preview and copy actions

load test_helper

COLORS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/colors")"

setup() {
  setup_fzx
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '! comment\n255 255 255\t\twhite\n 70 130 180\t\tsteel blue\n 70 130 180\t\tSteelBlue\n250 240 230\t\tlinen\n' \
    > "$BATS_TEST_TMPDIR/rgb.txt"
  export FZX_COLORS_RGB_TXT="$BATS_TEST_TMPDIR/rgb.txt"
  # a fake clipboard: wl-copy writes what it gets to $BATS_TEST_TMPDIR/clip
  printf '#!/usr/bin/env bash\ncat > "%s/clip"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/wl-copy"
  chmod +x "$BATS_TEST_TMPDIR/bin/wl-copy"
  export WAYLAND_DISPLAY=test PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

src() { FZX_MODE="$1" "$COLORS/source.sh" | sed 's/\x1b\[[0-9;]*m//g'; }

@test "256: every color with its xterm name, hex and SGR in hidden fields" {
  run src 256
  [ "${#lines[@]}" -eq 256 ]
  [[ "${lines[81]}" == 81$'\t'*" 81 SteelBlue1"*"#5fd7ff (95,215,255)"$'\t#5fd7ff\t38;5;81' ]]
}

@test "names: one spelling per name, comments skipped, the nearest 256 color" {
  run src names
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "white SteelBlue linen " ]
  [[ "${lines[0]}" == white$'\t'*"#ffffff ≈ 231"$'\t#ffffff\t38;2;255;255;255' ]]
  [[ "${lines[1]}" == *"≈  67"$'\t'* ]]
  FZX_COLORS_RGB_TXT=/nonexistent FZX_MODE=names run "$COLORS/source.sh"
  [ "$status" -eq 2 ]
}

@test "fzx: fzx's colors, then each module's own keys; the user's values win" {
  run src fzx
  [[ "$(printf '%s\n' "${lines[@]}" | grep $'^dim\t')" == "dim"$'\t'"dim "*" fzx "*"38;5;244"$'\t\t38;5;244' ]]
  [[ "$output" == *"capture_visible"$'\t'*" capture "*"38;5;81"* ]]
  [ "$(printf '%s\n' "${lines[@]}" | grep -c $'^dim\t')" -eq 1 ]
  mkdir -p "$FZX_CONFIG_DIR"
  echo 'FZX_COLORS[dim]="38;5;240"' > "$FZX_CONFIG_DIR/config.sh"
  run src fzx
  [[ "$(printf '%s\n' "${lines[@]}" | grep $'^dim\t')" == *$'\t\t38;5;240' ]]
}

@test "preview: swatch from the foreground color, values per mode, no swatch without a foreground" {
  FZF_PREVIEW_COLUMNS=20 FZX_MODE=names run "$COLORS/preview.sh" SteelBlue '#4682b4' '38;2;70;130;180'
  [[ "${lines[0]}" == $'\e[48;2;70;130;180m'"$(printf '%20s' '')"* ]]
  [[ "$output" == *"nearest"*" 67 (95,135,175)"* ]]
  FZX_MODE=256 run "$COLORS/preview.sh" 81 '#5fd7ff' '38;5;81'
  [[ "$output" == *"SteelBlue1"* && "$output" == *"hsl"*"(195,100,68)"* && "$output" == *'\e[48;5;81m'* ]]
  FZX_MODE=fzx run "$COLORS/preview.sh" bold '' '1'
  [[ "${lines[0]}" != *$'\e[48;'* && "$output" == *"FZX_COLORS[bold]"* ]]
}

@test "actions: hex, SGR and escape sequences to the clipboard, empty fields skipped" {
  "$COLORS/actions.sh" hex '#5fd7ff' '' '#ffffff'
  [ "$(cat "$BATS_TEST_TMPDIR/clip")" = $'#5fd7ff\n#ffffff' ]
  "$COLORS/actions.sh" sgr '38;5;81'
  [ "$(cat "$BATS_TEST_TMPDIR/clip")" = '38;5;81' ]
  "$COLORS/actions.sh" escape '38;5;81' '1;38;2;1;2;3'
  [ "$(cat "$BATS_TEST_TMPDIR/clip")" = $'\\e[38;5;81m\n\\e[1;38;2;1;2;3m' ]
  run "$COLORS/actions.sh" bogus x
  [ "$status" -eq 2 ]
}

@test "under fzx: the preview gets the hidden fields, the copy actions theirs" {
  stub_fzf
  run "$FZX" -m colors
  [ "$status" -eq 0 ]
  [ "$(fzf_flag --preview)" = "$FZX _cb preview {1} {3} {4}" ]
  [[ "$(fzf_bind alt-h)" == *'_cb action hex {+3}'* ]]
  [[ "$(fzf_bind alt-e)" == *'_cb action escape {+4}'* ]]
}
