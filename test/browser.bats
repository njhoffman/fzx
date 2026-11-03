#!/usr/bin/env bats
# the browser module against fixture profiles: a Chrome config directory (two profiles, Local State, a
# History database and Bookmarks JSON) and a Firefox one (profiles.ini, places.sqlite), built with sqlite3

load test_helper

BR="$(readlink -f "$BATS_TEST_DIRNAME/../modules/browser")"

# chrome_time <unix seconds>: Chrome's microseconds since 1601
chrome_time() { echo $((($1 + 11644473600) * 1000000)); }

setup() {
  command -v sqlite3 > /dev/null || skip "needs sqlite3"
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none TZ=UTC
  CH="$BATS_TEST_TMPDIR/chrome" FF="$BATS_TEST_TMPDIR/firefox"
  mkdir -p "$CH/Default" "$CH/Profile 2" "$CH/System Profile" "$FF/abcd.default" "$FF/wxyz.dev-edition-default"
  printf '{"profile":{"info_cache":{"Default":{"name":"Me"},"Profile 2":{"name":"Work"}}}}' > "$CH/Local State"
  local now=1767225600 # 2026-01-01 00:00 UTC
  sqlite3 "$CH/Default/History" "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER,
    typed_count INTEGER, last_visit_time INTEGER, hidden INTEGER);
    INSERT INTO urls VALUES (1, 'https://a.example/x', 'Alpha	tab', 3, 0, $(chrome_time $((now - 60))), 0);
    INSERT INTO urls VALUES (2, 'https://b.example/', 'Beta', 9, 0, $(chrome_time $((now - 7200))), 0);
    INSERT INTO urls VALUES (3, 'https://hidden.example/', 'Hidden', 1, 0, $(chrome_time now), 1);"
  sqlite3 "$CH/Profile 2/History" "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER,
    typed_count INTEGER, last_visit_time INTEGER, hidden INTEGER);
    INSERT INTO urls VALUES (1, 'https://work.example/', '', 1, 0, $(chrome_time $((now - 30))), 0);"
  cat > "$CH/Default/Bookmarks" << 'JSON'
{"roots": {"bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "children": [
  {"type": "url", "name": "Top", "url": "https://top.example/", "date_added": "13410000000000000"},
  {"type": "folder", "name": "Dev", "children": [{"type": "url", "name": "Docs", "url": "https://docs.example/", "date_added": "0"}]}]},
 "other": {"type": "folder", "name": "Other bookmarks", "children": []}, "sync_transaction_version": "1"}}
JSON
  printf '[General]\nStartWithLastProfile=1\n\n[Profile0]\nName=default\nIsRelative=1\nPath=abcd.default\nDefault=1\n\n[Profile1]\nName=dev-edition-default\nIsRelative=1\nPath=wxyz.dev-edition-default\n\n[Install1]\nDefault=abcd.default\n' > "$FF/profiles.ini"
  sqlite3 "$FF/abcd.default/places.sqlite" "CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT,
    visit_count INTEGER, hidden INTEGER, last_visit_date INTEGER);
    CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, position INTEGER,
      title TEXT, dateAdded INTEGER);
    INSERT INTO moz_places VALUES (1, 'https://fox.example/', 'Fox', 5, 0, $(((now - 120) * 1000000)));
    INSERT INTO moz_places VALUES (2, 'place:sort=8', 'Query', 0, 0, $(((now - 10) * 1000000)));
    INSERT INTO moz_places VALUES (3, 'https://never.example/', 'Never', 0, 0, NULL);
    INSERT INTO moz_bookmarks VALUES (1, 2, NULL, 0, 0, '', 0);
    INSERT INTO moz_bookmarks VALUES (2, 2, NULL, 1, 0, 'toolbar', 0);
    INSERT INTO moz_bookmarks VALUES (3, 2, NULL, 1, 1, 'tags', 0);
    INSERT INTO moz_bookmarks VALUES (4, 2, NULL, 2, 0, 'News', 0);
    INSERT INTO moz_bookmarks VALUES (5, 1, 1, 4, 0, '', $((now * 1000000)));
    INSERT INTO moz_bookmarks VALUES (6, 2, NULL, 3, 0, 'mytag', 0);
    INSERT INTO moz_bookmarks VALUES (7, 1, 1, 6, 0, NULL, 0);
    INSERT INTO moz_bookmarks VALUES (8, 1, 3, 2, 1, 'Never mind', $((now * 1000000)));"
  mkdir -p "$FZX_CONFIG_DIR/modules/browser"
  cat > "$FZX_CONFIG_DIR/modules/browser/config.sh" << EOF
