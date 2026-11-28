#!/usr/bin/env bats
# colors:theme and colors:pick: every color setting from the user's fzf options and fzx's layers, the
# pending edits, saving them into theme.sh (a config layer), the picker's values and the screens' binds

load test_helper

COLORS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/colors")"

setup() {
  setup_fzx
  mkdir -p "$FZX_CONFIG_DIR"
  # the user's fzf options: a comment, a quoted --color over several lines with a long name, a second one
  cat > "$BATS_TEST_TMPDIR/fzfrc" << 'EOF'
# --color=fg:1
--height=40%
--color='
  fg:#6f869f     current-bg:#181f32
  hl:#17a9b3     prompt:39:regular
'
--color dark,border:240
EOF
  export FZF_DEFAULT_OPTS_FILE="$BATS_TEST_TMPDIR/fzfrc" FZF_DEFAULT_OPTS="--color=info:108"
}

# lib: the theme's functions under a colors session (so edits have somewhere to wait)
lib() {
  load_libs log config session
  fzx::config_load "$COLORS" colors
  # shellcheck source=../modules/colors/actions.sh
  source "$COLORS/actions.sh" || :
  fzx::session_create colors "$COLORS"
  fzx::state_set mode theme
}

row() { colors::theme_values | awk -F'\t' -v id="$1" '$1 == id'; }

@test "fzf options: the --color specs of the options file then FZF_DEFAULT_OPTS, comments skipped, aliases resolved" {
  lib
  run colors::_fzf_specs
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == *"fg:#6f869f"*"current-bg:#181f32"*"prompt:39:regular"* ]]
  [ "${lines[1]}" = "dark,border:240" ]
  [ "${lines[2]}" = "info:108" ]
  run bash -c "$(declare -f colors::_color_items colors::_fzf_alias); printf '%s\n' 'dark,current-bg:#181f32 header-fg:1:bold' | colors::_color_items"
  [ "$output" = $'base\tdark\nbg+\t#181f32\nheader\t1:bold' ]
}

@test "values: each fzf key from the fzf options or FZX_FZF_COLORS, each FZX_COLORS key from the layers" {
  echo 'FZX_FZF_COLORS="hl:208"' > "$FZX_CONFIG_DIR/config.sh"
  lib
  [ "$(row fzf:fg)" = $'fzf:fg\t#6f869f\tfzf\ttext\t#6f869f' ]
  [[ "$(row fzf:bg+)" == $'fzf:bg+\t#181f32\tfzf\t'* ]]
  [[ "$(row fzf:info)" == $'fzf:info\t108\tfzf\t'* ]]
  # FZX_FZF_COLORS comes after the fzf options, as fzx passes it
  [[ "$(row fzf:hl)" == $'fzf:hl\t208\tfzx\t'* ]]
  [[ "$(row fzf:pointer)" == $'fzf:pointer\t\tdefault\t'* ]]
  [[ "$(row fzx:dim)" == $'fzx:dim\t38;5;244\tdefault\tFZX_COLORS[dim]\t38;5;244' ]]
  # a module's own key, under its name
  [[ "$(row fzx:capture_visible)" == *$'\tcapture\t'* ]]
}

@test "rows: a swatch, the value or the key it falls back to, the origin; the value and SGR in hidden fields" {
  lib
  run colors::theme
  local fg list bg
  fg="$(printf '%s\n' "${lines[@]}" | grep $'^fzf:fg\t')"
  list="$(printf '%s\n' "${lines[@]}" | grep $'^fzf:list-fg\t')"
  bg="$(printf '%s\n' "${lines[@]}" | grep $'^fzf:bg+\t')"
  [[ "$fg" == *$'\e[38;2;111;134;159m Abc '*"fg "*"#6f869f"*"fzf"*$'\t#6f869f\t38;2;111;134;159' ]]
  # unset: drawn as the key it falls back to, its own value field empty
  [[ "$list" == *"list-fg "*"(as fg)"*$'\t\t38;2;111;134;159' ]]
  # a background key as a background
  [[ "$bg" == *$'\e[48;2;24;31;50m      '* ]]
  [[ "$(printf '%s\n' "${lines[@]}" | grep $'^fzf:nth\t')" == *"(fzf's default)"*$'\t\t' ]]
}

@test "fzf values as SGR: numbers, hex, names, bright names, -1 and attributes; backgrounds as backgrounds" {
  lib
  local s
  colors::fzf_sgr "214:bold" 0 s && [ "$s" = "38;5;214;1" ]
  colors::fzf_sgr "#17a9b3:italic:underline" 0 s && [ "$s" = "38;2;23;169;179;3;4" ]
  colors::fzf_sgr "red" 0 s && [ "$s" = "31" ]
  colors::fzf_sgr "bright-blue" 1 s && [ "$s" = "104" ]
  colors::fzf_sgr "-1" 1 s && [ "$s" = "49" ]
  colors::fzf_sgr "39:regular" 0 s && [ "$s" = "38;5;39" ]
  colors::fzf_sgr "300" 0 s && [ "$s" = "" ]
}

