#!/usr/bin/env bats
# the fonts module against a stub fc-list (fixture fonts; a pattern argument filters by family), stub
# magick and chafa

load test_helper

FONTS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/fonts")"

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  # family style spacing format file
  cat > "$BATS_TEST_TMPDIR/fonts" << 'EOF'
Mono One	Bold	100	TrueType	/f/MonoOne-Bold.ttf
Mono One	Regular	100	TrueType	/f/MonoOne-Regular.ttf
Mono One	Italic	100	CFF	/f/MonoOne-Italic.otf
alpha Sans	Light		TrueType	/f/AlphaSans-Light.ttf
alpha Sans	Bold		TrueType	/f/AlphaSans-Bold.ttf
Zed Dual	Book	90	TrueType	/f/ZedDual.ttf
Mono One	Regular	100	Type 1	/f/dup/MonoOne.pfb
EOF
  # --format F [pattern]: the fields the format names, the rows of the pattern's family
  cat > "$STUBS/fc-list" << 'STUB'
#!/usr/bin/env bash
[[ "$1" == --format ]] || exit 1
fmt="$2" fam=""
[[ -n "${3:-}" ]] && fam="$(printf '%s' "${3#:family=}" | sed 's/\\\(.\)/\1/g')"
awk -F'\t' -v fmt="$fmt" -v fam="$fam" '
  fam != "" && $1 != fam { next }
  {
    s = fmt
    gsub(/%\{family\[0\]\}/, $1, s); gsub(/%\{style\[0\]\}/, $2, s); gsub(/%\{spacing\}/, $3, s)
    gsub(/%\{fontformat\}/, $4, s); gsub(/%\{file\}/, $5, s); gsub(/\n/, "", s)
    print s
  }' "$BATS_TEST_TMPDIR/fonts"
STUB
  printf '#!/usr/bin/env bash\necho "magick $*" >> "%s/calls"; out="${@: -1}"; [[ "$*" == *broken* ]] && exit 1; echo png > "$out"\n' "$BATS_TEST_TMPDIR" > "$STUBS/magick"
  printf '#!/usr/bin/env bash\necho "chafa $*" >> "%s/calls"; echo SAMPLE\n' "$BATS_TEST_TMPDIR" > "$STUBS/chafa"
  printf '#!/usr/bin/env bash\necho "xdg-open $*" >> "%s/calls"\n' "$BATS_TEST_TMPDIR" > "$STUBS/xdg-open"
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/f"
  touch "$BATS_TEST_TMPDIR/f/Mono.ttf" "$BATS_TEST_TMPDIR/f/broken.ttf"
}

@test "families: one row each by name, its regular style's file, mono marker, style count, formats" {
  run "$FONTS/source.sh"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1,2 | tr '\t\n' '| ')" = "alpha Sans|/f/AlphaSans-Bold.ttf Mono One|/f/MonoOne-Regular.ttf Zed Dual|/f/ZedDual.ttf " ]
  [[ "${lines[1]}" == *"Mono One"*"  mono  4 styles    TrueType, CFF, Type 1" ]]
  [[ "${lines[0]}" == *"alpha Sans"*"        2 styles    TrueType" ]]
  [[ "${lines[2]}" == *"  mono  1 style "* ]]
}

@test "families: the mono toggle keeps monospace and dual-width ones" {
  FZX_TOGGLES=mono run "$FONTS/source.sh"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "Mono One Zed Dual " ]
}

@test "preview: the sample (rendered once per file, % escaped), then spacing, formats and styles" {
  FZF_PREVIEW_LINES=40 FZX_FONTS_SAMPLE='50% off\nline' run "$FONTS/preview.sh" "Mono One" "$BATS_TEST_TMPDIR/f/Mono.ttf"
  [ "${lines[0]}" = SAMPLE ] && [ "${lines[1]}" = "Mono One" ]
  [[ "$output" == *"spacing  mono"*"format   TrueType, CFF, Type 1"*"4 styles"*"  Bold                     /f/MonoOne-Bold.ttf"* ]]
  grep -q "^magick .*-font $BATS_TEST_TMPDIR/f/Mono.ttf .*label:50%% off" "$BATS_TEST_TMPDIR/calls"
  grep -q '^chafa .*--size=80x10 ' "$BATS_TEST_TMPDIR/calls"
  # cached: no second render
  FZX_FONTS_SAMPLE='50% off\nline' run "$FONTS/preview.sh" "Mono One" "$BATS_TEST_TMPDIR/f/Mono.ttf"
  [ "$(grep -c '^magick' "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
  # a small preview: half its lines; a font magick cannot draw: details only
  rm "$BATS_TEST_TMPDIR/calls"
  FZF_PREVIEW_LINES=12 run "$FONTS/preview.sh" "Mono One" "$BATS_TEST_TMPDIR/f/Mono.ttf"
  grep -q -- '--size=80x6 ' "$BATS_TEST_TMPDIR/calls"
  run "$FONTS/preview.sh" "Mono One" "$BATS_TEST_TMPDIR/f/broken.ttf"
  [ "${lines[0]}" = "Mono One" ]
  FZX_FONTS_SAMPLE_ROWS=0 run "$FONTS/preview.sh" "Mono One" "$BATS_TEST_TMPDIR/f/Mono.ttf"
  [ "${lines[0]}" = "Mono One" ]
  run "$FONTS/preview.sh" "Gone" ""
  [ "${lines[-1]}" = "no fonts in this family (any more)" ]
}

@test "patterns: fontconfig's special characters escaped" {
  source "$FONTS/preview.sh" || :
  [ "$(fonts::_pattern 'A-B:C,D=E\F')" = ':family=A\-B\:C\,D\=E\\F' ]
}

@test "actions: the folder of each sample file; unknown actions" {
  "$FONTS/actions.sh" folder "$BATS_TEST_TMPDIR/f/Mono.ttf" /nonexistent.ttf
  local i
  for ((i = 0; i < 30; i++)); do [[ -s "$BATS_TEST_TMPDIR/calls" ]] && break; sleep 0.1; done
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "xdg-open $BATS_TEST_TMPDIR/f" ]
  run "$FONTS/actions.sh" bogus
  [ "$status" -eq 2 ]
}

@test "under fzx: families accepted, the preview gets the sample file, alt-o the files" {
  stub_fzf
  run "$FZX" -m fonts
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=1 "* ]]
  [[ "$(fzf_flag --preview)" == *"preview {1} {2}"* ]]
  [[ "$(fzf_bind alt-o)" == "alt-o:execute-silent($FZX _cb action folder {+2})"* ]]
  [[ "$(fzf_bind alt-m)" == *toggle* ]]
}

@test "menu: the family count" {
  source "$FONTS/manifest.sh"
  fonts::applicable
  [ "$(fonts::summary fonts)" = "3 families" ]
}
