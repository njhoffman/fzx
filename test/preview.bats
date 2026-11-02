#!/usr/bin/env bats
# lib/preview.sh: detection, the renderer chains, user viewers, debug output; `fzx preview`

load test_helper

setup() {
  setup_fzx
  load_libs log preview
  D="$BATS_TEST_TMPDIR/files"
  mkdir -p "$D"
  # a PATH holding only what the renderers need besides the tools under test: stubs go in $STUBS
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  local t
  for t in bash awk sed cat head tail grep stat tr readlink dirname env sort; do
    ln -sf "$(command -v "$t")" "$STUBS/$t"
  done
  export FZF_PREVIEW_COLUMNS=80 FZF_PREVIEW_LINES=20
  unset FZX_PREVIEW_DEBUG FZX_PREVIEW_VIEWERS FZX_PREVIEW_TEXT FZX_PREVIEW_BAT_STYLE FZX_PREVIEW_IMAGE_FORMAT
}

# stub <name> [body]: a tool on the minimal PATH; the default body prints "<name> <args>"
stub() {
  local body='printf "%s %s\n" "${0##*/}" "$*"'
  printf '#!/usr/bin/env bash\n%s\n' "${2:-$body}" > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# preview with only the stubs on PATH
pv() {
  PATH="$STUBS" fzx::preview "$@"
}

detect() {
  local type how
  PATH="$STUBS" fzx::preview_detect "$1" type how
  printf '%s %s\n' "$how" "$type"
}

@test "split: a path, a grep hit (path:line:col:text), a name that holds a colon" {
  printf 'x' > "$D/a.txt"
  printf 'x' > "$D/b:12"
  fzx::preview_split "$D/a.txt" p l
  [ "$p" = "$D/a.txt" ] && [ -z "$l" ]
  fzx::preview_split "$D/a.txt:12:3:some text" p l
  [ "$p" = "$D/a.txt" ] && [ "$l" = 12 ]
  fzx::preview_split "$D/b:12" p l
  [ "$p" = "$D/b:12" ] && [ -z "$l" ]
  mkdir -p "$D/x:1"
  printf 'x' > "$D/x:1/c.txt"
  fzx::preview_split "$D/x:1/c.txt:7:hit" p l
  [ "$p" = "$D/x:1/c.txt" ] && [ "$l" = 7 ]
  fzx::preview_split "$D/nope:12" p l
  [ "$p" = "$D/nope:12" ] && [ -z "$l" ]
}

@test "split: a line that is no path falls back to its first field; a path with spaces stays whole" {
  printf 'x' > "$D/a.txt"
  printf 'x' > "$D/with space.txt"
  fzx::preview_split "$D/a.txt   12K  2026-10-28" p l
  [ "$p" = "$D/a.txt" ] && [ -z "$l" ]
  fzx::preview_split "  $D/a.txt:3:hit and more words" p l
  [ "$p" = "$D/a.txt" ] && [ "$l" = 3 ]
  fzx::preview_split "$D/with space.txt" p l
  [ "$p" = "$D/with space.txt" ] && [ -z "$l" ]
  fzx::preview_split "$D/with space.txt:9:x" p l
  [ "$p" = "$D/with space.txt" ] && [ "$l" = 9 ]
  fzx::preview_split "just some text" p l
  [ "$p" = "just some text" ] && [ -z "$l" ]
}

@test "detect: by extension, case-insensitive, without file(1)" {
  stub file 'echo should-not-run >&2; exit 1'
  local f expect
  for f in r.MD:markdown s.mp3:mp3 s.flac:audio v.mkv:video p.PNG:image i.svg:image d.pdf:pdf t.tar.gz:archive \
    z.zip:archive l.log.gz:compressed j.json:json c.pem:cert w.docx:document x.sh:text; do
    printf 'x' > "$D/${f%%:*}"
    expect="ext ${f#*:}"
    run detect "$D/${f%%:*}"
    [ "$output" = "$expect" ] || { echo "${f%%:*}: $output"; false; }
  done
}

@test "detect: directories, empty and missing files" {
  : > "$D/empty"
  run detect "$D"
  [ "$output" = "dir dir" ]
  run detect "$D/empty"
  [ "$output" = "empty empty" ]
  run detect "$D/nope"
  [ "$output" = "missing missing" ]
}

@test "detect: unknown names ask file(1) for the mime type" {
  printf 'x' > "$D/blob"
  local m expect
  for m in "text/plain; charset=us-ascii:text" "application/json; charset=us-ascii:json" "audio/mpeg; charset=binary:mp3" \
    "audio/x-flac; charset=binary:audio" "image/jpeg; charset=binary:image" "application/gzip; charset=binary:compressed" \
    "application/vnd.sqlite3; charset=binary:sqlite" "application/x-executable; charset=binary:binary" \
    "application/x-empty; charset=utf-8:text"; do
    stub file "echo '${m%:*}'"
    expect="mime ${m##*:}"
    run detect "$D/blob"
    [ "$output" = "$expect" ] || { echo "$m: $output"; false; }
  done
}

@test "detect: a .db is SQLite only with SQLite's magic; .ts is left to file(1)" {
  printf 'SQLite format 3\0rest' > "$D/real.db"
  printf 'berkeley' > "$D/other.db"
  printf 'x' > "$D/x.ts"
  stub file "echo 'application/octet-stream; charset=binary'"
  run detect "$D/real.db"
  [ "$output" = "ext sqlite" ]
  run detect "$D/other.db"
  [ "$output" = "mime binary" ]
  run detect "$D/x.ts"
  [ "$output" = "mime binary" ]
}

@test "text: bat with the style, width, and a line highlighted ten lines into the range" {
  stub bat
  printf 'x\n' > "$D/a.sh"
  run pv "$D/a.sh"
  [ "$output" = "bat --color=always --paging=never --terminal-width=80 -- $D/a.sh" ]
  run env FZX_PREVIEW_BAT_STYLE=numbers PATH="$STUBS" bash -c "source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/a.sh:42:7:hit'"
  [ "$output" = "bat --color=always --paging=never --style=numbers --terminal-width=80 --highlight-line 42 --line-range 32: -- $D/a.sh" ]
  run pv "$D/a.sh" 5
  [[ "$output" == *"--highlight-line 5 --line-range 1:"* ]]
}

@test "text: cat without bat" {
  printf 'plain\n' > "$D/a.sh"
  run pv "$D/a.sh"
  [ "$output" = plain ]
}

@test "markdown: nvcat at the preview's width, every markdown extension in any case, else bat in plain style" {
  printf '# t\n' > "$D/r.md"
  stub nvcat
  stub bat
  run pv "$D/r.md"
  [ "$output" = "nvcat --columns 80 --all --cat --fallback none --filetype markdown -- $D/r.md" ]
  local ext
  for ext in markdown mdown mdwn mkd mkdn MD Markdown; do
    printf '# t\n' > "$D/r.$ext"
    run pv "$D/r.$ext"
    [[ "$output" == "nvcat "*"--filetype markdown -- $D/r.$ext" ]]
  done
  stub nvcat 'exit 1'
  run pv "$D/r.md"
  [[ "$output" == "bat --color=always --paging=never --style=plain "* ]]
}

@test "mp3: tags named and ordered, cover summarised, noise and lyric continuations dropped" {
  printf 'x' > "$D/s.mp3"
  stub mid3v2 "cat << 'EOF'
IDv2 tag info for \$2
APIC=cover front,  (image/jpeg, 180773 bytes)
COMM=iTunNORM=eng= 00000631 00000631
COMM=Comment=eng=nice one
IPLS=[unrepresentable data]
POPM=Default=0 255/255
TALB=The Album
TIT2=The Title
TPE1=The Artist
TXXX=REPLAYGAIN_TRACK_GAIN=-2.00 dB
USLT=XXX=eng=[Intro]
second=line of lyrics
EOF"
  stub mediainfo 'echo "00:04:08  320 kb/s  44.1 kHz  2 ch"'
  run bash -c "PATH='$STUBS'; source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/s.mp3' | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "${lines[0]}" = "00:04:08  320 kb/s  44.1 kHz  2 ch" ]
  [[ "${lines[1]}" =~ ^Title\ +The\ Title$ ]]
  [[ "${lines[2]}" =~ ^Artist\ +The\ Artist$ ]]
  [[ "${lines[3]}" =~ ^Album\ +The\ Album$ ]]
  [[ "${lines[4]}" =~ ^Lyrics\ +\[Intro\]$ ]]
  [[ "${lines[5]}" =~ ^Comment\ +nice\ one$ ]]
  [[ "${lines[6]}" =~ ^Rating\ +5/5$ ]]
  [[ "${lines[7]}" =~ ^Cover\ +jpeg,\ 176K$ ]]
  [[ "${lines[8]}" =~ ^REPLAYGAIN_TRACK_GAIN\ +-2.00\ dB$ ]]
  [ "${#lines[@]}" -eq 9 ]
  [[ "$output" != *iTunNORM* && "$output" != *unrepresentable* && "$output" != *second=* ]]
}

@test "mp3: without an ID3 tag (or mid3v2), mediainfo's report, sections bold and keys aligned" {
  printf 'x' > "$D/s.mp3"
  stub mid3v2 'echo "No IDv2 tag found"'
  stub mediainfo 'printf "General\nFormat                                   : MPEG Audio\nDuration : 4 min\n"'
  run bash -c "PATH='$STUBS'; source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/s.mp3' | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "${lines[0]}" = General ]
  [[ "${lines[1]}" =~ ^Format\ {20}MPEG\ Audio$ ]]
  [[ "${lines[2]}" =~ ^Duration\ {18}4\ min$ ]]
}

@test "audio and video: ffprobe when mediainfo is missing" {
  printf 'x' > "$D/v.mkv"
  stub ffprobe
  run pv "$D/v.mkv"
  [ "$output" = "ffprobe -hide_banner -- $D/v.mkv" ]
}

@test "image: a size line, then chafa in the configured format filling the rest" {
  printf 'x' > "$D/p.png"
  stub magick 'echo "PNG 4x4"'
  stub chafa
  run env FZX_PREVIEW_IMAGE_FORMAT=sixels PATH="$STUBS" bash -c "source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/p.png' | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "${lines[0]}" = "PNG 4x4" ]
  [ "${lines[1]}" = "chafa --format=sixels --size=80x19 --animate=off -- $D/p.png" ]
}

@test "image: without chafa, an svg falls back to its source and others to the size line" {
  printf '<svg/>\n' > "$D/i.svg"
  printf 'x' > "$D/p.png"
  stub magick 'echo "PNG 4x4"'
  run pv "$D/i.svg"
  [[ "$output" == *"<svg/>"* ]]
  run bash -c "PATH='$STUBS'; source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/p.png' | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "$output" = "PNG 4x4" ]
}

@test "pdf, documents, archives: their listing tools" {
  printf 'x' > "$D/d.pdf"
  printf 'x' > "$D/w.docx"
  printf 'x' > "$D/t.tgz"
  printf 'x' > "$D/z.zip"
  stub pdftotext
  stub pandoc
  stub bsdtar
  run pv "$D/d.pdf"
  [ "$output" = "pdftotext -layout -l 3 -- $D/d.pdf -" ]
  run pv "$D/w.docx"
  [ "$output" = "pandoc -t plain --columns=80 -- $D/w.docx" ]
  run pv "$D/t.tgz"
  [ "$output" = "bsdtar -tvf $D/t.tgz" ]
  rm "$STUBS/bsdtar"
  stub unzip
  run pv "$D/z.zip"
  [ "$output" = "unzip -l -- $D/z.zip" ]
}

@test "compressed: the decompressed start, named for bat by the inner file name" {
  printf 'hello\n' | gzip > "$D/app.log.gz"
  ln -sf "$(command -v gzip)" "$STUBS/gzip"
  stub bat 'printf "bat %s | " "$*"; cat'
  run pv "$D/app.log.gz"
  [ "$output" = "bat --color=always --paging=never --file-name=app.log | hello" ]
}

@test "json: jq up to the size limit, bat beyond it" {
  printf '{"a":1}\n' > "$D/j.json"
  stub jq
  stub bat
  run pv "$D/j.json"
  [ "$output" = "jq -C . -- $D/j.json" ]
  run bash -c "PATH='$STUBS'; source '$FZX_REPO/lib/preview.sh'; _FZX_PREVIEW_JSON_MAX=2; fzx::preview '$D/j.json'"
  [[ "$output" == "bat "* ]]
}

@test "sqlite: tables and schema, read-only" {
  printf 'SQLite format 3\0' > "$D/s.sqlite"
  stub sqlite3 'case "$*" in *.tables) echo "t1  t2" ;; *.schema) echo "CREATE TABLE t1(a);" ;; esac; [[ "$*" == *-readonly* ]]'
  run bash -c "PATH='$STUBS'; source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/s.sqlite' | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "${lines[0]}" = tables ]
  [ "${lines[1]}" = "t1  t2" ]
  [ "${lines[2]}" = "CREATE TABLE t1(a);" ]
}

@test "cert: openssl for certificates (PEM or DER); a private key is named, never shown" {
  printf -- '-----BEGIN CERTIFICATE-----\nAAAA\n' > "$D/c.pem"
  printf '\x30\x82' > "$D/c.der"
  printf -- '-----BEGIN PRIVATE KEY-----\nSECRET\n' > "$D/k.pem"
  stub openssl
  run pv "$D/c.pem"
  [ "$output" = "openssl x509 -inform PEM -text -noout -in $D/c.pem" ]
  run pv "$D/c.der"
  [ "$output" = "openssl x509 -inform DER -text -noout -in $D/c.der" ]
  run pv "$D/k.pem"
  [[ "$output" == *"private key (not shown)"* ]]
  [[ "$output" != *SECRET* ]]
}

@test "binary: file's description, hexyl from 79 columns, xxd below" {
  printf '\x00\x01' > "$D/blob"
  stub file 'case "$*" in *--mime*) echo "application/octet-stream; charset=binary" ;; *) echo data ;; esac'
  stub hexyl
  stub xxd
  run bash -c "PATH='$STUBS'; source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/blob' | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "${lines[0]}" = data ]
  [ "${lines[1]}" = "hexyl -n 512 -- $D/blob" ]
  run bash -c "FZF_PREVIEW_COLUMNS=40 PATH='$STUBS'; source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/blob' | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "${lines[1]}" = "xxd -l 512 -c 8 -- $D/blob" ]
}

@test "directory: eza's tree without its root line, else lsd, else ls" {
  stub eza 'echo ROOT; echo "├── a"'
  run pv "$D"
  [ "$output" = "├── a" ]
  rm "$STUBS/eza"
  stub lsd 'echo ROOT; echo "├── b"'
  run pv "$D"
  [ "$output" = "├── b" ]
}

@test "empty and missing files" {
  : > "$D/empty"
  run bash -c "PATH='$STUBS'; source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/empty' | sed 's/\x1b\[[0-9;:]*m//g'"
  [ "$output" = "empty file" ]
  run pv "$D/nope"
  [ "$status" -eq 1 ]
  [ "$output" = "no such file: $D/nope" ]
}

@test "viewers: a glob wins over a type, a type over FZX_PREVIEW_TEXT; {} places the path" {
  printf 'x' > "$D/app.log"
  printf 'x' > "$D/a.sh"
  printf '# t\n' > "$D/r.md"
  export FZX_PREVIEW_VIEWERS="text=echo by-type; *.log = echo by-glob {} end;markdown=echo md"
  export FZX_PREVIEW_TEXT="echo text-setting"
  run pv "$D/app.log"
  [ "$output" = "by-glob $D/app.log end" ]
  run pv "$D/a.sh"
  [ "$output" = "by-type $D/a.sh" ]
  run pv "$D/r.md"
  [ "$output" = "md $D/r.md" ]
  unset FZX_PREVIEW_VIEWERS
  run pv "$D/a.sh"
  [ "$output" = "text-setting $D/a.sh" ]
  # FZX_PREVIEW_TEXT is for text only
  stub nvcat
  run pv "$D/r.md"
  [[ "$output" == nvcat* ]]
}

@test "viewers: a path with spaces and quotes reaches the command as one argument" {
  local f="$D/it's a file.sh"
  printf 'x' > "$f"
  FZX_PREVIEW_VIEWERS='text=printf "<%s>\n"' run pv "$f"
  [ "$output" = "<$f>" ]
}

@test "debug: a first line with detector, type, renderer and time; the exit code is kept" {
  printf '{}' > "$D/j.json"
  stub jq 'echo "{}"'
  FZX_PREVIEW_DEBUG=1 run bash -c "PATH='$STUBS'; source '$FZX_REPO/lib/preview.sh'; fzx::preview '$D/j.json' | sed 's/\x1b\[[0-9;:]*m//g'"
  [[ "${lines[0]}" =~ ^ext:json\ -\>\ jq\ \([0-9]+ms\)$ ]]
  [ "${lines[1]}" = "{}" ]
  [ "${#lines[@]}" -eq 2 ]
  FZX_PREVIEW_DEBUG=1 run pv "$D/nope"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "fzx preview: the subcommand renders and logs its choice at debug level" {
  printf '{"a":1}\n' > "$D/j.json"
  run "$FZX" preview "$D/j.json:1:x"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"a"'* ]]
  grep -q "preview $D/j.json: ext:json -> " "$LOG"
}

# lib/render.sh, as the modules' previews use it (stdin, a language, a name)
render() {
  PATH="$STUBS" "$@"
}

@test "render text: stdin with a language and style; NO_COLOR turns colors off; marks highlight lines" {
  stub bat 'printf "bat %s\n" "$*"; cat'
  run render fzx::render_text --language zsh --style plain <<< 'ls -la'
  [ "${lines[0]}" = "bat --color=always --paging=never --style=plain --language=zsh --terminal-width=80" ]
  [ "${lines[1]}" = "ls -la" ]
  NO_COLOR=1 run render fzx::render_text --language man <<< page
  [[ "${lines[0]}" == "bat --color=never "* ]]
  printf 'x\n' > "$D/a.sh"
  run render fzx::render_text --name a.sh --style numbers --mark 3 --mark 5 -- "$D/a.sh" < /dev/null
  [ "${lines[0]}" = "bat --color=always --paging=never --style=numbers --file-name=a.sh --terminal-width=80 --highlight-line 3 --highlight-line 5 -- $D/a.sh" ]
  # without bat: as it is
  rm "$STUBS/bat"
  run render fzx::render_text --language zsh <<< 'echo hi'
  [ "$output" = "echo hi" ]
}

@test "render text: a user viewer for named files only; stdin reaches it as a file named like the name" {
  ln -sf "$(command -v mktemp)" "$STUBS/mktemp"
  ln -sf "$(command -v rm)" "$STUBS/rm"
  stub bat
  export FZX_PREVIEW_VIEWERS='*.py=echo viewer'
  printf 'x\n' > "$D/a.py"
  run render fzx::render_text --name src/a.py -- "$D/a.py"
  [ "$output" = "viewer $D/a.py" ]
  run render fzx::render_text --name a.py <<< 'print(1)'
  [[ "$output" =~ ^viewer\ .*/render\.[A-Za-z0-9]+\.py$ ]]
  # a snippet with only a language: bat, whatever the viewers say
  FZX_PREVIEW_TEXT='echo text-setting' run render fzx::render_text --language python <<< 'print(1)'
  [[ "$output" == bat* ]]
}

@test "render markdown: viewer, nvcat, then bat (never glow); stdin spooled and removed; no stdin for the tools" {
  ln -sf "$(command -v mktemp)" "$STUBS/mktemp"
  ln -sf "$(command -v rm)" "$STUBS/rm"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  stub bat
  stub nvcat 'IFS= read -r x && echo "stdin: $x"; printf "nvcat %s\n" "$*"'
  run render fzx::render_markdown --width 50 <<< '# t'
  [[ "$output" =~ ^nvcat\ --columns\ 50\ .*--filetype\ markdown\ --\ .*/render\.[A-Za-z0-9]+\.md$ ]]
  [ -z "$(ls -A "$TMPDIR")" ]
  stub nvcat
  printf '# t\n' > "$D/r.md"
  run render fzx::render_markdown -- "$D/r.md"
  [ "$output" = "nvcat --columns 80 --all --cat --fallback none --filetype markdown -- $D/r.md" ]
  FZX_PREVIEW_VIEWERS='markdown=echo md' run render fzx::render_markdown -- "$D/r.md"
  [ "$output" = "md $D/r.md" ]
  # NO_COLOR: no renderer that draws in colors
  NO_COLOR=1 run render fzx::render_markdown -- "$D/r.md"
  [[ "$output" == "bat --color=never --paging=never --style=plain --language=markdown --terminal-width=80 --wrap=auto -- $D/r.md" ]]
  # nvcat failing: bat, even with glow installed
  stub nvcat 'exit 1'
  stub glow
  run render fzx::render_markdown -- "$D/r.md"
  [[ "$output" == "bat --color=always --paging=never --style=plain --language=markdown "* ]]
}

@test "render text: files nvcat-dispatch claims go to nvcat with its filetype; grep hits, snippets and failures to bat" {
  stub bat
  stub nvcat
  stub nvcat-dispatch '[[ "$2" == *kitty.conf || "$2" == */Justfile ]] && { case "$2" in *kitty*) echo kitty ;; *) echo just ;; esac; exit 0; }; exit 1'
  printf 'x\n' > "$D/kitty.conf"
  printf 'x\n' > "$D/a.sh"
  run pv "$D/kitty.conf"
  [ "$output" = "nvcat --columns 80 --all --cat --fallback none --filetype kitty -- $D/kitty.conf" ]
  run pv "$D/a.sh"
  [[ "$output" == bat* ]]
  # a grep hit: bat highlights the line
  run pv "$D/kitty.conf:3"
  [[ "$output" == bat*"--highlight-line 3"* ]]
  # a github blob: matched by its repository path, not the cache file's name
  run render fzx::render_text --name proj/Justfile -- "$D/a.sh" < /dev/null
  [ "$output" = "nvcat --columns 80 --all --cat --fallback none --filetype just -- $D/a.sh" ]
  NO_COLOR=1 run pv "$D/kitty.conf"
  [[ "$output" == "bat --color=never"* ]]
  stub nvcat 'exit 1'
  run pv "$D/kitty.conf"
  [[ "$output" == bat* ]]
  # longer than the cap: bat, without asking nvcat-dispatch
  stub nvcat
  seq 301 > "$D/kitty.conf"
  run pv "$D/kitty.conf"
  [[ "$output" == bat* ]]
  { echo '# t'; seq 300; } > "$D/long.md"
  run pv "$D/long.md"
  [[ "$output" == "bat "*"--language=markdown"* ]]
  FZX_PREVIEW_NVCAT_MAX_LINES=400 run pv "$D/long.md"
  [[ "$output" == nvcat* ]]
}
