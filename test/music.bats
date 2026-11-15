#!/usr/bin/env bats
# the music module against a stub mpc (a small library, a queue and two playlists) and musicman

load test_helper

MUSIC="$(readlink -f "$BATS_TEST_DIRNAME/../modules/music")"

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  # the library: albumartist, album, file, disc, track, title, artist, time, date (albumartist empty: MPD
  # falls back to the artist)
  printf '%s\n' \
    $'Mazzy Star\tAmong My Swan\tms/swan/02.mp3\t1\t2\tCry, Cry\tMazzy Star\t3:51\t1996-10-29' \
    $'Mazzy Star\tAmong My Swan\tms/swan/01.mp3\t1\t1\tDisappear\tMazzy Star\t3:23\t1996-10-29' \
    $'Mazzy Star\tShe Hangs Brightly\tms/she/01.mp3\t\t1\tHalah\tMazzy Star\t3:17\t1990' \
    $'Zero 7\tThe Garden\tz7/garden/04.mp3\t1\t4/12\tThe Pageant of the Bizarre\tZero 7\t4:25\t2006' \
    $'Zero 7\tThe Garden\tz7/garden/10.mp3\t1\t10/12\tIf I Can\'t Have You\tZero 7 feat. Sia\t4:00\t2006' \
    $'\t\tloose/single.mp3\t\t\tSingle\tSomeone\t2:00\t' > "$BATS_TEST_TMPDIR/library.tsv"
  printf '%s\n' z7/garden/04.mp3 ms/she/01.mp3 > "$BATS_TEST_TMPDIR/queue"
  printf '%s\n' ms/she/01.mp3 z7/garden/10.mp3 > "$BATS_TEST_TMPDIR/pl.chill"
  printf '%s\n' z7/garden/04.mp3 > "$BATS_TEST_TMPDIR/pl.Best"
  cat > "$STUBS/mpc" << 'STUB'
#!/usr/bin/env bash
T="$BATS_TEST_TMPDIR"
fmt=""
[[ "$1" == -f ]] && { fmt="$2"; shift 2; }
[[ "$1" == -q ]] && { shift; { printf '%s' "$*"; [[ "$1" == add && $# -eq 1 ]] && printf ' %s' $(cat); echo; } >> "$T/mpc.calls"; exit 0; }
lib() { cat "$T/library.tsv"; }
# a song by file: library columns 3..8 as the song formats want them (file disc track title artist time)
song() { awk -F'\t' -v f="$1" '$3 == f { print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8 }' "$T/library.tsv"; }
songs_of() { while IFS= read -r f; do song "$f"; done; }
# library rows as "artist<TAB>album<TAB>date<TAB>time"
rows() { awk -F'\t' -v tag="$1" '{ a = (tag == "artist" || $1 == "") ? $7 : $1; print a "\t" $2 "\t" $9 "\t" $8 }'; }
tag=albumartist
[[ "$fmt" == '[%artist%]'* ]] && tag=artist
case "$1" in
  search) lib | rows "$tag" ;;
  find)
    shift
    k="$1" a="$2" al="${4-}"
    if [[ "$fmt" == '%file%' ]]; then
      lib | awk -F'\t' -v k="$k" -v a="$a" '((k == "artist" || $1 == "") ? $7 : $1) == a { print $3 }'
    elif [[ "$fmt" == '%file%'* ]]; then
      lib | awk -F'\t' -v k="$k" -v a="$a" -v al="$al" '((k == "artist" || $1 == "") ? $7 : $1) == a && $2 == al { print $3 }' | songs_of
    else
      lib | awk -F'\t' -v k="$k" -v a="$a" '((k == "artist" || $1 == "") ? $7 : $1) == a' | rows "$k"
    fi
    ;;
  playlist)
    if [[ -n "${2:-}" ]]; then
      if [[ "$fmt" == '%file%' || -z "$fmt" ]]; then cat "$T/pl.$2"; else songs_of < "$T/pl.$2"; fi
    else
      n=0
      while IFS= read -r f; do
        n=$((n + 1))
        if [[ "$fmt" == '%file%' ]]; then echo "$f"; else
          awk -F'\t' -v f="$f" -v n="$n" '$3 == f { print n "\t" $3 "\t" $7 "\t" $6 "\t" $2 "\t" $8 }' "$T/library.tsv"; fi
      done < "$T/queue"
    fi
    ;;
  lsplaylists) printf 'chill\nBest\n' ;;
  ls) awk -F'\t' -v f="$2" '$3 == f { print $6 "\t" $7 "\t" $2 "\t" $9 "\t" $5 "\t" $4 "\t" $8 "\tTrip-Hop" }' "$T/library.tsv" ;;
  status)
    case "${2:-}" in
      '%songpos% %state%') echo "2 ${MPC_STATE:-playing}" ;;
      '%state%'*) printf 'playing\t1:02\t3:17\t2\t2\ton\toff\toff\toff\t 80%%\n' ;;
      *) echo "volume: 80%" ;;
    esac
    ;;
  albumart | readpicture) exit 1 ;;
  *) echo "$*" >> "$T/mpc.calls" ;;
esac
STUB
  cat > "$STUBS/musicman" << 'STUB'