FZX_BROWSER_CHROMIUM_DIRS=([chrome]="$CH" [brave]="$BATS_TEST_TMPDIR/nobrave")
FZX_BROWSER_FIREFOX_DIR="$FF"
EOF
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  for c in google-chrome firefox firefox-devedition xdg-open; do
    printf '#!/usr/bin/env bash\nprintf "%%s|" %s "$@" >> "%s/calls"; echo >> "%s/calls"\n' "$c" "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$STUBS/$c"
  done
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
}

src() { FZX_MODE="$1" "$BR/source.sh"; }

# calls_settle <n>: wait (up to 3s) for n lines in the calls file: the opens run detached
calls_settle() {
  local i
  for ((i = 0; i < 30; i++)); do
    [[ -f "$BATS_TEST_TMPDIR/calls" && "$(wc -l < "$BATS_TEST_TMPDIR/calls")" -ge "$1" ]] && return 0
    sleep 0.1
  done
  return 1
}

@test "history: every profile newest first, hidden and unvisited left out, tabs in titles cleaned" {
  run src history
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1,2 | tr '\t\n' '| ')" = "chrome:Profile 2|https://work.example/ chrome:Default|https://a.example/x firefox:abcd.default|https://fox.example/ chrome:Default|https://b.example/ " ]
  # src url display title visits date epoch label
  IFS=$'\t' read -r -a f <<< "${lines[1]}"
  [ "${f[3]}" = "Alpha tab" ] && [ "${f[4]}" = 3 ] && [ "${f[5]}" = "2025-12-31 23:59" ] && [ "${f[6]}" = 1767225540 ]
  [ "${f[7]}" = "chrome Me" ]
  [[ "${f[2]}" == "chrome Me        2025-12-31 23:59  Alpha tab "*"  https://a.example/x" ]]
  # the label column is as wide as the widest label of a profile with a database (firefox default)
  [[ "${lines[2]}" == *$'\tfirefox default  2025-12-31 23:58  Fox '* ]]
}

@test "history: the toggles pick the browsers; sort by visits" {
  FZX_TOGGLES=firefox run src history
  [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == firefox:abcd.default* ]]
  FZX_TOGGLES=chrome run src history
  [ "${#lines[@]}" -eq 3 ]
  FZX_TOGGLES="" run src history
  [ -z "$output" ]
  FZX_SORT=visits run src history
  [ "$(printf '%s\n' "${lines[@]}" | cut -f2 | head -2 | tr '\n' ' ')" = "https://b.example/ https://fox.example/ " ]
  FZX_MODE=bogus run "$BR/source.sh"
  [ "$status" -eq 2 ]
}

@test "history: a header row (FZX_SORTED_SHOW=header) over the columns, the date marked when sorted by it" {
  export FZX_SORTED_SHOW=header FZX_SORT_HEADER=1 FZX_SORTED_ARROWS='^ v'
  FZX_SORT_DESC=1 FZX_MODE=history run "$BR/source.sh"
  [[ "${lines[0]}" == $'\t\tPROFILE '*'VISITEDv'*'TITLE'*'URL' ]]
  header_aligned 2 "${lines[0]}" VISITEDv "${lines[1]}" "$(cut -f6 <<< "${lines[1]}")"
  header_aligned 2 "${lines[0]}" URL "${lines[1]}" "$(cut -f2 <<< "${lines[1]}")"
  FZX_SORT=visits FZX_MODE=history run "$BR/source.sh"
  [[ "${lines[0]}" == *'VISITED   '* && "${lines[0]}" != *'^'* ]]
}

