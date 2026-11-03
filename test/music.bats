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
