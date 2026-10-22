#!/usr/bin/env bash
# menu: module manifests, menu lines and cached per-directory entry summaries.
#
# A module's manifest.sh defines <module>::manifest, which declares entries with
#   fzx::entry <module[:mode]> <description> [module args...]
# and optionally
#   <module>::applicable <target> [args...]   fast exit-code check, run on every menu open
#   <module>::summary <target> [args...]      one short line about the entry here (may be slow);
#                                             cached per directory for FZX_SUMMARY_TTL seconds.
#                                             No output means no summary; a non-zero exit is logged

# fzx::entry <target> <description> [args...]: called from <module>::manifest
fzx::entry() {
  local _args
  FZX_ENTRY_TARGETS+=("$1")
  FZX_ENTRY_DESCS+=("$2")
  shift 2
  _args=""
  (($#)) && printf -v _args '%q ' "$@"
  FZX_ENTRY_ARGS+=("${_args% }")
}

# modules with a manifest, first on FZX_MODULE_PATH wins, as "name<TAB>dir" lines; the menu itself is excluded
fzx::menu_modules() {
  local dir mod name
  local -A seen=()
  local IFS=:
  for dir in $FZX_MODULE_PATH; do
    for mod in "$dir"/*/; do
      mod="${mod%/}"
      name="${mod##*/}"
      [[ "$name" == menu || -n "${seen[$name]:-}" || ! -f "$mod/manifest.sh" ]] && continue
      [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || continue
      seen[$name]=1
      printf '%s\t%s\n' "$name" "$mod"
    done
  done | sort
}

# fzx::menu_entries <module> <dir>: source the manifest and fill FZX_ENTRY_TARGETS/DESCS/ARGS
fzx::menu_entries() {
  FZX_ENTRY_TARGETS=() FZX_ENTRY_DESCS=() FZX_ENTRY_ARGS=()
  # shellcheck source=/dev/null
  source "$2/manifest.sh" || return 1
  declare -F "$1::manifest" > /dev/null || return 1
  "$1::manifest"
}

# fzx::menu_entry_args <i>: entry i's args into FZX_ARGS (they were stored %q-quoted, so eval is safe)
fzx::menu_entry_args() {
  eval "FZX_ARGS=(${FZX_ENTRY_ARGS[$1]})"
}

# fzx::summary_path <var> <id>: summary cache file for an entry id ("module#n") in the current directory
fzx::summary_path() {
  local _dir
  _dir="$(printf '%s' "$PWD" | md5sum)"
  printf -v "$1" '%s/summary/%s/%s' "$FZX_CACHE_DIR" "${_dir%% *}" "$2"
}

# summary file is present and younger than FZX_SUMMARY_TTL
fzx::_summary_fresh() {
  local mtime
  [[ -f "$1" ]] || return 1
  mtime="$(stat -c %Y -- "$1")" || return 1
  ((EPOCHSECONDS - mtime < ${FZX_SUMMARY_TTL:-300}))
}

# print the menu: "id<TAB>display" per applicable entry, display padded into columns.
# Each module runs in a subshell, so a broken manifest only drops that module.
fzx::menu_lines() {
  local name dir
  while IFS=$'\t' read -r name dir; do
    (
      fzx::menu_entries "$name" "$dir" 2>> "$FZX_LOG_FILE" || {
        fzx::log warn "menu: manifest of $name failed"
        exit 0
      }
      local i label summary file
      for i in "${!FZX_ENTRY_TARGETS[@]}"; do
        fzx::menu_entry_args "$i"
        if declare -F "$name::applicable" > /dev/null &&
          ! "$name::applicable" "${FZX_ENTRY_TARGETS[i]}" "${FZX_ARGS[@]}" 2>> "$FZX_LOG_FILE"; then
          continue
        fi
        label="${FZX_ENTRY_TARGETS[i]}${FZX_ENTRY_ARGS[i]:+ ${FZX_ENTRY_ARGS[i]}}"
        summary=""
        fzx::summary_path file "$name#$i"
        [[ -f "$file" ]] && summary="$(< "$file")"
        printf '%s\t\e[%sm%-24s\e[0m %-42s \e[%sm%s\e[0m\n' \
          "$name#$i" "${FZX_COLORS[menu_target]:-0}" "$label" "${FZX_ENTRY_DESCS[i]}" \
          "${FZX_COLORS[menu_summary]:-0}" "$summary"
      done
    )
  done < <(fzx::menu_modules)
}

# compute stale summaries of applicable entries, all in parallel, each limited to FZX_SUMMARY_TIMEOUT
# seconds. Returns 0 when at least one summary was written.
fzx::menu_refresh() {
  local name dir results="$FZX_SESSION_DIR/summaries.$BASHPID"
  : > "$results"
  while IFS=$'\t' read -r name dir; do
    (
      fzx::menu_entries "$name" "$dir" 2>> "$FZX_LOG_FILE" || exit 0
      declare -F "$name::summary" > /dev/null || exit 0
      local i file
      for i in "${!FZX_ENTRY_TARGETS[@]}"; do
        fzx::summary_path file "$name#$i"
        fzx::_summary_fresh "$file" && continue
        fzx::menu_entry_args "$i"
        if declare -F "$name::applicable" > /dev/null &&
          ! "$name::applicable" "${FZX_ENTRY_TARGETS[i]}" "${FZX_ARGS[@]}" 2>> "$FZX_LOG_FILE"; then
          continue
        fi
        fzx::_summary_run "$name" "$i" "$file" "$results" &
      done
      wait
    ) &
  done < <(fzx::menu_modules)
  # every module at once: slow summaries of different modules overlap instead of adding up
  wait
  local n
  n="$(wc -l < "$results")"
  rm -f -- "$results"
  ((${n// /} > 0))
}

# fzx::_summary_run <module> <i> <file> <results>: one summary with a timeout; on failure or timeout an
# empty summary is cached, so a slow or broken summary is not retried on every menu open
fzx::_summary_run() {
  local name="$1" i="$2" file="$3" results="$4" out rc tmp
  tmp="$file.$BASHPID"
  mkdir -p -- "${file%/*}"
  "$name::summary" "${FZX_ENTRY_TARGETS[i]}" "${FZX_ARGS[@]}" > "$tmp" 2>> "$FZX_LOG_FILE" &
  local pid=$!
  # the watcher must not hold the callback's stdout open (fzf waits for every writer to close it), and
  # must not leave its sleep running when it is cancelled
  (
    exec > /dev/null 2>&1
    sleep "${FZX_SUMMARY_TIMEOUT:-3}" &
    sp=$!
    trap 'kill "$sp"; exit 0' TERM
    wait "$sp"
    kill "$pid"
  ) &
  local watcher=$!
  wait "$pid"
  rc=$?
  kill "$watcher" 2> /dev/null
  wait "$watcher" 2> /dev/null
  out=""
  if ((rc == 0)); then
    IFS= read -r out < "$tmp" || :
  else
    fzx::log warn "menu: summary of $name#$i failed or timed out rc=$rc"
  fi
  rm -f -- "$tmp"
  out="${out//[$'\t\r']/ }"
  fzx::_kv_set "$file" "$out"
  printf '%s\n' "$name#$i" >> "$results"
}
