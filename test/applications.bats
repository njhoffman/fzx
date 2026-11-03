#!/usr/bin/env bats
# the applications module against fixture desktop entries in $XDG_DATA_HOME and $XDG_DATA_DIRS, a fixture
# icon theme, and a stub gtk-launch

load test_helper

APPS="$(readlink -f "$BATS_TEST_DIRNAME/../modules/applications")"

# entry <file> <lines...>: a desktop file
entry() {
  local f="$1"
  shift
  mkdir -p "${f%/*}"
  printf '%s\n' "$@" > "$f"
}

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/home" XDG_DATA_DIRS="$BATS_TEST_TMPDIR/sys:$BATS_TEST_TMPDIR/missing"
  H="$XDG_DATA_HOME/applications" S="$BATS_TEST_TMPDIR/sys/applications"
  entry "$S/editor.desktop" "[Desktop Entry]" "Type=Application" "Name=Editor" "GenericName=Text Editor" \
    "Comment=Edit text" "Categories=GTK;Utility;TextEditor;" "Icon=editor" "Exec=editor %F" "Keywords=text;" \
    "" "[Desktop Action new]" "Name=New Window" "Exec=editor --new"
  entry "$S/browser.desktop" "[Desktop Entry]" "Type=Application" "Name=System Browser" "Exec=browser"
  entry "$H/browser.desktop" "[Desktop Entry]" "Type=Application" "Name=My Browser" "Categories=Network;WebBrowser;" \
    "Icon=browser" "Exec=browser --mine"
  entry "$S/kde/tool.desktop" "[Desktop Entry]" "Type=Application" "Name=alpha tool" "Comment=Tabbed	comment" \
    "Icon=$BATS_TEST_TMPDIR/abs.png" "Exec=tool"
  entry "$S/helper.desktop" "[Desktop Entry]" "Type=Application" "Name=Helper" "NoDisplay=true" "Exec=helper"
  entry "$S/link.desktop" "[Desktop Entry]" "Type=Link" "Name=A Link" "URL=https://x/"
  entry "$S/noname.desktop" "[Desktop Entry]" "Type=Application" "Exec=x"
  # icons: the theme, the theme it inherits, hicolor, pixmaps
  export FZX_APPLICATIONS_ICON_THEME=mytheme
  I="$BATS_TEST_TMPDIR/sys/icons"
  mkdir -p "$I/mytheme" "$I/parent/apps/48" "$I/hicolor/48x48/apps" "$I/hicolor/256x256/apps" "$I/hicolor/scalable/apps" \
    "$BATS_TEST_TMPDIR/sys/pixmaps"
  printf '[Icon Theme]\nName=Mine\nInherits=parent,hicolor\n' > "$I/mytheme/index.theme"
  touch "$I/parent/apps/48/editor.png" "$I/hicolor/48x48/apps/browser.png" "$I/hicolor/256x256/apps/browser.png" \
    "$I/hicolor/scalable/apps/editor.svg" "$BATS_TEST_TMPDIR/sys/pixmaps/helper.svg" "$BATS_TEST_TMPDIR/abs.png"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  printf '#!/usr/bin/env bash\necho "gtk-launch $*" >> "%s/calls"\n' "$BATS_TEST_TMPDIR" > "$STUBS/gtk-launch"
  printf '#!/usr/bin/env bash\necho "edit $*" >> "%s/calls"\n' "$BATS_TEST_TMPDIR" > "$STUBS/ed-stub"
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
}

@test "entries: applications by name, yours over the system's, IDs from subdirectories; links and nameless left out" {
  run "$APPS/source.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f2,4 | tr '\t\n' '| ')" = "kde-tool.desktop|alpha tool editor.desktop|Editor browser.desktop|My Browser " ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | sed -n 3p)" = "$H/browser.desktop" ]
  # name, main category, comment (else the generic name)
  [[ "${lines[1]}" == *$'\tEditor                            Utility       Edit text\tEditor\teditor' ]]
  [[ "${lines[2]}" == *"My Browser                        Network       "$'\t'* ]]
  [[ "${lines[0]}" == *"Tabbed comment"* ]]
}

@test "entries: the hidden toggle lists NoDisplay ones too" {
  FZX_TOGGLES=hidden run "$APPS/source.sh"
  [ "${#lines[@]}" -eq 4 ]
  [[ "$output" == *$'helper.desktop\tHelper'* ]]
}

@test "icons: the theme, what it inherits (an SVG first), hicolor's largest PNG, pixmaps, a path" {
  source "$APPS/preview.sh" || :
  applications::icon_file editor v && [ "$v" = "$I/parent/apps/48/editor.png" ]
  applications::icon_file browser v && [ "$v" = "$I/hicolor/256x256/apps/browser.png" ]
  applications::icon_file helper v && [ "$v" = "$BATS_TEST_TMPDIR/sys/pixmaps/helper.svg" ]
  applications::icon_file "$BATS_TEST_TMPDIR/abs.png" v && [ "$v" = "$BATS_TEST_TMPDIR/abs.png" ]
  ! applications::icon_file nothing v
  [ -z "$v" ]
  ! applications::icon_file "" v
}

@test "preview: name, generic name, comment, the fields, the entry's actions and its file" {
  FZX_APPLICATIONS_ICON_ROWS=0 run "$APPS/preview.sh" "$S/editor.desktop" editor.desktop
  [ "${lines[0]}" = Editor ] && [ "${lines[1]}" = "Text Editor" ] && [ "${lines[2]}" = "Edit text" ]
  [[ "$output" == *"id          editor.desktop"*"exec        editor %F"*"categories  GTK;Utility;TextEditor;"* ]]
  [[ "$output" == *"icon        editor  $I/parent/apps/48/editor.png"* ]]
  [[ "$output" == *$'actions\n  New Window'* && "$output" != *"exec        editor --new"* ]]
  [ "${lines[${#lines[@]}-1]}" = "$S/editor.desktop" ]
  run "$APPS/preview.sh" "$S/gone.desktop" x
  [ "$output" = "no file $S/gone.desktop" ]
}

@test "actions: launch by desktop ID (yours and a subdirectory's), edit the files" {
  "$APPS/actions.sh" launch "$H/browser.desktop" "$S/kde/tool.desktop" "$S/gone.desktop"
  local i
  for ((i = 0; i < 30; i++)); do [[ "$(wc -l < "$BATS_TEST_TMPDIR/calls" 2> /dev/null)" -ge 2 ]] && break; sleep 0.1; done
  [ "$(sort "$BATS_TEST_TMPDIR/calls")" = "gtk-launch browser.desktop
gtk-launch kde-tool.desktop" ]
  rm "$BATS_TEST_TMPDIR/calls"
  VISUAL=ed-stub "$APPS/actions.sh" edit "$S/editor.desktop"
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "edit $S/editor.desktop" ]
  run "$APPS/actions.sh" bogus
  [ "$status" -eq 2 ]
}

@test "under fzx: enter launches and closes, ctrl-o launches and stays, IDs accepted" {
  stub_fzf
  run "$FZX" -m applications
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=2 "* ]]
  [[ "$(fzf_bind enter)" == "enter:become($FZX _cb action launch {+1})"* ]]
  [[ "$(fzf_bind ctrl-o)" == "ctrl-o:execute-silent($FZX _cb action launch-stay {+1})"* ]]
  [[ "$(fzf_bind ctrl-y)" == *"copy {+2}"* ]]
}

@test "menu: the desktop file count" {
  source "$APPS/manifest.sh"
  run applications::summary applications
  [[ "$output" =~ ^[0-9]+\ entries$ ]]
}
