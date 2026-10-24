#!/usr/bin/env bats
# the youtube module, against stub yt-dlp, mpv and ffmpeg

load test_helper

bats_require_minimum_version 1.5.0

YT_DIR="$(readlink -f "$BATS_TEST_DIRNAME/../modules/youtube")"

setup() {
  setup_fzx
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  # yt-dlp: records its args (one per line, a call per file), prints $STUB_YT_JSON, exits $STUB_YT_RC
  cat > "$STUBS/yt-dlp" << 'STUB'
#!/usr/bin/env bash
n=$(($(cat "$BATS_TEST_TMPDIR/yt.calls" 2> /dev/null || echo 0) + 1))
echo "$n" > "$BATS_TEST_TMPDIR/yt.calls"
printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/yt.args"
[[ -n "${STUB_YT_JSON:-}" ]] && printf '%s\n' "$STUB_YT_JSON"
exit "${STUB_YT_RC:-0}"
STUB
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$BATS_TEST_TMPDIR/mpv.args"\n' > "$STUBS/mpv"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/ffmpeg"
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
  export STUB_YT_JSON='{"id":"aaa","url":"https://www.youtube.com/watch?v=aaa","title":"First video","channel":"Chan","duration_string":"2:33","view_count":2081261,"description":"about it"}
{"id":"bbb","title":"Tab\there\nand line","channel":null,"duration_string":"58","view_count":999,"description":null}'
}

# source output without colors; keeps the source's exit status
src() {
  local rc
  FZF_QUERY="$1" "$YT_DIR/source.sh" > "$BATS_TEST_TMPDIR/src.out"
  rc=$?
  sed 's/\x1b\[[0-9;]*m//g' "$BATS_TEST_TMPDIR/src.out"
  return "$rc"
}

yt_calls() { cat "$BATS_TEST_TMPDIR/yt.calls" 2> /dev/null || echo 0; }

@test "empty query: the recent searches, newest first; none yet is an empty list" {
  run src ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(yt_calls)" -eq 0 ]
  src "first one" > /dev/null
  src "second one" > /dev/null
  run src "   "
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = $'search\tsecond one\t\t\t\t\t  recent  second one' ]
  [ "${lines[1]}" = $'search\tfirst one\t\t\t\t\t  recent  first one' ]
}

@test "search: yt-dlp flat search; url, fields and display; tabs and newlines flattened" {
  run src "  some query "
  [ "$status" -eq 0 ]
  mapfile -t args < "$BATS_TEST_TMPDIR/yt.args"
  [[ " ${args[*]} " == *" --flat-playlist "* ]]
  [ "${args[-1]}" = "ytsearch30:some query" ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = $'https://www.youtube.com/watch?v=aaa\tFirst video\tChan\t2:33\t2081261\tabout it\t    2:33  First video  Chan · 2.1M views' ]
  # no url: built from the id; 58 seconds shown as 0:58; no channel
  [ "${lines[1]}" = $'https://www.youtube.com/watch?v=bbb\tTab here and line\t\t0:58\t999\t\t    0:58  Tab here and line  999 views' ]
  FZX_YOUTUBE_RESULTS=5 src "other" > /dev/null
  [ "$(tail -n1 "$BATS_TEST_TMPDIR/yt.args")" = "ytsearch5:other" ]
}

@test "search: recorded in the history once, moved to the top, capped; backslashes kept" {
  src 'a\tb' > /dev/null
  src "two" > /dev/null
  src 'a\tb' > /dev/null
  [ "$(cat "$FZX_STATE_DIR/youtube/history")" = $'a\\tb\ntwo' ]
  FZX_YOUTUBE_HISTORY_MAX=2 src "three" > /dev/null
  [ "$(cat "$FZX_STATE_DIR/youtube/history")" = $'three\na\\tb' ]
}

