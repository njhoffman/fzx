#!/usr/bin/env bash
# preview: a file's contents rendered by its type, for the files module and for plain fzf (`fzx preview`,
# which ~/.shell/scripts/fzf-preview runs). Detection goes by extension first and asks file(1) only for
# names it does not know; each type has a chain of renderers, the first one installed and succeeding wins.
# Runs on every focus change: no config loading, one process per step at most.
#
# Settings (environment, or ~/.config/fzx/config.sh for fzx's own modules):
#   FZX_PREVIEW_TEXT     command for text and code (default: bat); the path is appended, or replaces {}
#   FZX_PREVIEW_VIEWERS  per-type commands, "KEY=COMMAND;KEY=COMMAND"; KEY is a type (markdown, mp3,
#                        audio, video, image, pdf, archive, compressed, json, sqlite, cert, document,
#                        binary, text) or a glob on the file name (*.log); globs win over types
#   FZX_PREVIEW_DEBUG    1: a first line saying how the file was detected and rendered, and how long it took
#   FZX_PREVIEW_IMAGE_FORMAT  chafa's --format (default symbols)
#   FZX_PREVIEW_BAT_STYLE     bat's --style (default: bat's own config)

# largest JSON file jq pretty-prints; bigger ones go to bat, which streams
_FZX_PREVIEW_JSON_MAX=$((1024 * 1024))
# bytes of an unknown binary shown as hex
_FZX_PREVIEW_HEX_BYTES=512

# fzx::preview_split <item> <path var> <line var>: "path", "path:line" or "path:line:col:..." (grep hits)
# into a path and a line number; the whole item is the path when it names a file as it is. A line that is
# none of these is tried again by its first field ("path  size  date" listings, plain fzf's {}), and is the
# path unchanged when that fails too.
fzx::preview_split() {
  local _item _path="$1" _line="" _head _rest _first
  _first="${1#"${1%%[![:space:]]*}"}"
  _first="${_first%%[[:space:]]*}"
  for _item in "$1" "$_first"; do
    [[ -n "$_item" ]] || continue
    if [[ -e "$_item" ]]; then
      _path="$_item"
      break
    fi
    _head="" _rest="$_item"
    # the shortest prefix that exists and is followed by :digits (a path may itself hold colons)
    while [[ "$_rest" == *:* ]]; do
      _head+="${_rest%%:*}"
      _rest="${_rest#*:}"
      if [[ -e "$_head" && "$_rest" =~ ^([0-9]+)(:|$) ]]; then
        _path="$_head" _line="${BASH_REMATCH[1]}"
        break 2
      fi
      _head+=:
    done
  done
  printf -v "$2" '%s' "$_path"
  printf -v "$3" '%s' "$_line"
}

