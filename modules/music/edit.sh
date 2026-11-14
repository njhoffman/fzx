#!/usr/bin/env bash
# music edits through musicman (github.com/njhoffman/musicman): the rating and the multi value fields
# (FZX_MUSIC_EDIT_FIELDS: context, mood, picks) of the selected songs, written with `musicman edit` one file
# at a time (it asks before changing several at once). Sourced by actions.sh, after preview.sh.

# music::edit_paths <var> <files...>: the songs' paths under MPD's music directory, into the array <var>;
# false when musicman or the music directory is missing
music::edit_paths() {
  local -n _paths="$1"
  local _root _file
  shift
  command -v musicman > /dev/null || { printf 'music: musicman is not installed\n' >&2; return 1; }
  _root="$(music::music_dir)"
  [[ -n "$_root" ]] || { printf 'music: no music directory (FZX_MUSIC_DIR, or MPD'\''s music_directory)\n' >&2; return 1; }
  _paths=()
  for _file; do
    [[ -n "$_file" ]] && _paths+=("$_root/$_file")
  done
  ((${#_paths[@]})) || return 1
}

# music::forget <file...>: drop the cached musicman answers of these songs, so their previews read again
music::forget() {
  local dir file root key
  dir="$(music::cache_dir tags)" || return 0
  root="$(music::music_dir)"
  for file; do
    key="$(printf '%s' "$root/$file" | command md5sum)"
    rm -f -- "$dir/${key%% *}.json"
  done
}

# music::edit_write <assignment...> -- <path...>: musicman edit each path with the assignments (a rating
# number, or field=+a,-b); the files that failed are reported, the rest still written
music::edit_write() {
  local args=() path failed=0
  while (($#)) && [[ "$1" != -- ]]; do args+=("$1") && shift; done
  shift
  for path; do
    if ! command musicman edit "$path" "${args[@]}" > /dev/null 2>&1; then
      printf 'music: musicman edit failed: %s\n' "${path##*/}" >&2
      failed=1
    fi
  done
  return "$failed"
}

# music::ask <var> <prompt> <default>: a line read on the terminal, with readline and the default to edit
music::ask() {
  local -n _answer="$1"
  fzx::tty_read -r -e -p "$2" -i "$3" _answer < /dev/tty
}

# music::rate <files...>: ask for a rating (0 to 5 in half steps, the first song's as the default) and
# write it to every song
music::rate() {
  local paths=() current rating
  music::edit_paths paths "$@" || return 1
  current="$(music::musicman "$1" | command awk -F'\t' '$1 == "rating" { print $2 }')"
  music::ask rating $'\e[1mrating\e[0m'" for ${#paths[@]} song(s) (0-5 in half steps): " "$current" || return 0
  [[ -n "$rating" ]] || return 0
  if ! [[ "$rating" =~ ^(5(\.0)?|[0-4](\.[05])?)$ ]]; then
    printf 'music: not a rating from 0 to 5 in half steps: %s\n' "$rating" >&2
    return 1
  fi
  music::edit_write "$rating" -- "${paths[@]}"
  local rc=$?
  music::forget "$@"
  return "$rc"
}

# music::tag_rows <values json> <songs> <field:value counts...>: "field:value<TAB>display" per value in use
# (musicman values), plus values the songs have that the library does not list yet; the display marks
# values every song has (●), some have (◐) and none (○), with the number of songs in the library
music::tag_rows() {
  local json="$1" songs="$2"
  shift 2
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" f=$'\e['"${FZX_COLORS[music_field]:-38;5;111}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && d="" f="" r=""
  printf '%s\n' "$@" | command jq -rR --slurp --argjson v "$json" --argjson songs "$songs" \
    --arg d "$d" --arg f "$f" --arg r "$r" '
    (split("\n") | map(select(. != "") | split("\t") | {key: .[0], value: (.[1] | tonumber)}) | from_entries) as $have |
    [$v | to_entries[] | .key as $field | .value[] | {key: "\($field):\(.value)", field: $field, value, count}] as $rows |
    ($rows | map(.key)) as $known |
    ($rows + [$have | keys[] | select(. as $k | $known | index($k) | not) |
      {key: ., field: (split(":")[0]), value: (split(":")[1:] | join(":")), count: 0}]) |
    .[] | ($have[.key] // 0) as $n |
    (if $n == $songs then "●" elif $n > 0 then "◐" else "○" end) as $mark |
    "\(.key)\t\($mark) \($f)\(.field | . + (" " * ([10 - length, 1] | max)))\($r)\(.value) \($d)\(.count)\($r)"'
}

# music::tags <files...>: pick the songs' context, mood and picks values in fzf, those every song has
# selected at the start; enter writes the difference (selected: every song gets it; unselected and once
# on every song: removed from all; a value only some have is left alone unless selected). alt-enter also
# adds the query as a new value, typed as field:value
music::tags() {
  local paths=() fields=("${FZX_MUSIC_EDIT_FIELDS[@]}") json file line key i n out
  ((${#fields[@]})) || fields=(context mood picks)
  music::edit_paths paths "$@" || return 1
  command -v jq > /dev/null || { printf 'music: jq is not installed\n' >&2; return 1; }
  json="$(command musicman values "${fields[@]}" --format json 2> /dev/null)" || {
    printf 'music: musicman values failed (musicman 1.61 or later has it)\n' >&2
    return 1
  }
  # how many of the selected songs have each field:value (the preview's cached musicman answers)
  local -A have=()
  for file; do
    while IFS=$'\t' read -r key line; do
      [[ " ${fields[*]} " == *" $key "* ]] || continue
      IFS=',' read -ra out <<< "$line"
      for i in "${out[@]}"; do
        i="${i#"${i%%[![:space:]]*}"}" i="${i%"${i##*[![:space:]]}"}"
        [[ -n "$i" ]] && have["$key:$i"]=$((${have["$key:$i"]:-0} + 1))
      done
    done < <(music::musicman "$file")
  done
  local counts=() rows=() start="" songs=$# prompt
  for key in "${!have[@]}"; do counts+=("$key	${have[$key]}"); done
  mapfile -t rows < <(music::tag_rows "$json" "$songs" "${counts[@]}")
  ((${#rows[@]})) || { printf 'music: no %s values in the library yet\n' "${fields[*]}" >&2; }
  # the values every song has start selected (on load: at start the rows are not read yet)
  for i in "${!rows[@]}"; do
    [[ "${have[${rows[i]%%$'\t'*}]:-0}" == "$songs" ]] && start+="pos($((i + 1)))+toggle+"
  done
  printf -v prompt '%s, ' "${fields[@]}"
  prompt="${prompt%, }"
  mapfile -t out < <(printf '%s\n' "${rows[@]}" | command fzf --multi --ansi --delimiter=$'\t' --with-nth=2 \
    --no-sort --print-query --expect=alt-enter --prompt="$prompt> " \
    --header=$'enter: write the selection  alt-enter: also add the query (field:value)  tab: select\n● every song  ◐ some  ○ none' \
    --bind "load:${start}first")
  ((${#out[@]} >= 2)) || return 0
  local query="${out[0]}" pressed="${out[1]}"
  local -A chosen=()
  for line in "${out[@]:2}"; do [[ -n "$line" ]] && chosen["${line%%$'\t'*}"]=1; done
  if [[ "$pressed" == alt-enter && -n "$query" ]]; then
    key="${query%%:*}"
    if [[ "$query" != *:* || " ${fields[*]} " != *" $key "* || -z "${query#*:}" || "$query" == *,* ]]; then
      printf 'music: a new value is field:value, field one of %s, no commas: %s\n' "${fields[*]}" "$query" >&2
      return 1
    fi
    chosen["$query"]=1
  fi
  # per field: +value for the chosen ones not on every song, -value for the ones on every song not chosen
  local -A change=()
  for key in "${!chosen[@]}"; do
    [[ "${have[$key]:-0}" == "$songs" ]] || change["${key%%:*}"]+=",+${key#*:}"
  done
  for key in "${!have[@]}"; do
    [[ "${have[$key]}" == "$songs" && -z "${chosen[$key]:-}" ]] && change["${key%%:*}"]+=",-${key#*:}"
  done
  ((${#change[@]})) || return 0
  local assignments=()
  for key in "${fields[@]}"; do
    [[ -n "${change[$key]:-}" ]] && assignments+=("$key=${change[$key]#,}")
  done
  printf '\e[2m%s\e[0m\n' "${assignments[*]}"
  music::edit_write "${assignments[@]}" -- "${paths[@]}"
  n=$?
  music::forget "$@"
  return "$n"
}