@test "search: cached per query and results count until the ttl" {
  src "q" > /dev/null
  src "q" > /dev/null
  [ "$(yt_calls)" -eq 1 ]
  FZX_YOUTUBE_RESULTS=10 src "q" > /dev/null
  [ "$(yt_calls)" -eq 2 ]
  touch -d '2 hours ago' "$FZX_CACHE_DIR"/youtube/search/*
  run src "q"
  [ "$(yt_calls)" -eq 3 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "search failure: an error row, exit 1, nothing cached or recorded" {
  # the message goes to stderr (fzx sends it to the log); stdout has only the error row
  STUB_YT_RC=1 run --separate-stderr src "broken"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"search failed: broken"* ]]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == $'error\tsearch failed: broken'* ]]
  [ -z "$(ls -A "$FZX_CACHE_DIR/youtube/search" 2> /dev/null)" ]
  [ ! -s "$FZX_STATE_DIR/youtube/history" ]
}

@test "under fzx: the source records the query its list shows" {
  load_libs log session
  fzx::session_create youtube "$YT_DIR"
  FZF_QUERY=" cats " run "$FZX" _cb source
  [ "$status" -eq 0 ]
  [ "$(cat "$FZX_SESSION_DIR/state/youtube_query")" = cats ]
  FZF_QUERY="" run "$FZX" _cb source
  [ "$(cat "$FZX_SESSION_DIR/state/youtube_query")" = "" ]
}

@test "under fzx: enter searches a new query, accepts a video, reruns a recent search" {
  load_libs log session
  fzx::session_create youtube "$YT_DIR"
  fzx::state_set youtube_query ""
  # a new query: search (whatever the cursor is on)
  FZF_QUERY="cats" run "$FZX" _cb transform enter search "old one"
  [[ "$output" == *"reload($FZX _cb source)" ]]
  [[ "$output" != *change-query* ]]
  fzx::state_set youtube_query cats
  FZF_QUERY="cats " run "$FZX" _cb transform enter https://www.youtube.com/watch?v=aaa "First video"
  [ "$output" = accept ]
  # cleared query on the results: still accepts
  FZF_QUERY="" run "$FZX" _cb transform enter https://www.youtube.com/watch?v=aaa "First video"
  [ "$output" = accept ]
  # the recent searches list (empty query): the row's query, with a delimiter the query does not close
  fzx::state_set youtube_query ""
  FZF_QUERY="" run "$FZX" _cb transform enter search "a (b) c"
  [[ "$output" == "change-query[a (b) c]+"*"reload($FZX _cb source)" ]]
  FZF_QUERY="" run "$FZX" _cb transform enter search "plain"
  [[ "$output" == "change-query(plain)+"* ]]
  # nothing to act on
  FZF_QUERY="" run "$FZX" _cb transform enter "" ""
  [ -z "$output" ]
  FZF_QUERY="" run "$FZX" _cb transform enter error "search failed: x"
  [ -z "$output" ]
}

@test "options: no filtering, enter is the transform; standalone searches as you type" {
  stub_fzf
  run "$FZX" -m youtube
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --disabled "* ]]
  [ "$(fzf_bind enter)" = "enter:transform:$FZX _cb transform enter {1} {2}" ]
  ! fzf_bind change
  [ "$(fzf_flag --preview)" = "$FZX _cb preview {1} {2} {3} {4} {5} {6}" ]
  [ "$(fzf_bind alt-m)" = "alt-m:execute($FZX _cb action mp3 {+1})" ]
  run "$YT_DIR/module.sh"
  [ "$(fzf_bind change)" = "change:reload:sleep 0.5; $YT_DIR/source.sh" ]
  ! fzf_bind enter
}

@test "actions: play and audio get only the urls; mp3 extracts with yt-dlp into the audio dir" {
  local u=https://www.youtube.com/watch?v=aaa
  "$YT_DIR/actions.sh" audio search "$u" error
  [ "$(cat "$BATS_TEST_TMPDIR/mpv.args")" = $'--no-video\n--\n'"$u" ]
  "$YT_DIR/actions.sh" play "$u"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BATS_TEST_TMPDIR/mpv.args" ] && grep -qx -- -- "$BATS_TEST_TMPDIR/mpv.args" && ! grep -q no-video "$BATS_TEST_TMPDIR/mpv.args" && break; sleep 0.1; done
  [ "$(cat "$BATS_TEST_TMPDIR/mpv.args")" = $'--\n'"$u" ]
  FZX_YOUTUBE_AUDIO_DIR="$BATS_TEST_TMPDIR/music" run "$YT_DIR/actions.sh" mp3 search "$u"
  [ "$status" -eq 0 ]
  [ -d "$BATS_TEST_TMPDIR/music" ]
  mapfile -t args < "$BATS_TEST_TMPDIR/yt.args"
  [[ " ${args[*]} " == *" -x --audio-format mp3 "* ]]
  [[ " ${args[*]} " == *" -o $BATS_TEST_TMPDIR/music/%(title)s.%(ext)s -- $u " ]]
  # nothing selected that is a video: no call at all
  rm -f "$BATS_TEST_TMPDIR/yt.args"
  run "$YT_DIR/actions.sh" mp3 search
  [ ! -e "$BATS_TEST_TMPDIR/yt.args" ]
}

@test "actions: mp3 without ffmpeg fails before downloading" {
  rm "$STUBS/ffmpeg"
  # a PATH without the system's ffmpeg: the stubs plus what the script itself needs
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  ln -s "$(command -v bash)" "$(command -v dirname)" "$bin/"
  PATH="$STUBS:$bin" run "$YT_DIR/actions.sh" mp3 https://www.youtube.com/watch?v=aaa
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs ffmpeg"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/yt.args" ]
}

@test "preview: a video from its fields; a recent search with its cached results" {
  run "$YT_DIR/preview.sh" https://www.youtube.com/watch?v=aaa "First video" Chan 2:33 2081261 "about it"
  [ "$status" -eq 0 ]
  [[ "$output" == *"First video"* && "$output" == *"Chan"* && "$output" == *"2:33"* && "$output" == *"about it"* ]]
  [[ "$output" == *"https://www.youtube.com/watch?v=aaa"* ]]
  src "cached q" > /dev/null
  run "$YT_DIR/preview.sh" search "cached q"
  [[ "$output" == *"searches again for"*"cached q"* ]]
  [[ "$output" == *"First video"*"Tab here and line"* ]]
}

@test "manifest: needs yt-dlp and jq; summary counts recent searches" {
  load_libs log
  source "$YT_DIR/manifest.sh"
  youtube::applicable youtube
  run youtube::summary youtube
  [ -z "$output" ]
  src "one" > /dev/null
  [ "$(youtube::summary youtube)" = "1 recent searches" ]
}
