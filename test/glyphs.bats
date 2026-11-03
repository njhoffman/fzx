#!/usr/bin/env bats
# the glyphs module: Nerd Font names (a fixture glyphnames.json through the update action), Unicode characters
# and blocks and emoji (fixture Unicode data), preview, copy actions and the block drill-down

load test_helper

GLYPHS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/glyphs")"

setup() {
  setup_fzx
  export NO_COLOR=1
  U="$BATS_TEST_TMPDIR/unicode"
  mkdir -p "$U/emoji" "$BATS_TEST_TMPDIR/bin"
  cat > "$U/UnicodeData.txt" << 'EOF'
0009;<control>;Cc;0;S;;;;;N;CHARACTER TABULATION;;;;
0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;0061;
00E9;LATIN SMALL LETTER E WITH ACUTE;Ll;0;L;0065 0301;;;;N;;;00C9;;00C9
0301;COMBINING ACUTE ACCENT;Mn;230;NSM;;;;;N;NON-SPACING ACUTE;;;;
2603;SNOWMAN;So;0;ON;;;;;N;;;;;
4E00;<CJK Ideograph, First>;Lo;0;L;;;;;N;;;;;
9FFF;<CJK Ideograph, Last>;Lo;0;L;;;;;N;;;;;
E000;<Private Use, First>;Co;0;L;;;;;N;;;;;
1F600;GRINNING FACE;So;0;ON;;;;;N;;;;;
EOF
  cat > "$U/Blocks.txt" << 'EOF'
# Blocks-15.1.0.txt
0000..007F; Basic Latin
0080..00FF; Latin-1 Supplement
0300..036F; Combining Diacritical Marks
2600..26FF; Miscellaneous Symbols
1F600..1F64F; Emoticons
EOF
  cat > "$U/emoji/emoji-test.txt" << 'EOF'
# group: Smileys & Emotion
# subgroup: face-smiling
1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face
263A FE0F                                              ; fully-qualified     # ☺️ E0.6 smiling face
263A                                                   ; unqualified         # ☺ E0.6 smiling face
# group: People & Body
# subgroup: family
1F468 200D 1F469 200D 1F467                            ; fully-qualified     # 👨‍👩‍👧 E2.0 family: man, woman, girl
EOF
  export FZX_GLYPHS_UNICODE_DIR="$U"
  # a fake clipboard: wl-copy writes what it gets to $BATS_TEST_TMPDIR/clip
  printf '#!/usr/bin/env bash\ncat > "%s/clip"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/wl-copy"
  # curl -o FILE URL: the fixture glyph table (STUB_CURL_BAD: something else)
  cat > "$BATS_TEST_TMPDIR/bin/curl" << 'EOF'
#!/usr/bin/env bash
while (($#)); do [[ "$1" == -o ]] && out="$2"; shift; done
if [[ -n "${STUB_CURL_BAD:-}" ]]; then echo '<html>' > "$out"; exit 0; fi
printf '{"METADATA":{"version":"9.9.9","date":"2030-01-01 00:00:00+00:00"},%s}\n' \
  "$(for i in $(seq 1 120); do printf '"cod-n%s":{"char":"x","code":"ea%02x"},' "$i" "$i"; done | sed 's/,$//')" > "$out"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin"/*
  export WAYLAND_DISPLAY=test PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

src() { FZX_MODE="$1" "$GLYPHS/source.sh" "${@:2}"; }

@test "nerd: the module's glyph names by name, the set and code point; built once into the cache" {
  run src nerd
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -gt 9000 ]
  local row
  row="$(printf '%s\n' "${lines[@]}" | grep $'\tnf-cod-account\t')"
  [[ "$row" == $'\uEB99\tEB99\tnf-cod-account\tcod\t\uEB99  nf-cod-account'*' U+EB99' ]]
  [ -s "$FZX_CACHE_DIR/glyphs/nerd.tsv" ]
  # sorted by name
  [ "$(printf '%s\n' "${lines[@]}" | cut -f3 | head -50 | LC_ALL=C sort -c && echo sorted)" = sorted ]
}

@test "unicode: named characters with their block; controls, ranges and private use left out; --block" {
  run src unicode
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f2 | tr '\n' ' ')" = "0041 00E9 0301 2603 1F600 " ]
  [ "${lines[0]}" = $'A\t0041\tlatin capital letter a\tBasic Latin\tA  U+0041   latin capital letter a  Basic Latin' ]
  # a combining mark on a dotted circle; the id is the mark alone
  [[ "${lines[2]}" == $'\u0301\t0301\tcombining acute accent\tCombining Diacritical Marks\t◌\u0301  U+0301 '* ]]
  [[ "${lines[4]}" == $'😀\t1F600\tgrinning face\tEmoticons\t'* ]]
  run src unicode --block "Miscellaneous Symbols"
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == $'☃\t2603\tsnowman\t'* ]]
  FZX_GLYPHS_UNICODE_DIR=/nonexistent run src unicode
  [ "$status" -eq 2 ]
  [[ "$output" == *"no /nonexistent/UnicodeData.txt"*"unicode-data"* ]]
}