#!/usr/bin/env bash
echo "$*" >> "$BATS_TEST_TMPDIR/musicman.calls"
printf '[{"path":"%s","rating":"4.5","grouping":"Downbeat","mood":"Mellow","context":"","copyright":"x"}]\n' "$2"
STUB
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
}

src() { FZX_MODE="$1" "$MUSIC/source.sh" "${@:2}"; }

@test "queue: position, artist - title, time, album; the current song marked, not when stopped" {
  run src queue
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = $'1\tsong\tz7/garden/04.mp3\t    1  Zero 7 - The Pageant of the Bizarre  4:25  The Garden' ]
  [ "${lines[1]}" = $'2\tsong\tms/she/01.mp3\t>   2  Mazzy Star - Halah  3:17  She Hangs Brightly' ]
  MPC_STATE=paused run src queue
  [[ "${lines[1]}" == *$'\t=   2  Mazzy Star - Halah'* ]]
  MPC_STATE=stopped run src queue
  [[ "${lines[1]}" == *$'\t    2  Mazzy Star - Halah'* ]]
}

@test "artists: album artists with album and song counts, by name; the byartist toggle uses the artist tag" {
  run src artists
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' '|')" = "Mazzy Star|Someone|Zero 7|" ]
  [ "${lines[0]}" = $'Mazzy Star\tartist\tMazzy Star\tMazzy Star  2 albums, 3 songs' ]
  [ "${lines[2]}" = $'Zero 7\tartist\tZero 7\tZero 7  1 album, 2 songs' ]
  FZX_TOGGLES=byartist run src artists
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' '|')" = "Mazzy Star|Someone|Zero 7|Zero 7 feat. Sia|" ]
}

@test "albums: by artist then year, with year, artist, songs and minutes; an artist's albums by year" {
  run src albums
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[0]}" = $'Mazzy Star\x1fShe Hangs Brightly\talbum\tMazzy Star - She Hangs Brightly\t1990  She Hangs Brightly  Mazzy Star  1 song, 3 min' ]
  [ "${lines[1]}" = $'Mazzy Star\x1fAmong My Swan\talbum\tMazzy Star - Among My Swan\t1996  Among My Swan  Mazzy Star  2 songs, 7 min' ]
  [[ "${lines[2]}" == $'Someone\x1f\talbum\tSomeone - \t      (no album)  Someone  1 song, 2 min' ]]
  run src artist --artist "Mazzy Star"
  [ "${#lines[@]}" -eq 2 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f4)" = "1990  She Hangs Brightly  1 song, 3 min
1996  Among My Swan  2 songs, 7 min" ]
  run src artist
  [ "$status" -eq 2 ]
}