@test "bookmarks: Chrome's folders by path, Firefox's from the root; tags and queries left out" {
  run src bookmarks
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1,2,5 | tr '\t\n' '| ')" = "chrome:Default|https://top.example/|Bookmarks bar chrome:Default|https://docs.example/|Bookmarks bar/Dev firefox:abcd.default|https://never.example/|toolbar firefox:abcd.default|https://fox.example/|toolbar/News " ]
  # a bookmark without a title takes the page's
  [ "$(printf '%s\n' "${lines[3]}" | cut -f4)" = Fox ]
  [ "$(printf '%s\n' "${lines[0]}" | cut -f6)" = 2025-12-12 ] && [ "$(printf "%s\n" "${lines[1]}" | cut -f6,7)" = $'\t0' ]
}

@test "preview: title, host and path, profile, then visits or folder" {
  FZX_MODE=history run "$BR/preview.sh" chrome:Default "https://a.example/x/y?q=1" "Alpha" 3 "2025-12-31 23:59" "chrome Me"
  [ "${lines[0]}" = Alpha ] && [ "${lines[1]}" = "https://a.example/x/y?q=1" ]
  [[ "$output" == *"host     a.example"*"path     /x/y"*"profile  chrome Me"*"visits   3"*"last     2025-12-31 23:59" ]]
  FZX_MODE=bookmarks run "$BR/preview.sh" firefox:a "https://b.example/" "" "" "" "firefox default"
  [ "${lines[0]}" = "(no title)" ]
  [[ "$output" == *"folder   (top)" && "$output" != *path* ]]
}

@test "actions: each profile's URLs in one call to its browser, detached; xdg-open; errors" {
  "$BR/actions.sh" open $'chrome:Profile 2\thttps://w/' $'firefox:wxyz.dev-edition-default\thttps://d/' \
    $'chrome:Profile 2\thttps://w2/' $'firefox:abcd.default\thttps://f/'
  calls_settle 3
  run sort "$BATS_TEST_TMPDIR/calls"
  [ "$output" = "firefox-devedition|--profile|$FF/wxyz.dev-edition-default|https://d/|
firefox|--profile|$FF/abcd.default|https://f/|
google-chrome|--profile-directory=Profile 2|https://w/|https://w2/|" ]
  rm "$BATS_TEST_TMPDIR/calls"
  "$BR/actions.sh" xdg "https://x/"
  calls_settle 1
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "xdg-open|https://x/|" ]
  run "$BR/actions.sh" open $'brave:Default\thttps://b/'
  [ "$status" -eq 1 ] && [[ "$output" == *"brave-browser not found"* ]]
  run "$BR/actions.sh" bogus
  [ "$status" -eq 2 ]
}

@test "under fzx: urls accepted, enter opens and closes, ctrl-o opens with each row's profile" {
  stub_fzf
  run "$FZX" -m browser
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=2 "* && " ${FZF_ARGS[*]} " == *" --with-nth=3 "* ]]
  [[ "$(fzf_bind enter)" == "enter:become($FZX _cb action open {+1..2})"* ]]
  [[ "$(fzf_bind ctrl-o)" == "ctrl-o:execute-silent($FZX _cb action open-stay {+1..2})"* ]]
  [[ "$(fzf_bind alt-y)" == *"notify copy-title {+4}"* ]]
}

@test "menu: where a profile directory exists; the browsers found" {
  source "$BR/config.sh"
  source "$BR/manifest.sh"
  FZX_BROWSER_CHROMIUM_DIRS=([chrome]="$CH" [brave]="$BATS_TEST_TMPDIR/nobrave")
  FZX_BROWSER_FIREFOX_DIR="$FF"
  browser::applicable
  [ "$(browser::summary browser)" = "chrome, firefox" ]
  FZX_BROWSER_CHROMIUM_DIRS=() FZX_BROWSER_FIREFOX_DIR="$BATS_TEST_TMPDIR/none"
  ! browser::applicable
}