# fzx::preview_detect <path> <type var> <detector var>: the type key and how it was found (dir, empty,
# missing, ext, mime)
fzx::preview_detect() {
  local _p="$1" _type="" _how=ext _name="${1##*/}" _mime
  _name="${_name,,}"
  if [[ -d "$_p" ]]; then
    _type=dir _how=dir
  elif [[ ! -e "$_p" ]]; then
    _type=missing _how=missing
  elif [[ ! -s "$_p" ]]; then
    _type=empty _how=empty
  else
    case "$_name" in
      *.md | *.markdown | *.mdown | *.mkd | *.mkdn | *.mdwn) _type=markdown ;;
      *.mp3) _type=mp3 ;;
      *.flac | *.ogg | *.oga | *.opus | *.m4a | *.aac | *.wav | *.wma | *.aiff | *.ape) _type=audio ;;
      *.mp4 | *.mkv | *.webm | *.avi | *.mov | *.wmv | *.flv | *.m4v | *.mpg | *.mpeg) _type=video ;;
      *.png | *.jpg | *.jpeg | *.gif | *.webp | *.bmp | *.tif | *.tiff | *.ico | *.avif | *.heic | *.svg) _type=image ;;
      *.pdf) _type=pdf ;;
      *.tar | *.tar.* | *.tgz | *.tbz | *.tbz2 | *.txz | *.tzst | *.zip | *.jar | *.war | *.apk | *.7z | *.rar | *.iso | *.deb | *.rpm | *.cpio | *.xpi | *.whl)
        _type=archive
        ;;
      *.gz | *.xz | *.bz2 | *.zst | *.lz4 | *.lzma) _type=compressed ;;
      *.json | *.geojson) _type=json ;;
      *.sqlite | *.sqlite3 | *.db) _type=sqlite ;;
      *.pem | *.crt | *.cer | *.der) _type=cert ;;
      *.docx | *.odt | *.epub | *.rtf | *.fb2) _type=document ;;
      *.sh | *.bash | *.zsh | *.py | *.js | *.mjs | *.tsx | *.jsx | *.lua | *.go | *.rs | *.c | *.h | *.cpp | *.hpp | *.java | *.rb | *.pl | *.vim | *.txt | *.yaml | *.yml | *.toml | *.ini | *.conf | *.cfg | *.css | *.html | *.xml | *.csv | *.tsv | *.log | *.diff | *.patch | *.bats | *.nix | *.sql)
        _type=text
        ;;
    esac
    # a .db that is not SQLite (Berkeley DB, anything else) is left to file(1)
    if [[ "$_type" == sqlite && "$_name" == *.db ]]; then
      local _magic=""
      read -r -n 15 _magic < "$_p" 2> /dev/null
      [[ "$_magic" == "SQLite format 3" ]] || _type=""
    fi
    if [[ -z "$_type" ]]; then
      _how=mime
      _mime="$(command file --brief --dereference --mime -- "$_p" 2> /dev/null)"
      case "$_mime" in
        application/json*) _type=json ;;
        text/markdown*) _type=markdown ;;
        inode/x-empty*) _type=empty ;;
        audio/mpeg*) _type=mp3 ;;
        audio/*) _type=audio ;;
        video/*) _type=video ;;
        image/*) _type=image ;;
        application/pdf*) _type=pdf ;;
        application/zip* | application/x-tar* | application/x-7z* | application/x-rar* | application/vnd.rar* | application/x-iso9660*) _type=archive ;;
        application/gzip* | application/x-xz* | application/x-bzip2* | application/zstd* | application/x-lz4*) _type=compressed ;;
        application/vnd.sqlite3* | application/x-sqlite3*) _type=sqlite ;;
        application/epub* | application/vnd.oasis.opendocument.text* | application/vnd.openxmlformats-officedocument.wordprocessingml*) _type=document ;;
        *"charset=binary"*) _type=binary ;;
        *) _type=text ;;
      esac
    fi
  fi
  printf -v "$2" '%s' "$_type"
  printf -v "$3" '%s' "$_how"
}

# fzx::preview_viewer <path> <type> <var>: the user's command for this file (FZX_PREVIEW_VIEWERS; text also
# FZX_PREVIEW_TEXT), empty when there is none
fzx::preview_viewer() {
  local _name="${1##*/}" _type="$2" _entry _key _glob="" _bytype="" _entries
  IFS=';' read -r -a _entries <<< "${FZX_PREVIEW_VIEWERS:-}"
  for _entry in "${_entries[@]}"; do
    [[ "$_entry" == *=* ]] || continue
    _key="${_entry%%=*}"
    _key="${_key//[[:space:]]/}"
    if [[ "$_key" == *[*?[]* ]]; then
      # shellcheck disable=SC2053  # the key is a glob
      [[ -z "$_glob" && "$_name" == $_key ]] && _glob="${_entry#*=}"
    elif [[ -z "$_bytype" && "$_key" == "$_type" ]]; then
      _bytype="${_entry#*=}"
    fi
  done
  [[ -z "$_glob$_bytype" && "$_type" == text ]] && _bytype="${FZX_PREVIEW_TEXT:-}"
  printf -v "$3" '%s' "${_glob:-$_bytype}"
}

# fzx::_preview_user <command> <path>: a user command, through bash so it may hold options and pipes; the
# path replaces {} or is appended
fzx::_preview_user() {
  local cmd="$1"
  if [[ "$cmd" == *"{}"* ]]; then
    cmd="${cmd//\{\}/\"\$1\"}"
  else
    # shellcheck disable=SC2016  # $1 is the inner bash's
    cmd+=' "$1"'
  fi
  bash -c "$cmd" fzx-preview "$2"
}