@test "tracks: an album's songs in disc and track order, guests named; a playlist's with their artists" {
  run src tracks --artist "Mazzy Star" --album "Among My Swan"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'ms/swan/01.mp3\tsong\tms/swan/01.mp3\t  1  Disappear  3:23' ]
  [ "${lines[1]}" = $'ms/swan/02.mp3\tsong\tms/swan/02.mp3\t  2  Cry, Cry  3:51' ]
  run src tracks --artist "Zero 7" --album "The Garden"
  [ "$(printf '%s\n' "${lines[@]}" | cut -f4)" = "  4  The Pageant of the Bizarre  4:25
 10  If I Can't Have You  Zero 7 feat. Sia  4:00" ]
  run src tracks --playlist chill
  [ "$(printf '%s\n' "${lines[@]}" | cut -f4)" = "  1  Mazzy Star - Halah  3:17
  2  Zero 7 feat. Sia - If I Can't Have You  4:00" ]
  run src tracks
  [ "$status" -eq 2 ]
  run src queue --tag bogus
  [ "$status" -eq 2 ]
}

@test "playlists: by name, with song counts" {
  run src playlists
  [ "${lines[0]}" = $'Best\tplaylist\tBest\tBest  1 song' ]
  [ "${lines[1]}" = $'chill\tplaylist\tchill\tchill  2 songs' ]
}

@test "preview: a queued song with the player's state and musicman's fields (cached); albums, artists, playlists" {
  export FZF_PREVIEW_LINES=40 FZX_MUSIC_DIR="$BATS_TEST_TMPDIR/music"
  mkdir -p "$FZX_MUSIC_DIR/ms/she"
  : > "$FZX_MUSIC_DIR/ms/she/01.mp3"
  FZX_MODE=queue run "$MUSIC/preview.sh" -- 2 song ms/she/01.mp3
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "playing  1:02 / 3:17  2 of 2" ]
  [ "${lines[1]}" = "random, volume 80%" ]
  [ "${lines[2]}" = "Halah" ]
  [[ "$output" == *$'Mazzy Star\nShe Hangs Brightly  1990\n'* ]]
  [[ "$output" == *"length  3:17"* && "$output" == *"genre   Trip-Hop"* ]]
  [[ "$output" == *$'rating    ★★★★⯪ 4.5\ngrouping  Downbeat\nmood      Mellow\n\nms/she/01.mp3' ]]
  # empty fields and fields not in FZX_MUSIC_TAGS are left out; a second look is served from the cache
  [[ "$output" != *context* && "$output" != *copyright* ]]
  FZX_MODE=tracks run "$MUSIC/preview.sh" -- ms/she/01.mp3 song ms/she/01.mp3
  [ "${lines[0]}" = "Halah" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/musicman.calls")" -eq 1 ]
  # a changed file is asked again; off leaves musicman out
  touch -d '+1 min' "$FZX_MUSIC_DIR/ms/she/01.mp3"
  FZX_MODE=tracks run "$MUSIC/preview.sh" -- ms/she/01.mp3 song ms/she/01.mp3
  [ "$(wc -l < "$BATS_TEST_TMPDIR/musicman.calls")" -eq 2 ]
  FZX_MUSIC_MUSICMAN=off FZX_MODE=tracks run "$MUSIC/preview.sh" -- ms/she/01.mp3 song ms/she/01.mp3
  [[ "$output" != *rating* ]]
  FZX_MODE=albums run "$MUSIC/preview.sh" -- $'Mazzy Star\x1fAmong My Swan' album x
  [ "$output" = "Among My Swan
Mazzy Star

  1  Disappear  3:23
  2  Cry, Cry  3:51" ]
  FZX_MODE=artists run "$MUSIC/preview.sh" -- "Zero 7" artist "Zero 7"
  [ "$output" = "Zero 7

2006  The Garden  2 songs, 8 min" ]
  FZX_MODE=playlists run "$MUSIC/preview.sh" -- Best playlist Best
  [ "$output" = "Best

  1  Zero 7 - The Pageant of the Bizarre  4:25" ]
}

@test "actions: play, add and insert (in order) by mode; remove from the end; delete, player keys" {
  FZX_MODE=albums "$MUSIC/actions.sh" play -- $'Mazzy Star\x1fAmong My Swan'
  FZX_MODE=artists "$MUSIC/actions.sh" add -- "Zero 7"
  FZX_MODE=tracks "$MUSIC/actions.sh" insert -- a.mp3 b.mp3
  FZX_MODE=playlists "$MUSIC/actions.sh" add -- chill
  FZX_MODE=queue "$MUSIC/actions.sh" play -- 2
  FZX_MODE=queue "$MUSIC/actions.sh" remove -- 2 10 1
  FZX_MODE=playlists "$MUSIC/actions.sh" delete -- chill Best
  FZX_MODE=queue "$MUSIC/actions.sh" pause --
  FZX_MODE=queue "$MUSIC/actions.sh" previous --
  [ "$(cat "$BATS_TEST_TMPDIR/mpc.calls")" = "clear
add ms/swan/01.mp3 ms/swan/02.mp3
play
add z7/garden/04.mp3 z7/garden/10.mp3
insert b.mp3
insert a.mp3
add ms/she/01.mp3 z7/garden/10.mp3
play 2
del 10
del 2
del 1
rm chill
rm Best
toggle
prev" ]
  # the queue is not added to again; remove and delete keep to their modes
  FZX_MODE=queue run "$MUSIC/actions.sh" add -- 1
  [ "$status" -eq 1 ] && [[ "$output" == *"already queued"* ]]
  FZX_MODE=albums run "$MUSIC/actions.sh" remove -- x
  [ "$status" -eq 1 ]
  FZX_MODE=queue run "$MUSIC/actions.sh" delete -- x
  [ "$status" -eq 1 ]
  FZX_MODE=queue run "$MUSIC/actions.sh" bogus --
  [ "$status" -eq 2 ]
  # save asks for the name; an empty one saves nothing
  : > "$BATS_TEST_TMPDIR/mpc.calls"
  FZX_MODE=queue "$MUSIC/actions.sh" save -- <<< "evening"
  FZX_MODE=queue "$MUSIC/actions.sh" save -- <<< ""
  [ "$(cat "$BATS_TEST_TMPDIR/mpc.calls")" = "save evening" ]
}

@test "under fzx: enter plays a queued song, drills artists -> albums -> songs, plays an album from a song" {
  load_libs log session
  fzx::session_create music "$MUSIC"
  fzx::state_set mode queue
  run "$FZX" _cb transform enter -- 2 1
  [[ "$output" == *"reload("*"_cb source)" ]]
  grep -qx 'play 2' "$BATS_TEST_TMPDIR/mpc.calls"
  fzx::state_set mode artists
  run "$FZX" _cb transform enter -- "Mazzy Star" 0
  [[ "$output" == "become:"*" -m :artist" ]]
  local child="${output##*--resume }" args=()
  child="${child%% *}"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$child/meta/args"
  [ "${args[*]}" = "--artist Mazzy Star" ]
  printf artist > "$FZX_RUNTIME_DIR/sessions/$child/state/mode"
  FZX_SESSION="$child" run "$FZX" _cb transform enter --artist "Mazzy Star" -- $'Mazzy Star\x1fAmong My Swan' 1
  [[ "$output" == "become:"*" -m :tracks" ]]
  local grandchild="${output##*--resume }"
  grandchild="${grandchild%% *}"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$grandchild/meta/args"
  [ "${args[*]}" = "--artist Mazzy Star --album Among My Swan" ]
  # the byartist toggle carries into the drill-down
  FZX_SESSION="$child" FZX_TOGGLES=byartist run "$FZX" _cb transform enter --artist "Zero 7" -- $'Zero 7\x1fThe Garden' 0
  grandchild="${output##*--resume }" grandchild="${grandchild%% *}"
  mapfile -d '' -t args < "$FZX_RUNTIME_DIR/sessions/$grandchild/meta/args"
  [ "${args[*]}" = "--artist Zero 7 --album The Garden --tag artist" ]
  : > "$BATS_TEST_TMPDIR/mpc.calls"
  printf tracks > "$FZX_RUNTIME_DIR/sessions/$grandchild/state/mode"
  FZX_SESSION="$grandchild" run "$FZX" _cb transform enter --artist "Mazzy Star" --album "Among My Swan" -- ms/swan/02.mp3 1
  [ "$(cat "$BATS_TEST_TMPDIR/mpc.calls")" = "clear
add ms/swan/01.mp3 ms/swan/02.mp3
play 2" ]
  : > "$BATS_TEST_TMPDIR/mpc.calls"
  FZX_SESSION="$grandchild" run "$FZX" _cb transform enter --playlist chill -- z7/garden/10.mp3 1
  [ "$(cat "$BATS_TEST_TMPDIR/mpc.calls")" = "clear
load chill
play 2" ]
  fzx::state_set mode playlists
  run "$FZX" _cb transform enter -- chill 0
  [[ "$output" == "become:"*" -m :tracks" ]]
}

@test "under fzx: binds, a drill-down's header, copy takes the labels" {
  stub_fzf
  run "$FZX" -m music:tracks --artist "Mazzy Star" --album "Among My Swan"
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=Among My Swan by Mazzy Star "* ]]
  [[ "$(fzf_bind alt-a)" == *"_cb notify add --artist Mazzy\\ Star --album Among\\ My\\ Swan -- {+1}"* ]]
  [[ "$(fzf_bind ctrl-y)" == *"copy {+3}"* ]]
  [[ "$(fzf_bind enter)" == *"_cb transform enter"*"{1} {n}"* ]]
  run "$FZX" -m music:tracks --playlist chill
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=playlist chill "* ]]
}

@test "menu: applicable where mpc reaches MPD; summaries" {
  source "$MUSIC/manifest.sh"
  music::applicable music
  [ "$(music::summary music:playlists)" = "2 playlists" ]
}

# the edit tests' musicman: values lists two moods and a context in use; view gives each song its moods from
# $BATS_TEST_TMPDIR/moods.<basename>; edit is logged
edit_stubs() {
  export FZX_MUSIC_DIR="$BATS_TEST_TMPDIR/music" XDG_CACHE_HOME="$BATS_TEST_TMPDIR/xdg"
  cat > "$STUBS/musicman" << 'STUB'
#!/usr/bin/env bash
T="$BATS_TEST_TMPDIR"
case "$1" in
  values) echo "values ${*:2}" >> "$T/musicman.calls"
    printf '{"context":[{"value":"Study","count":40}],"mood":[{"value":"Mellow","count":9},{"value":"Upbeat","count":3}],"picks":[]}\n' ;;
  view) f="${2##*/}"; printf '[{"rating":"3.5","mood":"%s","context":""}]\n' "$(cat "$T/moods.$f" 2> /dev/null)" ;;
  edit) echo "edit ${*:2}" >> "$T/musicman.calls" ;;
esac
STUB
  # fzf: records its input and options, prints STUB_PICK's lines (query, key, then the picked keys' rows)
  cat > "$STUBS/fzf" << 'STUB'
#!/usr/bin/env bash
cat > "$BATS_TEST_TMPDIR/fzf.input"
printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/fzf.opts"
printf '%s\n' "${STUB_PICK:-}" | while IFS= read -r key; do
  case "$key" in QUERY=*) echo "${key#QUERY=}" ;; KEY=*) echo "${key#KEY=}" ;; *) grep "^$key"$'\t' "$BATS_TEST_TMPDIR/fzf.input" ;; esac
done
STUB
  chmod +x "$STUBS"/*
  mkdir -p "$FZX_MUSIC_DIR/ms/she" "$FZX_MUSIC_DIR/z7/garden"
  touch "$FZX_MUSIC_DIR/ms/she/01.mp3" "$FZX_MUSIC_DIR/z7/garden/04.mp3"
}
# music_fn <fn> <args...>: a music:: function with the actions loaded, music::ask answering $ANSWER
music_fn() {
  bash -c 'source "$1/lib/core.sh"; fzx::require log config; fzx::config_load "$2" music; source "$2/actions.sh"
    music::ask() { local -n _a="$1"; _a="$ANSWER"; }; shift 2; "$@"' _ "$FZX_REPO" "$MUSIC" "$@"
}

@test "rate: every selected song gets the rating, by its path under the music directory; bad ones refused" {
  edit_stubs
  ANSWER=4.5 FZX_MODE=queue run music_fn music::action rate -- ms/she/01.mp3 z7/garden/04.mp3
  [ "$status" -eq 0 ]
  grep -qxF "edit $FZX_MUSIC_DIR/ms/she/01.mp3 4.5" "$BATS_TEST_TMPDIR/musicman.calls"
  grep -qxF "edit $FZX_MUSIC_DIR/z7/garden/04.mp3 4.5" "$BATS_TEST_TMPDIR/musicman.calls"
  : > "$BATS_TEST_TMPDIR/musicman.calls"
  ANSWER=4.3 FZX_MODE=queue run music_fn music::action rate -- ms/she/01.mp3
  [ "$status" -eq 1 ] && [[ "$output" == *'not a rating'* ]]
  ANSWER=6 FZX_MODE=queue run music_fn music::action rate -- ms/she/01.mp3
  [ "$status" -eq 1 ]
  ! grep -q '^edit' "$BATS_TEST_TMPDIR/musicman.calls"
  # an empty answer changes nothing; albums are not songs
  ANSWER= FZX_MODE=queue run music_fn music::action rate -- ms/she/01.mp3
  [ "$status" -eq 0 ] && [ ! -s "$BATS_TEST_TMPDIR/musicman.calls" ]
  ANSWER=4 FZX_MODE=albums run music_fn music::action rate -- x
  [ "$status" -eq 1 ] && [[ "$output" == *'works on songs'* ]]
}

@test "rate drops the songs' cached musicman answers, so the preview reads the new rating" {
  edit_stubs
  FZX_MODE=queue "$MUSIC/preview.sh" -- 2 song ms/she/01.mp3 > /dev/null
  [ "$(ls "$FZX_CACHE_DIR/music/tags" | wc -l)" -eq 1 ]
  ANSWER=5 FZX_MODE=queue music_fn music::action rate -- ms/she/01.mp3
  [ "$(ls "$FZX_CACHE_DIR/music/tags" | wc -l)" -eq 0 ]
}

@test "tags: values marked by how many selected songs have them, every song's selected at the start" {
  edit_stubs
  echo 'Mellow,Sunny' > "$BATS_TEST_TMPDIR/moods.01.mp3"
  echo 'Mellow' > "$BATS_TEST_TMPDIR/moods.04.mp3"
  STUB_PICK=$'\n\nmood:Mellow' FZX_MODE=tracks run music_fn music::action tags -- ms/she/01.mp3 z7/garden/04.mp3
  [ "$status" -eq 0 ]
  grep -qxF 'values context mood picks --format json' "$BATS_TEST_TMPDIR/musicman.calls"
  # library values in its order, then a value only the songs have (count 0)
  run cut -f2 "$BATS_TEST_TMPDIR/fzf.input"
  [ "${lines[0]}" = '○ context   Study 40' ]
  [ "${lines[1]}" = '● mood      Mellow 9' ]
  [ "${lines[2]}" = '○ mood      Upbeat 3' ]
  [ "${lines[3]}" = '◐ mood      Sunny 0' ]
  grep -qxF -- '--bind' "$BATS_TEST_TMPDIR/fzf.opts"
  grep -qxF 'load:pos(2)+toggle+first' "$BATS_TEST_TMPDIR/fzf.opts"
  # nothing changed: Mellow kept, Sunny (some songs) left alone
  ! grep -q '^edit' "$BATS_TEST_TMPDIR/musicman.calls"
}

@test "tags: selected values are added to every song, deselected shared ones removed, alt-enter adds the query" {
  edit_stubs
  echo 'Mellow,Sunny' > "$BATS_TEST_TMPDIR/moods.01.mp3"
  echo 'Mellow' > "$BATS_TEST_TMPDIR/moods.04.mp3"
  # Mellow deselected, Upbeat and Sunny selected, a new context typed
  STUB_PICK=$'QUERY=context:Pool\nKEY=alt-enter\nmood:Upbeat\nmood:Sunny' FZX_MODE=queue \
    run music_fn music::action tags -- ms/she/01.mp3 z7/garden/04.mp3
  [ "$status" -eq 0 ]
  [ "$(grep -c '^edit' "$BATS_TEST_TMPDIR/musicman.calls")" -eq 2 ]
  local line
  line="$(grep "^edit $FZX_MUSIC_DIR/ms/she/01.mp3 " "$BATS_TEST_TMPDIR/musicman.calls")"
  [[ "$line" == *' context=+Pool '* || "$line" == *' context=+Pool' ]]
  [[ "$line" == *' mood='* && "$line" == *'+Upbeat'* && "$line" == *'+Sunny'* && "$line" == *'-Mellow'* ]]
  # a new value that is not field:value of an edited field is refused
  : > "$BATS_TEST_TMPDIR/musicman.calls"
  STUB_PICK=$'QUERY=genre:Rock\nKEY=alt-enter' FZX_MODE=queue run music_fn music::action tags -- ms/she/01.mp3
  [ "$status" -eq 1 ] && [[ "$output" == *'field:value'* ]]
  ! grep -q '^edit' "$BATS_TEST_TMPDIR/musicman.calls"
}

@test "under fzx: rate and tags get the songs' files, not queue positions" {
  stub_fzf
  run "$FZX" -m music
  [ "$status" -eq 0 ]
  [[ "$(fzf_bind 'alt-*')" == *"_cb action rate -- {+3}"* ]]
  [[ "$(fzf_bind alt-t)" == *"_cb action tags -- {+3}"* ]]
}

# the smart playlist tests' musicman (1.86+): two presets, study's songs, a back point file under the test's
# runtime dir; every call is logged with its words joined by "|" (and, for --files, what stdin held).
# MM_OLD=1: a musicman before 1.86 (no --peek --path)
smart_stubs() {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg-config" XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg-state"
  mkdir -p "$XDG_CONFIG_HOME/musicman" "$XDG_STATE_HOME/musicman" "$BATS_TEST_TMPDIR/mm-run"
  printf 'study: context:Study mood:Upbeat rating:4.5\nmazzy: artist:"Mazzy Star"\n' > "$XDG_CONFIG_HOME/musicman/smart.yml"
  : > "$BATS_TEST_TMPDIR/library.sqlite"
  printf '{"version":1,"db":{"path":"%s"}}\n' "$BATS_TEST_TMPDIR/library.sqlite" > "$XDG_STATE_HOME/musicman/paths.json"
  cat > "$BATS_TEST_TMPDIR/smart.json" << 'JSON'
[{"name":"study","terms":["context:Study","mood:Upbeat","rating:4.5"],"text":"context:Study mood:Upbeat rating:4.5","songs":3,"spotify":2},
 {"name":"mazzy","terms":["artist:Mazzy Star"],"text":"artist:\"Mazzy Star\"","songs":1,"spotify":0}]
JSON
  cat > "$BATS_TEST_TMPDIR/show.study.json" << 'JSON'
{"name":"study","songs":3,"spotify":2,"tracks":[{"artist":"Zero 7","title":"The Pageant","rating":"4.5","file":"z7/garden/04.mp3"},
 {"artist":"Mazzy Star","title":"Halah","rating":"5","file":"ms/she/01.mp3"},{"artist":"","title":"","rating":"","file":"loose/single.mp3"}]}
JSON
  cat > "$STUBS/musicman" << 'STUB'
#!/usr/bin/env bash
T="$BATS_TEST_TMPDIR"
( IFS='|'; echo "$*" ) >> "$T/musicman.calls"
[[ " $* " == *" --files - "* ]] && echo "files: $(cat | tr '\n' ' ')" >> "$T/musicman.calls"
case "$1 ${2:-}" in
  "player back")
    if [[ "$*" == *"--peek --path"* ]]; then
      [[ -n "${MM_OLD:-}" ]] && { echo "unknown switch --path" >&2; exit 1; }
      echo "$T/mm-run/back"
    fi
    ;;
  "smart --list") cat "$T/smart.json" ;;
  "smart show") [[ -f "$T/show.$3.json" ]] && cat "$T/show.$3.json" || exit 1 ;;
esac
exit 0
STUB
  chmod +x "$STUBS/musicman"
}
# calls <pattern>: how many musicman calls match the pattern
calls() { grep -c -- "$1" "$BATS_TEST_TMPDIR/musicman.calls" 2> /dev/null || true; }

@test "smart: a row per preset with its counts and terms, cached until smart.yml or the database changes" {
  smart_stubs
  run src smart
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  IFS=$'\t' read -r id kind label display <<< "${lines[0]}"
  [ "$id" = study ] && [ "$kind" = smart ] && [ "$label" = "context:Study mood:Upbeat rating:4.5" ]
  [[ "$display" == "study      3 songs      2 on Spotify  context:Study mood:Upbeat rating:4.5" ]]
  [[ "${lines[1]}" == *$'\t''mazzy      1 song       0 on Spotify  artist:"Mazzy Star"' ]]
  [ "$(calls '^smart|--list|--format|json$')" -eq 1 ]
  src smart > /dev/null
  [ "$(calls '^smart|--list')" -eq 1 ]
  # a rating changes which songs match: the database's mtime is in the key
  touch -d '+1 min' "$BATS_TEST_TMPDIR/library.sqlite"
  src smart > /dev/null
  [ "$(calls '^smart|--list')" -eq 2 ]
  touch -d '+2 min' "$XDG_CONFIG_HOME/musicman/smart.yml"
  src smart > /dev/null
  [ "$(calls '^smart|--list')" -eq 3 ]
  # one key's directory at a time
  [ "$(find "$FZX_CACHE_DIR/music/smart" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
  FZX_MUSIC_MUSICMAN=off run src smart
  [ "$status" -eq 2 ] && [[ "$output" == *"need musicman"* ]]
}

@test "split_terms: words, quoted values kept together without their quotes; an unclosed quote fails" {
  run bash -c 'source "$1/smart.sh"; music::split_terms "$2" t || exit 9; printf "<%s>" "${t[@]}"' _ "$MUSIC" \
    $'mood:Upbeat  artist:"Mazzy Star" \'free text\' title:\'say "hi"\'\t~genre:Rock'
  [ "$output" = '<mood:Upbeat><artist:Mazzy Star><free text><title:say "hi"><~genre:Rock>' ]
  run bash -c 'source "$1/smart.sh"; music::split_terms "artist:\"Mazzy" t' _ "$MUSIC"
  [ "$status" -eq 1 ]
}

@test "smart preview: terms, counts, the ratings and the first songs; the songs listed once, in the background" {
  smart_stubs
  FZX_MUSIC_SMART_SONGS=2 FZX_MODE=smart run "$MUSIC/preview.sh" -- study smart "context:Study mood:Upbeat rating:4.5"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = study ]
  [ "${lines[1]}" = "context:Study mood:Upbeat rating:4.5" ]
  [ "${lines[2]}" = "3 songs, 2 on Spotify" ]
  [ "${lines[3]}" = "5 1  4.5 1  unrated 1" ]
  [ "${lines[4]}" = "Zero 7 - The Pageant  4.5" ]
  [ "${lines[5]}" = "Mazzy Star - Halah  5" ]
  [ "${lines[6]}" = "... 1 more" ]
  FZX_MODE=smart run "$MUSIC/preview.sh" -- study smart x
  [[ "$output" == *"single.mp3"* ]]
  [ "$(calls '^smart|show|study|--format|json$')" -eq 1 ]
  # musicman cannot list them: said once, not asked again
  FZX_MODE=smart run "$MUSIC/preview.sh" -- mazzy smart x
  [[ "$output" == *"did not list the songs"* ]]
  FZX_MODE=smart "$MUSIC/preview.sh" -- mazzy smart x > /dev/null
  [ "$(calls '^smart|show|mazzy')" -eq 1 ]
  FZX_MODE=smart run "$MUSIC/preview.sh" -- gone smart x
  [ "$output" = "no smart playlist gone" ]
}

@test "smart actions: a side trip (shuffled; ordered, mpd), add each, delete, save the query, edit the terms, back" {
  smart_stubs
  FZX_MODE=smart "$MUSIC/actions.sh" play -- study mazzy
  FZX_MODE=smart FZX_TOGGLES="ordered mpd" "$MUSIC/actions.sh" play -- mazzy
  FZX_MODE=smart "$MUSIC/actions.sh" add -- study mazzy
  FZX_MODE=smart "$MUSIC/actions.sh" delete -- study mazzy
  FZX_MODE=smart "$MUSIC/actions.sh" save -- 'mood:Upbeat artist:"Mazzy Star"' <<< "upbeat"
  ANSWER='artist:"Mazzy Star" rating:4' FZX_MODE=smart music_fn music::action terms -- mazzy
  FZX_MODE=smart "$MUSIC/actions.sh" back --
  [ "$(grep -v -- '--list\|--peek' "$BATS_TEST_TMPDIR/musicman.calls")" = "player|play|--shuffle|context:Study|mood:Upbeat|rating:4.5
player|mpd|play|artist:Mazzy Star
player|add|--shuffle|context:Study|mood:Upbeat|rating:4.5
player|add|--shuffle|artist:Mazzy Star
smart|rm|study|mazzy
smart|save|upbeat|mood:Upbeat|artist:Mazzy Star
smart|save|mazzy|artist:Mazzy Star|rating:4
player|back" ]
  # no query, a bad name, an unclosed quote, a song action: refused
  FZX_MODE=smart run "$MUSIC/actions.sh" save -- ""
  [ "$status" -eq 1 ] && [[ "$output" == *"query first"* ]]
  FZX_MODE=smart run "$MUSIC/actions.sh" save -- "mood:Upbeat" <<< "two words"
  [ "$status" -eq 1 ] && [[ "$output" == *"letters, digits"* ]]
  FZX_MODE=smart run "$MUSIC/actions.sh" save -- 'artist:"Mazzy' <<< "x"
  [ "$status" -eq 1 ] && [[ "$output" == *"unclosed quote"* ]]
  FZX_MODE=smart run "$MUSIC/actions.sh" insert -- study
  [ "$status" -eq 1 ] && [[ "$output" == *"not smart playlists"* ]]
  FZX_MODE=smart run "$MUSIC/actions.sh" play -- gone
  [ "$status" -eq 1 ] && [[ "$output" == *"no smart playlist gone"* ]]
}

@test "side trips: the library modes play through musicman player mpd play --files; an older musicman keeps mpc" {
  smart_stubs
  FZX_MODE=albums "$MUSIC/actions.sh" play -- $'Mazzy Star\x1fAmong My Swan'
  FZX_MODE=playlists "$MUSIC/actions.sh" play -- chill
  [ "$(grep -v -- '--peek' "$BATS_TEST_TMPDIR/musicman.calls")" = "player|mpd|play|--files|-
files: ms/swan/01.mp3 ms/swan/02.mp3 
player|mpd|play|--files|-
files: ms/she/01.mp3 z7/garden/10.mp3 " ]
  [ ! -e "$BATS_TEST_TMPDIR/mpc.calls" ]
  # the probe's answer is kept: asked once
  [ "$(calls '--peek|--path')" -eq 1 ]
  # the queue's play is the song, through mpc
  FZX_MODE=queue "$MUSIC/actions.sh" play -- 2
  [ "$(cat "$BATS_TEST_TMPDIR/mpc.calls")" = "play 2" ]
  rm -rf "$FZX_CACHE_DIR/music/musicman" "$BATS_TEST_TMPDIR/mpc.calls"
  MM_OLD=1 FZX_MODE=albums "$MUSIC/actions.sh" play -- $'Mazzy Star\x1fAmong My Swan'
  [ "$(cat "$BATS_TEST_TMPDIR/mpc.calls")" = "clear
add ms/swan/01.mp3 ms/swan/02.mp3
play" ]
  MM_OLD=1 FZX_MODE=queue run "$MUSIC/actions.sh" back --
  [ "$status" -eq 1 ] && [[ "$output" == *"needs musicman 1.86+"* ]]
}

@test "back header: the back point under the module's header; without one the header alone; old musicman: nothing" {
  smart_stubs
  # the first answer is fetched in the background: nothing until it is in
  FZX_MODE=queue music_fn music::transform header --
  local i
  for ((i = 0; i < 50; i++)); do [[ -s "$FZX_CACHE_DIR/music/musicman/back-path" ]] && break; sleep 0.1; done
  FZX_MODE=queue run music_fn music::transform header --
  [ "$output" = "change-header()" ]
  printf 'mpd\nZero 7\nThe Pageant\n2026-11-14T22:00:00Z\n' > "$BATS_TEST_TMPDIR/mm-run/back"
  FZX_MODE=queue run music_fn music::transform header --
  [ "$output" = "change-header(back: Zero 7 - The Pageant)" ]
  FZX_MODE=artist run music_fn music::transform header --artist 'Mazzy Star' --
  [ "$output" = "change-header(albums of Mazzy Star
back: Zero 7 - The Pageant)" ]
  printf 'spotify\n\nSome Title\n\n' > "$BATS_TEST_TMPDIR/mm-run/back"
  FZX_MODE=queue run music_fn music::transform header --
  [ "$output" = "change-header(back: Some Title)" ]
  printf '' > "$FZX_CACHE_DIR/music/musicman/back-path"
  FZX_MODE=queue run music_fn music::transform header --
  [ -z "$output" ]
}

@test "under fzx with musicman: the smart mode and its keys, the load bind for the header; enter plays the main list" {
  smart_stubs
  run "$MUSIC/components.tsv"
  [[ "$output" == *$'mode\tsmart\t-\t'* ]]
  [[ "$output" == *$'toggle\tordered\talt-2\tsmart: '* && "$output" == *$'toggle\tmpd\talt-3\tsmart: '* ]]
  [[ "$output" == *$'action\tback\talt-B\t'* && "$output" == *$'action\tterms\talt-e\tsmart: '* ]]
  stub_fzf
  run "$FZX" -m music:smart
  read_fzf_args
  [[ "$(printf '%s\n' "${FZF_ARGS[@]}")" == *"load:+transform:"*"_cb transform header --"* ]]
  [[ "$(fzf_bind alt-s)" == *"_cb action save -- {q}"* ]]
  [[ "$(fzf_bind enter)" == *"_cb transform enter -- {1} {n}"* ]]
  load_libs log session
  fzx::session_create music "$MUSIC"
  fzx::state_set mode smart
  run "$FZX" _cb transform enter -- study 0
  [[ "$output" == *"reload("*"_cb source)" ]]
  grep -qx 'player|play|--main|--shuffle|context:Study|mood:Upbeat|rating:4.5' "$BATS_TEST_TMPDIR/musicman.calls"
}

@test "without musicman: no smart mode, keys or load bind; the library modes keep mpc's descriptions" {
  smart_stubs
  export FZX_MUSIC_MUSICMAN=off
  run "$MUSIC/components.tsv"
  [[ "$output" != *smart* && "$output" != *ordered* && "$output" != *$'\tback\t'* ]]
  [[ "$output" == *$'action\tplay\talt-enter\treplace the queue with the selection and play it (queue: play the song)\tnotify,reload'* ]]
  stub_fzf
  run "$FZX" -m music
  read_fzf_args
  [[ "$(printf '%s\n' "${FZF_ARGS[@]}")" != *"transform header"* ]]
}

@test "menu: the smart entry where musicman is installed, also without MPD; the presets counted from smart.yml" {
  smart_stubs
  source "$MUSIC/manifest.sh"
  music::applicable music:smart
  [ "$(music::summary music:smart)" = "2 smart playlists" ]
  FZX_MUSIC_MUSICMAN=off run music::applicable music:smart
  [ "$status" -ne 0 ]
  # no MPD: the other entries go, smart stays
  printf '#!/bin/sh\nexit 1\n' > "$STUBS/mpc"
  run music::applicable music
  [ "$status" -ne 0 ]
  music::applicable music:smart
  [ ! -s "$BATS_TEST_TMPDIR/musicman.calls" ]
}

@test "f1: rate and tags are listed in the queue and an album's or a playlist's songs only" {
  run bash -c 'source "$1/lib/core.sh"; fzx::require log config components; FZX_MODULE=music FZX_MODULE_DIR="$2"
    fzx::comp_load "$2" music; d="$(fzx::comp_rows action | awk -F"\t" "\$2 == \"rate\" { print \$4 }")"
    modes=(); while IFS=$'"'"'\t'"'"' read -r _ n _; do modes+=("$n"); done < <(fzx::comp_rows mode)
    for m in queue tracks artists albums playlists smart; do out=""; fzx::mode_desc "$d" "$m" out "${modes[@]}"; echo "$m=$out"; done' _ "$FZX_REPO" "$MUSIC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"queue=rate the selected songs"* && "$output" == *"tracks=rate the selected songs"* ]]
  [[ "$output" == *"artists="$'\n'* && "$output" == *"albums="$'\n'* && "$output" == *"playlists="$'\n'* ]]
}