@test "pending: edits win over the layers, the last per key; reset and revert" {
  lib
  colors::theme_pend fzf:fg 1
  colors::theme_pend fzf:fg "214:bold"
  colors::theme_pend fzx:dim "38;5;240"
  [ "$(colors::theme_pending)" = $'fzf:fg\t214:bold\nfzx:dim\t38;5;240' ]
  [[ "$(row fzf:fg)" == $'fzf:fg\t214:bold\tpending\ttext\t#6f869f' ]]
  colors::theme_reset fzf:fg
  [ "$(colors::theme_pending)" = $'fzx:dim\t38;5;240' ]
  [[ "$(row fzf:fg)" == $'fzf:fg\t#6f869f\tfzf\t'* ]]
  colors::theme_revert
  [ -z "$(colors::theme_pending)" ]
}

@test "save: the saved overrides and the edits into theme.sh, a config layer after config.sh" {
  echo 'FZX_FZF_COLORS="hl:208"' > "$FZX_CONFIG_DIR/config.sh"
  lib
  run colors::theme_save
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to save"* ]]
  colors::theme_pend fzf:fg "214:bold"
  colors::theme_pend fzf:bg+ "#000000"
  colors::theme_pend fzx:dim "38;5;240"
  colors::theme_save
  [ -z "$(colors::theme_pending)" ]
  grep -qx 'FZX_FZF_COLORS+="${FZX_FZF_COLORS:+,}fg:214:bold,bg+:#000000"' "$FZX_CONFIG_DIR/theme.sh"
  grep -qx 'FZX_COLORS\[dim\]="38;5;240"' "$FZX_CONFIG_DIR/theme.sh"
  bash -n "$FZX_CONFIG_DIR/theme.sh"
  [ "$(colors::theme_saved)" = $'fzf:fg\t214:bold\nfzf:bg+\t#000000\nfzx:dim\t38;5;240' ]
  # loaded after config.sh: it adds to FZX_FZF_COLORS, and FZX_THEME_SKIP leaves it out
  run bash -c "source '$FZX_REPO/lib/core.sh'; fzx::require log config; fzx::config_load '' ''; printf '%s %s' \"\$FZX_FZF_COLORS\" \"\${FZX_COLORS[dim]}\""
  [ "$output" = "hl:208,fg:214:bold,bg+:#000000 38;5;240" ]
  run bash -c "source '$FZX_REPO/lib/core.sh'; fzx::require log config; FZX_THEME_SKIP=1 fzx::config_load '' ''; printf '%s %s' \"\$FZX_FZF_COLORS\" \"\${FZX_COLORS[dim]}\""
  [ "$output" = "hl:208 38;5;244" ]
  # the list shows them as the theme's; a reset of a saved key waits as "reset", then saving drops it
  [[ "$(row fzf:fg)" == $'fzf:fg\t214:bold\ttheme\t'* ]]
  [[ "$(row fzx:dim)" == $'fzx:dim\t38;5;240\ttheme\t'* ]]
  colors::theme_reset fzf:fg
  [[ "$(row fzf:fg)" == $'fzf:fg\t#6f869f\treset\t'* ]]
  colors::theme_save
  grep -qx 'FZX_FZF_COLORS+="${FZX_FZF_COLORS:+,}bg+:#000000"' "$FZX_CONFIG_DIR/theme.sh"
  # what fzx gives fzf on top of the fzf options: config.sh's and the theme's, in the key table's order
  local spec
  colors::theme_fzf_spec spec
  [ "$spec" = "hl:208,bg+:#000000" ]
}

@test "picker values: a palette color or a typed one with the toggles' attributes; SGR keeps the background" {
  lib
  local v
  FZX_TOGGLES="bold italic" colors::pick_value fzf:fg "" 214 "" v && [ "$v" = "214:bold:italic" ]
  FZX_TOGGLES="" colors::pick_value fzf:fg "" "" "#17a9b3" v && [ "$v" = "#17a9b3" ]
  FZX_TOGGLES="underline" colors::pick_value fzf:fg "" "" "red" v && [ "$v" = "red:underline" ]
  # fzf's own syntax, as typed
  colors::pick_value fzf:fg "" "" "bright-red:bold:dim" v && [ "$v" = "bright-red:bold:dim" ]
  ! colors::pick_value fzf:fg "" "" "nope" v
  ! colors::pick_value fzf:fg "" "" "300" v
  colors::pick_value fzf:fg "" - "" v && [ "$v" = "-" ]
  FZX_TOGGLES="bold" colors::pick_value fzx:dim "38;5;244;48;5;236" 81 "" v && [ "$v" = "1;38;5;81;48;5;236" ]
  FZX_TOGGLES="" colors::pick_value fzx:dim "" "" "#ff0000" v && [ "$v" = "38;2;255;0;0" ]
  FZX_TOGGLES="" colors::pick_value fzx:dim "" "" "1;4;38;5;9" v && [ "$v" = "1;4;38;5;9" ]
  ! colors::pick_value fzx:dim "" "" "#ff00" v
}