@test "blocks: each block's range and named characters, its first one shown" {
  run src blocks
  [ "${#lines[@]}" -eq 5 ]
  [[ "${lines[0]}" == $'Basic Latin\t0000..007F\tBasic Latin\t-\tA Basic Latin'*' 0000..007F'*' 1' ]]
  [[ "${lines[1]}" == $'Latin-1 Supplement\t0080..00FF\t'* ]]
  [[ "${lines[4]}" == *$'\t😀 Emoticons'* ]]
}

@test "emoji: fully-qualified ones with their group and subgroup; sequences kept whole" {
  run src emoji
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == $'😀\t1F600\tgrinning face\tSmileys & Emotion / face-smiling\t😀  grinning face'* ]]
  [[ "${lines[1]}" == $'☺️\t263A FE0F\tsmiling face\t'* ]]
  [[ "${lines[2]}" == $'👨‍👩‍👧\t1F468 200D 1F469 200D 1F467\tfamily: man, woman, girl\tPeople & Body / family\t'* ]]
}

@test "preview: the glyph, its codes and escapes, and a grid of its neighbours with it marked" {
  src unicode > /dev/null
  run "$GLYPHS/preview.sh" ☃ 2603 snowman "Miscellaneous Symbols"
  [[ "$output" == *"name     snowman"* ]]
  [[ "$output" == *"code     U+2603"* ]]
  [[ "$output" == *'escape   \u2603 '* ]]
  [[ "$output" == *'utf-8    \xe2\x98\x83'* ]]
  [[ "$output" == *'html     &#x2603;'* ]]
  # the rows of 16 around it: only its own has a character the list names; the others are dots and left out
  [[ "$output" == *"02600  ·  ·  · [☃] ·  "* && "$output" != *"025F0 "* && "$output" != *"02610 "* ]]
  # without the unicode list every code point is shown; marked in reverse with colors
  rm "$FZX_CACHE_DIR/glyphs/unicode.tsv"
  run env -u NO_COLOR "$GLYPHS/preview.sh" ☃ 2603 snowman "Miscellaneous Symbols"
  [[ "$output" == *"025F0"*"02600"*$'\e[7m☃\e[0m'*"02610"* ]]
  run "$GLYPHS/preview.sh" 😀 1F600 "grinning face" Emoticons
  [[ "$output" == *'escape   \U0001F600 '* ]]
  # a sequence: every code point, no grid
  run "$GLYPHS/preview.sh" 👨‍👩‍👧 "1F468 200D 1F469 200D 1F467" "family" "People & Body / family"
  [[ "$output" == *"code     U+1F468 U+200D U+1F469 U+200D U+1F467"* && "$output" != *"1F460 "* ]]
  FZX_MODE=blocks run "$GLYPHS/preview.sh" "Basic Latin" 0000..007F "Basic Latin" -
  [ "${lines[0]}" = "Basic Latin  U+0000..U+007F" ]
  [[ "$output" == *"00040 "*" A "* ]]
}