# renderers: fzx::_pv_<type> <path> <line>; each sets _FZX_PV_RENDERER to the tool that drew the preview
# and fails when none of its tools could

fzx::_pv_text() {
  if command -v bat > /dev/null; then
    local args=(--color=always --paging=never) line="$2"
    [[ -n "${FZX_PREVIEW_BAT_STYLE:-}" ]] && args+=("--style=$FZX_PREVIEW_BAT_STYLE")
    [[ -n "${FZF_PREVIEW_COLUMNS:-}" ]] && args+=("--terminal-width=$FZF_PREVIEW_COLUMNS")
    [[ "$line" =~ ^[0-9]+$ ]] && args+=(--highlight-line "$line" --line-range "$((line > 10 ? line - 10 : 1)):")
    _FZX_PV_RENDERER=bat
    command bat "${args[@]}" -- "$1" && return 0
  fi
  _FZX_PV_RENDERER="cat"
  command cat -- "$1"
}

fzx::_pv_markdown() {
  if command -v mdpreview > /dev/null; then
    _FZX_PV_RENDERER=mdpreview
    command mdpreview --columns "${FZF_PREVIEW_COLUMNS:-80}" --all -- "$1" 2> /dev/null < /dev/null && return 0
  fi
  FZX_PREVIEW_BAT_STYLE="${FZX_PREVIEW_BAT_STYLE:-plain}" fzx::_pv_text "$@"
}

