#!/usr/bin/env bash
# music through musicman (github.com/njhoffman/musicman, 1.86+; its docs/09-contract.md): the smart mode's
# presets (`musicman smart`), side trips (`player play`, `player back`) and the back point the header
# shows. musicman's CLI takes over a second to start, so what it answers is cached under
# $FZX_CACHE_DIR/music: the presets and their songs keyed by the mtimes of smart.yml and the library
# database, the back point's file (`player back --peek --path`) for a day. JSON through jq, which gives
# the presets' terms as words to pass back.

# music::cache_dir <sub>: the directory of cached covers or musicman answers (under FZX_CACHE_DIR, which
# core.sh sets; standalone scripts that load no core fall back to XDG_CACHE_HOME's)
music::cache_dir() {
  local dir="${FZX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fzx}/music/$1"
  mkdir -p -- "$dir" 2> /dev/null && printf '%s' "$dir"
}

# music::mm_on: musicman is wanted (FZX_MUSIC_MUSICMAN not off), installed, and jq reads its answers
music::mm_on() {
  [[ "${FZX_MUSIC_MUSICMAN:-auto}" != off ]] && command -v musicman > /dev/null && command -v jq > /dev/null
}

# music::_back_probe <file>: ask musicman where it publishes the back point and write the answer to file:
# the path, or nothing when this musicman does not know --peek --path. A timeout writes nothing (asked
# again next time)
music::_back_probe() {
  local file="$1" path rc
  path="$(command timeout 15 musicman player back --peek --path 2> /dev/null)"
  rc=$?
  ((rc == 124)) && return 1
  ((rc == 0)) && [[ "$path" == /* ]] || path=""
  printf '%s' "$path" > "$file.$$" && mv -f -- "$file.$$" "$file"
}

# music::back_path <var> [wait]: the file musicman publishes its back point to, which also says this
# musicman has side trips and play --files. Asked once and kept a day (asked again in the background when
# older). Fails without musicman, with one too old for it, and, without wait, while the first answer is
# being fetched in the background
music::back_path() {
  local -n _bp_out="$1"
  local _bp_dir _bp_f
  _bp_out=""
  music::mm_on || return 1
  _bp_dir="$(music::cache_dir musicman)" || return 1
  _bp_f="$_bp_dir/back-path"
  if [[ ! -f "$_bp_f" ]]; then
    if [[ "${2:-}" == wait ]]; then
      music::_back_probe "$_bp_f" || return 1
    else
      (music::_back_probe "$_bp_f" > /dev/null 2>&1 < /dev/null &)
      return 1
    fi
  elif [[ -n "$(command find "$_bp_f" -mmin +1440 2> /dev/null)" ]]; then
    touch -- "$_bp_f"
    (music::_back_probe "$_bp_f" > /dev/null 2>&1 < /dev/null &)
  fi
  _bp_out="$(< "$_bp_f")"
  [[ -n "$_bp_out" ]]
}

# music::back_point <var>: "artist - title" of the back point (empty artist: the title alone), from the
# published file; fails when there is none or musicman cannot say
music::back_point() {
  local -n _pt_out="$1"
  local _pt_file _pt_lines=()
  _pt_out=""
  music::back_path _pt_file && [[ -f "$_pt_file" ]] || return 1
  mapfile -t _pt_lines < "$_pt_file"
  ((${#_pt_lines[@]} >= 3)) || return 1
  _pt_out="${_pt_lines[2]}"
  [[ -n "${_pt_lines[1]}" ]] && _pt_out="${_pt_lines[1]} - $_pt_out"
  [[ -n "$_pt_out" ]] || _pt_out="(${_pt_lines[0]})"
}

# music::smart_key <var>: what the cached presets depend on: the mtimes of smart.yml and of the library
# database (from musicman's paths.json; ratings and tags change which songs match)
music::smart_key() {
  local -n _key_out="$1"
  local _yml="${XDG_CONFIG_HOME:-$HOME/.config}/musicman/smart.yml"
  local _paths="${XDG_STATE_HOME:-$HOME/.local/state}/musicman/paths.json" _db="" _f _m
  [[ -f "$_paths" ]] && _db="$(command jq -r '.db.path // empty' "$_paths" 2> /dev/null)"
  _key_out=""
  for _f in "$_yml" "$_db"; do
    _m=0
    [[ -n "$_f" && -e "$_f" ]] && _m="$(command stat -c %Y -- "$_f" 2> /dev/null)"
    _key_out+="${_key_out:+-}${_m:-0}"
  done
}

# music::smart_dir <var>: the cache directory of the presets as they are now, with list.tsv in it:
# "name<TAB>terms as text<TAB>songs<TAB>songs with a Spotify id<TAB>terms (US-separated)" per preset, in
# smart.yml's order. Built from `musicman smart --list --format json` when missing (older keys removed)
music::smart_dir() {
  local -n _sd_out="$1"
  local _sd_base _sd_key _sd_tmp
  _sd_out=""
  _sd_base="$(music::cache_dir smart)" || return 1
  music::smart_key _sd_key
  _sd_out="$_sd_base/$_sd_key"
  [[ -f "$_sd_out/list.tsv" ]] && return 0
  _sd_tmp="$_sd_base/.new.$$"
  mkdir -p -- "$_sd_tmp/show" || return 1
  if ! command musicman smart --list --format json > "$_sd_tmp/list.json" ||
    ! command jq -r '.[] | [.name, .text, (.songs | tostring), (.spotify | tostring), (.terms | join("\u001f"))]
      | map(gsub("[\t\n\r]+"; " ")) | join("\t")' "$_sd_tmp/list.json" > "$_sd_tmp/list.tsv"; then
    printf 'music: musicman smart --list failed\n' >&2
    rm -rf -- "$_sd_tmp"
    return 1
  fi
  rm -f -- "$_sd_tmp/list.json"
  command find "$_sd_base" -mindepth 1 -maxdepth 1 -type d ! -name '.new.*' -exec rm -rf -- {} + 2> /dev/null
  mv -T -- "$_sd_tmp" "$_sd_out" 2> /dev/null || rm -rf -- "$_sd_tmp"
  [[ -f "$_sd_out/list.tsv" ]]
}

# music::smart_row <name> <var>: the preset's list.tsv row
music::smart_row() {
  local -n _row_out="$2"
  local _row_dir
  _row_out=""
  music::smart_dir _row_dir || return 1
  _row_out="$(command awk -F'\t' -v n="$1" '$1 == n { print; exit }' "$_row_dir/list.tsv")"
  [[ -n "$_row_out" ]]
}

# music::smart_terms <name> <array var>: the preset's search terms, one word each
music::smart_terms() {
  local -n _st_out="$2"
  local _st_row
  _st_out=()
  music::smart_row "$1" _st_row || { printf 'music: no smart playlist %s\n' "$1" >&2; return 1; }
  IFS=$'\x1f' read -r -a _st_out <<< "$(printf '%s' "$_st_row" | command cut -f5)"
  ((${#_st_out[@]}))
}

# music::smart_rows: the smart mode's lines, "name<TAB>smart<TAB>terms<TAB>display"
music::smart_rows() {
  local dir
  music::smart_dir dir || return 1
  music::colors
  command awk -F'\t' -v d="$MC_D" -v r="$MC_R" -v ca="$MC_A" '
    { n[NR] = $1; t[NR] = $2; s[NR] = $3; sp[NR] = $4; if (length($1) > w) w = length($1) }
    END {
      for (i = 1; i <= NR; i++)
        printf "%s\tsmart\t%s\t%s%-*s%s  %5d song%s  %s%5d on Spotify  %s%s\n", n[i], t[i], ca, w, n[i], r,
          s[i], (s[i] == 1 ? " " : "s"), d, sp[i], t[i], r
    }' "$dir/list.tsv"
}

# music::_smart_show_build <dir> <name>: the preset's songs into dir/show/<name>.tsv, "artist<TAB>title<TAB>
# rating<TAB>file" (file under the music directory), in library order; .none when musicman fails
music::_smart_show_build() {
  local out="$1/show/$2.tsv"
  mkdir -p -- "$1/show"
  if command musicman smart show "$2" --format json > "$out.$$.json" 2> /dev/null &&
    command jq -r '.tracks[] | [.artist, .title, .rating, .file] | map(tostring | gsub("[\t\n\r]+"; " ")) | join("\t")' \
      "$out.$$.json" > "$out.$$" 2> /dev/null; then
    mv -f -- "$out.$$" "$out"
  else
    rm -f -- "$out.$$"
    : > "$1/show/$2.none"
  fi
  rm -f -- "$out.$$.json"
  rmdir -- "$1/show/$2.lock" 2> /dev/null
}

# music::smart_songs <name> <var> [wait seconds]: the cached song list's path, its building started in the
# background (a preview moving on does not stop it); waits up to that long for it (default 0)
music::smart_songs() {
  local -n _ss_out="$2"
  local _ss_dir _ss_i _ss_n=$((${3:-0} * 10))
  _ss_out=""
  music::smart_dir _ss_dir || return 1
  _ss_out="$_ss_dir/show/$1.tsv"
  [[ -f "$_ss_out" ]] && return 0
  [[ -f "$_ss_dir/show/$1.none" ]] && return 1
  mkdir -p -- "$_ss_dir/show"
  if mkdir -- "$_ss_dir/show/$1.lock" 2> /dev/null; then
    (music::_smart_show_build "$_ss_dir" "$1" > /dev/null 2>&1 < /dev/null &)
  fi
  for ((_ss_i = 0; _ss_i < _ss_n; _ss_i++)); do
    [[ -f "$_ss_out" ]] && return 0
    [[ -f "$_ss_dir/show/$1.none" ]] && return 1
    sleep 0.1
  done
  [[ -f "$_ss_out" ]]
}

# music::split_terms <text> <array var>: search terms typed as musicman writes them (words split on
# spaces, "..." or '...' keep one together, the quotes dropped); fails on an unclosed quote
music::split_terms() {
  local _sp_s="$1" _sp_c _sp_q="" _sp_t="" _sp_in=0 _sp_i _sp_all=()
  for ((_sp_i = 0; _sp_i < ${#_sp_s}; _sp_i++)); do
    _sp_c="${_sp_s:_sp_i:1}"
    if [[ -n "$_sp_q" ]]; then
      if [[ "$_sp_c" == "$_sp_q" ]]; then _sp_q=""; else _sp_t+="$_sp_c"; fi
    elif [[ "$_sp_c" == [\"\'] ]]; then
      _sp_q="$_sp_c" _sp_in=1
    elif [[ "$_sp_c" == [[:space:]] ]]; then
      ((_sp_in)) && _sp_all+=("$_sp_t")
      _sp_t="" _sp_in=0
    else
      _sp_t+="$_sp_c" _sp_in=1
    fi
  done
  ((_sp_in)) && _sp_all+=("$_sp_t")
  [[ -z "$_sp_q" ]] || return 1
  local -n _sp_out="$2"
  _sp_out=("${_sp_all[@]}")
}

# music::smart_play <main|side|add> <names...>: play the first preset as the main list (forgets the back
# point) or as a side trip, or add every one's songs; shuffled unless the ordered toggle is on, on MPD
# with the mpd toggle, else on the player musicman finds playing
music::smart_play() {
  local how="$1" name terms=() cmd=(musicman player)
  shift
  (($#)) || return 0
  [[ " ${FZX_TOGGLES:-} " == *" mpd "* ]] && cmd+=(mpd)
  if [[ "$how" == add ]]; then cmd+=(add); else cmd+=(play); fi
  [[ "$how" == main ]] && cmd+=(--main)
  [[ " ${FZX_TOGGLES:-} " == *" ordered "* ]] || cmd+=(--shuffle)
  [[ "$how" == add ]] || set -- "$1"
  for name; do
    music::smart_terms "$name" terms || return 1
    command "${cmd[@]}" "${terms[@]}" || return
  done
}

# music::smart_save <name> <terms text>: add or replace the preset (musicman checks the terms)
music::smart_save() {
  local terms=()
  [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]] || { printf 'music: a smart playlist name is letters, digits and _ . -: %s\n' "$1" >&2; return 1; }
  music::split_terms "$2" terms || { printf 'music: an unclosed quote in: %s\n' "$2" >&2; return 1; }
  ((${#terms[@]})) || { printf 'music: no search terms\n' >&2; return 1; }
  command musicman smart save "$1" "${terms[@]}"
}