@test "actions: code points, names and escapes to the clipboard; update downloads the glyph names" {
  "$GLYPHS/actions.sh" code EB99 "1F468 200D 1F469"
  [ "$(cat "$BATS_TEST_TMPDIR/clip")" = $'U+EB99\nU+1F468 U+200D U+1F469' ]
  "$GLYPHS/actions.sh" name nf-cod-account snowman
  [ "$(cat "$BATS_TEST_TMPDIR/clip")" = $'nf-cod-account\nsnowman' ]
  "$GLYPHS/actions.sh" escape 2603 "1F600 FE0F"
  [ "$(cat "$BATS_TEST_TMPDIR/clip")" = $'\\u2603\n\\U0001F600\\uFE0F' ]
  run "$GLYPHS/actions.sh" update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nerd Fonts 9.9.9 (2030-01-01): 120 glyphs" ]]
  run src nerd
  [ "${#lines[@]}" -eq 120 ]
  # a bad download keeps the one there
  STUB_CURL_BAD=1 run "$GLYPHS/actions.sh" update
  [ "$status" -eq 1 ]
  run src nerd
  [ "${#lines[@]}" -eq 120 ]
  run "$GLYPHS/actions.sh" bogus x
  [ "$status" -eq 2 ]
}

@test "under fzx: enter prints the glyph, opens a block in blocks; ctrl-o opens a character's block" {
  load_libs log session
  fzx::session_create glyphs "$GLYPHS"
  fzx::state_set mode nerd
  run "$FZX" _cb transform enter nf-cod-account cod
  [ "$output" = accept ]
  run "$FZX" _cb transform into nf-cod-account cod
  [ -z "$output" ]
  fzx::state_set mode blocks
  run "$FZX" _cb transform enter "Basic Latin" -
  [[ "$output" == "become:"*" -m :unicode" ]]
  local child="${output##*--resume }" args=()
  child="${child%% *}"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${args[*]}" = "--block Basic Latin" ]
  fzx::state_set mode unicode
  run "$FZX" _cb transform into snowman "Miscellaneous Symbols"
  child="${output##*--resume }" child="${child%% *}"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${args[*]}" = "--block Miscellaneous Symbols" ]
  stub_fzf
  run "$FZX" -m glyphs:unicode --block "Basic Latin"
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=Basic Latin "* ]]
  [ "$(fzf_flag --preview)" = "$FZX _cb preview {1} {2} {3} {4}" ]
  [[ "$(fzf_bind alt-c)" == *'_cb notify code {+2}'* ]]
  [[ "$(fzf_bind alt-e)" == *'_cb notify escape {+2}'* ]]
}

@test "menu: each entry's count" {
  source "$BATS_TEST_DIRNAME/../modules/glyphs/manifest.sh"
  load_libs log config
  local mode word n
  for mode in unicode blocks emoji; do
    case "$mode" in unicode) word=characters ;; *) word="$mode" ;; esac
    n="$(FZX_MODE="$mode" "$BATS_TEST_DIRNAME/../modules/glyphs/source.sh" | wc -l)"
    [ "$(glyphs::summary "glyphs:$mode")" = "$n $word" ]
  done
  [[ "$(glyphs::summary glyphs)" == *" glyphs" ]]
}

@test "menu: the Unicode entries only where the Unicode data is" {
  source "$GLYPHS/manifest.sh"
  glyphs::applicable glyphs
  glyphs::applicable glyphs:unicode
  glyphs::applicable glyphs:emoji
  FZX_GLYPHS_UNICODE_DIR=/nonexistent run glyphs::applicable glyphs:unicode
  [ "$status" -ne 0 ]
  FZX_GLYPHS_UNICODE_DIR=/nonexistent run glyphs::applicable glyphs:emoji
  [ "$status" -ne 0 ]
}