# fzx::preview_id3: mid3v2's frames as "Name  value" rows, the common ones first in a fixed order: frame ids
# named, the cover summarised, noise frames (iTunes normalisation, unrepresentable data) dropped
fzx::preview_id3() {
  awk -v dim=$'\e[38;5;244m' -v key=$'\e[38;5;110m' -v rst=$'\e[0m' '
    BEGIN {
      n = split("TIT2 Title TPE1 Artist TALB Album TPE2 Album-artist TRCK Track TPOS Disc TDRC Year TYER Year " \
        "TCON Genre TCOM Composer TBPM BPM TKEY Key TLEN Length TPUB Label TCOP Copyright TSRC ISRC " \
        "TIT1 Grouping TIT3 Subtitle TENC Encoded-by TSSE Encoder TLAN Language TMED Media TCMP Compilation " \
        "TOPE Original-artist TDOR Original-date TORY Original-year TSOP Artist-sort TSOA Album-sort " \
        "USLT Lyrics WXXX URL", a, " ")
      for (i = 1; i < n; i += 2) { name[a[i]] = a[i + 1]; gsub(/-/, " ", name[a[i]]); rank[a[i]] = i }
      rank["COMM"] = 900; rank["POPM"] = 901; rank["APIC"] = 902
    }
    NR == 1 && /^IDv2 tag info/ { next }
    {
      # frames are "ID=value"; other lines continue a multi-line frame (lyrics, comments) and are dropped
      if ($0 !~ /^[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]=/) next
      id = substr($0, 1, 4); val = substr($0, 6)
      if (val ~ /unrepresentable data/ || val ~ /^iTun(NORM|SMPB|PGAP)/ || id == "PRIV" || id == "MCDI") next
      color = key
      if (id == "APIC") {
        if (!match(val, /\(image\/[a-z]+, [0-9]+ bytes\)/)) next
        split(substr(val, RSTART + 1, RLENGTH - 2), p, /, | /); sub(/image\//, "", p[1])
        label = "Cover"; val = p[1] ", " int(p[2] / 1024) "K"
      } else if (id == "COMM" || id == "USLT") { sub(/^[^=]*=[A-Za-z][A-Za-z][A-Za-z]=/, "", val); label = (id == "COMM") ? "Comment" : "Lyrics" }
      else if (id == "TXXX") { label = substr(val, 1, index(val, "=") - 1); val = substr(val, index(val, "=") + 1); color = dim }
      else if (id == "POPM") { split(val, r, " "); sub(/\/.*/, "", r[2]); label = "Rating"; val = int(r[2] * 5 / 255 + 0.5) "/5" }
      else if (id in name) label = name[id]
      else { label = id; color = dim }
      if (length(label) > 28) label = substr(label, 1, 28)
      if (length(label) > w) w = length(label)
      rows++; lab[rows] = label; col[rows] = color; v[rows] = val; rk[rows] = (id in rank) ? rank[id] : 1000 + rows
    }
    END {
      for (i = 2; i <= rows; i++) for (j = i; j > 1 && rk[j - 1] > rk[j]; j--) {
        t = rk[j]; rk[j] = rk[j - 1]; rk[j - 1] = t; t = lab[j]; lab[j] = lab[j - 1]; lab[j - 1] = t
        t = col[j]; col[j] = col[j - 1]; col[j - 1] = t; t = v[j]; v[j] = v[j - 1]; v[j - 1] = t }
      for (i = 1; i <= rows; i++) printf "%s%-*s%s  %s\n", col[i], w, lab[i], rst, v[i]
    }'
}

fzx::_pv_mp3() {
  local tags=""
  command -v mid3v2 > /dev/null && tags="$(command mid3v2 -- "$1" 2> /dev/null)"
  if [[ "$tags" == "IDv2 tag info"* ]]; then
    _FZX_PV_RENDERER=mid3v2
    if command -v mediainfo > /dev/null; then
      local stream
      stream="$(command mediainfo --Inform='Audio;%Duration/String3%  %BitRate/String%  %SamplingRate/String%  %Channel(s)% ch' -- "$1" 2> /dev/null)"
      [[ -n "${stream// /}" ]] && printf '\e[38;5;244m%s\e[0m\n\n' "$stream"
    fi
    fzx::preview_id3 <<< "$tags"
    return 0
  fi
  fzx::_pv_audio "$@"
}

# fzx::preview_sections: "Key : value" reports (mediainfo, exiftool) with section titles bold, keys dim
fzx::preview_sections() {
  awk -v b=$'\e[1m' -v dim=$'\e[38;5;244m' -v rst=$'\e[0m' '
    /^[^ :][^:]*$/ { print b $0 rst; next }
    index($0, " : ") { k = substr($0, 1, index($0, " : ") - 1); sub(/ +$/, "", k)
      printf "%s%-26s%s%s\n", dim, k, rst, substr($0, index($0, " : ") + 3); next }
    { print }'
}

fzx::_pv_audio() {
  if command -v mediainfo > /dev/null; then
    _FZX_PV_RENDERER=mediainfo
    command mediainfo -- "$1" 2> /dev/null | fzx::preview_sections && return 0
  fi
  if command -v ffprobe > /dev/null; then
    _FZX_PV_RENDERER=ffprobe
    command ffprobe -hide_banner -- "$1" 2>&1 && return 0
  fi
  fzx::_pv_binary "$@"
}

fzx::_pv_video() { fzx::_pv_audio "$@"; }

fzx::_pv_image() {
  local cols="${FZF_PREVIEW_COLUMNS:-80}" lines="${FZF_PREVIEW_LINES:-40}" info="" identify=identify
  command -v magick > /dev/null && identify="magick identify"
  if command -v "${identify%% *}" > /dev/null; then
    # shellcheck disable=SC2086  # "magick identify" is two words
    info="$(command $identify -format '%m %wx%h' -- "$1[0]" 2> /dev/null)"
  fi
  [[ -n "$info" ]] && printf '\e[38;5;244m%s\e[0m\n' "$info" && lines=$((lines - 1))
  if command -v chafa > /dev/null; then
    _FZX_PV_RENDERER=chafa
    command chafa --format="${FZX_PREVIEW_IMAGE_FORMAT:-symbols}" --size="${cols}x$((lines > 1 ? lines : 1))" \
      --animate=off -- "$1" 2> /dev/null && return 0
  fi
  [[ "${1,,}" == *.svg ]] && fzx::_pv_text "$@" && return 0
  [[ -n "$info" ]] && _FZX_PV_RENDERER=identify && return 0
  fzx::_pv_binary "$@"
}

fzx::_pv_pdf() {
  if command -v pdftotext > /dev/null; then
    _FZX_PV_RENDERER=pdftotext
    command pdftotext -layout -l 3 -- "$1" - 2> /dev/null && return 0
  fi
  fzx::_pv_binary "$@"
}

fzx::_pv_archive() {
  local name="${1,,}"
  if [[ "$name" == *.deb ]] && command -v dpkg-deb > /dev/null; then
    _FZX_PV_RENDERER=dpkg-deb
    { command dpkg-deb --info -- "$1" && command dpkg-deb --contents -- "$1"; } 2> /dev/null && return 0
  fi
  if command -v bsdtar > /dev/null; then
    _FZX_PV_RENDERER=bsdtar
    command bsdtar -tvf "$1" 2> /dev/null && return 0
  fi
  if command -v 7z > /dev/null; then
    _FZX_PV_RENDERER=7z
    command 7z l -- "$1" 2> /dev/null && return 0
  fi
  if [[ "$name" == *.zip ]] && command -v unzip > /dev/null; then
    _FZX_PV_RENDERER=unzip
    command unzip -l -- "$1" 2> /dev/null && return 0
  fi
  fzx::_pv_binary "$@"
}

# a compressed single file: its decompressed start, highlighted for the name without the extension
fzx::_pv_compressed() {
  local tool inner="${1%.*}"
  case "${1,,}" in
    *.gz) tool=(gzip -dc) ;;
    *.xz | *.lzma) tool=(xz -dc) ;;
    *.bz2) tool=(bzip2 -dc) ;;
    *.zst) tool=(zstd -dcq) ;;
    *.lz4) tool=(lz4 -dc) ;;
    *) tool=() ;;
  esac
  if ((${#tool[@]})) && command -v "${tool[0]}" > /dev/null; then
    _FZX_PV_RENDERER="${tool[0]}"
    if command -v bat > /dev/null; then
      # bat names the language after --file-name; head stops the decompressor on large files
      command "${tool[@]}" -- "$1" 2> /dev/null | head -c 1048576 |
        command bat --color=always --paging=never --file-name="${inner##*/}" && return 0
    else
      command "${tool[@]}" -- "$1" 2> /dev/null | head -c 1048576 && return 0
    fi
  fi
  fzx::_pv_binary "$@"
}

fzx::_pv_json() {
  local size
  size="$(stat -L -c %s -- "$1" 2> /dev/null || echo 0)"
  if ((size <= _FZX_PREVIEW_JSON_MAX)) && command -v jq > /dev/null; then
    _FZX_PV_RENDERER=jq
    command jq -C . -- "$1" 2> /dev/null && return 0
  fi
  fzx::_pv_text "$@"
}

fzx::_pv_sqlite() {
  if command -v sqlite3 > /dev/null; then
    local tables schema
    # -readonly and a short busy timeout: a database another program holds (a browser's) fails fast
    tables="$(command sqlite3 -readonly -cmd '.timeout 200' -- "$1" .tables 2> /dev/null)" &&
      schema="$(command sqlite3 -readonly -cmd '.timeout 200' -- "$1" .schema 2> /dev/null)" && {
      _FZX_PV_RENDERER=sqlite3
      printf '\e[1mtables\e[0m\n%s\n\n' "$tables"
      if command -v bat > /dev/null; then
        command bat --color=always --paging=never --style=plain --language=sql <<< "$schema"
      else
        printf '%s\n' "$schema"
      fi
      return 0
    }
  fi
  fzx::_pv_binary "$@"
}

fzx::_pv_cert() {
  # a private key is named, never shown: the preview would put it on screen and in scrollback
  if grep -q -m1 -e '-----BEGIN .*PRIVATE KEY-----' -- "$1" 2> /dev/null; then
    _FZX_PV_RENDERER=none
    printf '\e[38;5;244mprivate key (not shown)\e[0m\n'
    grep -m1 -e '-----BEGIN ' -- "$1"
    return 0
  fi
  if command -v openssl > /dev/null; then
    local form=PEM
    grep -q -m1 -e '-----BEGIN ' -- "$1" 2> /dev/null || form=DER
    _FZX_PV_RENDERER=openssl
    command openssl x509 -inform "$form" -text -noout -in "$1" 2> /dev/null < /dev/null && return 0
  fi
  [[ "$form" == DER ]] && fzx::_pv_binary "$@" && return 0
  fzx::_pv_text "$@"
}

fzx::_pv_document() {
  if command -v pandoc > /dev/null; then
    _FZX_PV_RENDERER=pandoc
    command pandoc -t plain --columns="${FZF_PREVIEW_COLUMNS:-80}" -- "$1" 2> /dev/null && return 0
  fi
  fzx::_pv_archive "$@"
}

fzx::_pv_binary() {
  local cols="${FZF_PREVIEW_COLUMNS:-80}"
  command -v file > /dev/null && printf '\e[38;5;244m%s\e[0m\n' "$(command file --brief --dereference -- "$1")"
  # hexyl's fixed layout needs 79 columns; narrower previews get xxd, 8 bytes per row
  if ((cols >= 79)) && command -v hexyl > /dev/null; then
    _FZX_PV_RENDERER=hexyl
    command hexyl -n "$_FZX_PREVIEW_HEX_BYTES" -- "$1" 2> /dev/null && return 0
  fi
  if command -v xxd > /dev/null; then
    _FZX_PV_RENDERER=xxd
    command xxd -l "$_FZX_PREVIEW_HEX_BYTES" -c "$((cols >= 70 ? 16 : 8))" -- "$1" 2> /dev/null && return 0
  fi
  _FZX_PV_RENDERER="file"
}

fzx::_pv_dir() {
  if command -v eza > /dev/null; then
    _FZX_PV_RENDERER=eza
    # the first line is the directory itself
    command eza --color=always --icons --group-directories-first -a --tree --level=2 -- "$1" 2> /dev/null |
      tail -n +2
    return 0
  fi
  if command -v lsd > /dev/null; then
    _FZX_PV_RENDERER=lsd
    command lsd --color=always --tree --depth=2 -a -- "$1" 2> /dev/null | tail -n +2
    return 0
  fi
  _FZX_PV_RENDERER="ls"
  command ls -la --color=always -- "$1"
}

fzx::_pv_empty() {
  _FZX_PV_RENDERER=none
  printf '\e[38;5;244mempty file\e[0m\n'
}

# fzx::preview_body <path> [line]: the rendered contents, no header; logs the choice at debug level
fzx::preview_body() {
  local path="$1" line="${2:-}" type how viewer start end rc=0
  _FZX_PV_RENDERER=""
  start="${EPOCHREALTIME//[.,]/}"
  fzx::preview_detect "$path" type how
  if [[ "$type" == missing ]]; then
    _FZX_PV_SUMMARY="missing"
    printf 'no such file: %s\n' "$path"
    return 1
  fi
  fzx::preview_viewer "$path" "$type" viewer
  if [[ -n "$viewer" && "$type" != dir ]]; then
    _FZX_PV_RENDERER="user: $viewer"
    fzx::_preview_user "$viewer" "$path" || rc=$?
  else
    "fzx::_pv_$type" "$path" "$line" || rc=$?
  fi
  end="${EPOCHREALTIME//[.,]/}"
  _FZX_PV_SUMMARY="$how:$type -> ${_FZX_PV_RENDERER:-none} ($(((end - start) / 1000))ms)"
  declare -F fzx::log > /dev/null && fzx::log debug "preview $path: $_FZX_PV_SUMMARY${rc:+ rc=$rc}"
  return "$rc"
}

# fzx::preview <item> [line]: the body for a path or a grep hit (path:line:...); FZX_PREVIEW_DEBUG=1 puts
# the detector, renderer and time on a first line (the body is buffered for it)
fzx::preview() {
  local path line out rc=0
  fzx::preview_split "${1:-}" path line
  [[ "${2:-}" =~ ^[0-9]+$ && -z "$line" ]] && line="$2"
  if [[ "${FZX_PREVIEW_DEBUG:-0}" == 1 ]]; then
    out="$(
      fzx::preview_body "$path" "$line"
      rc=$?
      printf '\n%s' "$_FZX_PV_SUMMARY"
      exit "$rc"
    )" || rc=$?
    local body="${out%$'\n'*}"
    printf '\e[38;5;244m%s\e[0m\n%s\n' "${out##*$'\n'}" "${body%$'\n'}"
    return "$rc"
  fi
  fzx::preview_body "$path" "$line"
}