@test "picker toggles from a value: fzf's attribute names, SGR codes but not a color's numbers" {
  lib
  [ "$(colors::_value_attrs fzf:fg "#8fa6bf:italic:bold")" = "italic bold" ]
  [ "$(colors::_value_attrs fzx:dim "1;38;5;3;4")" = "bold underline" ]
  # 38;2;1;2;3: the 1, 2 and 3 are the color
  [ "$(colors::_value_attrs fzx:dim "38;2;1;2;3;7")" = "reverse" ]
  [ "$(colors::_value_attrs fzx:dim "48;5;1")" = "" ]
}

@test "picker rows: a reset row, then the palette in the attributes the toggles have on" {
  FZX_TOGGLES="bold underline" FZX_MODE=pick run "$COLORS/source.sh"
  [ "${#lines[@]}" -eq 257 ]
  [[ "${lines[0]}" == -$'\t'*"reset: back to the value"* ]]
  [[ "${lines[215]}" == 214$'\t'*$'\e[1;4;38;5;214m'*$'\t#ffaf00\t1;4;38;5;214' ]]
}

@test "transforms: edit opens the picker with the value's attributes on; pick sets it and goes back" {
  lib
  local parent="$FZX_SESSION_DIR" child act
  act="$(colors::transform edit fzf:fg "#8fa6bf:italic")"
  [[ "$act" == "become:"*" --resume "*" -m :pick" ]]
  [[ "$act" =~ --resume\ ([^ ]+) ]]
  child="$FZX_SESSIONS_DIR/${BASH_REMATCH[1]}"
  [ "$(< "$child/state/toggles")" = italic ]
  [ "$(< "$child/meta/parent")" = "${parent##*/}" ]
  # in the picker: the color with the toggles on goes to the parent's edits, which reads its rows again
  export FZX_SESSION="${BASH_REMATCH[1]}" FZX_SESSION_DIR="$child"
  fzx::state_set mode pick
  FZX_TOGGLES="italic" FZF_QUERY="" run colors::transform pick 81
  [[ "$output" == "become:"*" --resume ${parent##*/}" ]]
  [ "$(< "$parent/state/theme_pending")" = $'fzf:fg\t81:italic' ]
  [ "$(< "$parent/state/fresh")" = 1 ]
  # a typed value that is no color stays in the picker and says so
  FZX_TOGGLES="" FZF_QUERY="nope" run colors::transform pick ""
  [[ "$output" == "change-footer"*"not a color: nope"* ]]
  [ "$(wc -l < "$parent/state/theme_pending")" -eq 1 ]
}

@test "under fzx: theme's enter edits the setting, pick's sets it; the picker's header; the theme keys" {
  stub_fzf
  run "$FZX" -m colors:theme
  [ "$status" -eq 0 ]
  [ "$(fzf_bind enter)" = "enter:transform:$FZX _cb transform edit {1} {3}" ]
  [[ "$(fzf_bind alt-x)" == *'_cb notify reset {+1}'* ]]
  [[ "$(fzf_bind alt-k)" == *'_cb notify save'*'_cb nav restart'* ]]
  [[ "$(fzf_bind alt-z)" == *'_cb action revert'* ]]
  run "$FZX" -m colors:pick --key fzf:hl --value "#17a9b3"
  [ "$status" -eq 0 ]
  [ "$(fzf_bind enter)" = "enter:transform:$FZX _cb transform pick {1}" ]
  read_fzf_args
  printf '%s\n' "${FZF_ARGS[@]}" | grep -qxF -- "--header=hl: #17a9b3  type #rrggbb, 0-255 or fzf's syntax for your own"
}

@test "preview: what the key colors, its value, a sample; a background as a band" {
  FZX_MODE=theme run "$COLORS/preview.sh" fzf:list-fg "" ""
  [[ "$output" == *"fzf --color"*"list-fg"*"text in the list section"*"when unset it is drawn as fg"* ]]
  [[ "$output" == *"(not set)"* ]]
  FZX_MODE=theme run "$COLORS/preview.sh" fzf:bg+ "#181f32" "48;2;24;31;50"
  [[ "$output" == *$'\e[48;2;24;31;50m  The quick brown fox'* ]]
  FZX_MODE=theme run "$COLORS/preview.sh" fzx:dim "38;5;244" "38;5;244"
  [[ "$output" == *"FZX_COLORS[dim]"*$'\e[38;5;244mThe quick brown fox'* ]]
}
