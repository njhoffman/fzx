#!/usr/bin/env bash
# menu: module manifests, menu lines and cached per-directory entry summaries.
#
# A module's manifest.sh defines <module>::manifest, which declares entries with
#   fzx::entry <module[:mode]> <description> [module args...]
# and optionally
#   <module>::applicable <target> [args...]   fast exit-code check, run on every menu open (all modules
#                                             at once; a module over FZX_APPLICABLE_TIMEOUT is left out)
#   <module>::summary <target> [args...]      one short line about the entry here (may be slow);
#                                             cached per directory for FZX_SUMMARY_TTL seconds.
#                                             No output means no summary; a non-zero exit is logged
#   <module>::summary_key                     optional, fast: more to key that cache on (the state the
#                                             summaries depend on beyond the directory), asked once per
#                                             module and listing

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

# fzx::menu_entries <module> <dir>: load the module's config (its applicable and summary hooks read it, the
# menu shows its icons), source the manifest and fill FZX_ENTRY_TARGETS/DESCS/ARGS. Callers run it in a
# subshell per module, so one module's settings never reach the next.
fzx::menu_entries() {
  FZX_ENTRY_TARGETS=() FZX_ENTRY_DESCS=() FZX_ENTRY_ARGS=()
  fzx::require config
  FZX_ICON=""
  fzx::config_load "$2" "$1" 2>> "${FZX_LOG_FILE:-/dev/null}" || return 1
  # shellcheck source=/dev/null
  source "$2/manifest.sh" || return 1
  declare -F "$1::manifest" > /dev/null || return 1
  "$1::manifest"
}

# fzx::menu_entry_args <i>: entry i's args into FZX_ARGS (they were stored %q-quoted, so eval is safe)
fzx::menu_entry_args() {
  eval "FZX_ARGS=(${FZX_ENTRY_ARGS[$1]})"
}

# fzx::summary_path <var> <module> <n>: summary cache file for the module's entry n (FZX_ENTRY_* loaded) in
# the current directory. Keyed by what the entry opens (target and args), not its position, so a manifest
# that gains, drops or reorders entries never shows one entry's summary on another; plus what the module's
# <module>::summary_key prints, when it has one (git: HEAD and the index; capture: the pane), so a change
# it can see makes a new entry at once instead of after FZX_SUMMARY_TTL. Old entries go with `fzx gc`
# (FZX_CACHE_MAX_AGE_DAYS). The directory's hash and each module's summary_key are kept for the rest of the
# process (a listing), in _FZX_SUMMARY_KEYS: a module's entries share them.
declare -gA _FZX_SUMMARY_KEYS=()
fzx::summary_path() {
  local _key _dir="${_FZX_SUMMARY_KEYS[/$PWD]:-}" _extra=""
  if [[ -z "$_dir" ]]; then
    _dir="$(printf '%s' "$PWD" | md5sum)"
    _dir="${_dir%% *}"
    _FZX_SUMMARY_KEYS[/$PWD]="$_dir"
  fi
  if declare -F "$2::summary_key" > /dev/null; then
    if [[ -z "${_FZX_SUMMARY_KEYS[$2]+x}" ]]; then
      _FZX_SUMMARY_KEYS[$2]="$("$2::summary_key" 2>> "${FZX_LOG_FILE:-/dev/null}")"
    fi
    _extra="${_FZX_SUMMARY_KEYS[$2]}"
  fi
  _key="$(printf '%s\n%s\n%s' "${FZX_ENTRY_TARGETS[$3]}" "${FZX_ENTRY_ARGS[$3]:-}" "$_extra" | md5sum)"
  printf -v "$1" '%s/summary/%s/%s@%s' "$FZX_CACHE_DIR" "$_dir" "$2" "${_key:0:12}"
}

# summary file is present and younger than FZX_SUMMARY_TTL
fzx::_summary_fresh() {
  local mtime
  [[ -f "$1" ]] || return 1
  mtime="$(stat -c %Y -- "$1")" || return 1
  ((EPOCHSECONDS - mtime < ${FZX_SUMMARY_TTL:-300}))
}

# print the menu: "id<TAB>display" per applicable entry, display padded into columns.
# Every module runs at once, each in a subshell writing its own file (so a broken manifest only drops that
# module), and the files are printed in module order. A module whose manifest and applicable checks take
# longer than FZX_APPLICABLE_TIMEOUT seconds is left out of this listing and logged.
fzx::menu_lines() {
  local name dir n=0 tmp pids=() names=() watcher
  tmp="$(mktemp -d "${FZX_SESSION_DIR:-${TMPDIR:-/tmp}}/menu.XXXXXX")" || return
  while IFS=$'\t' read -r name dir; do
    names+=("$name")
    # its output goes to its file only: a check left running when it is cut off must not hold the
    # source's stdout, which fzf reads until every writer closes it
    fzx::_menu_module "$name" "$dir" "$tmp/$n" < /dev/null > /dev/null 2>> "$FZX_LOG_FILE" &
    pids+=($!)
    n=$((n + 1))
  done < <(fzx::menu_modules)
  (
    exec > /dev/null 2>&1
    sleep "${FZX_APPLICABLE_TIMEOUT:-2}" &
    sp=$!
    trap 'kill "$sp"; exit 0' TERM
    wait "$sp"
    kill "${pids[@]}"
  ) &
  watcher=$!
  wait "${pids[@]}" 2> /dev/null
  kill "$watcher" 2> /dev/null
  wait "$watcher" 2> /dev/null
  local i
  for i in "${!names[@]}"; do
    if [[ -f "$tmp/$i" ]]; then
      cat -- "$tmp/$i"
    else
      fzx::log warn "menu: ${names[i]} took over ${FZX_APPLICABLE_TIMEOUT:-2}s, left out"
    fi
  done
  rm -rf -- "$tmp"
}

# fzx::_menu_module <module> <dir> <file>: one module's menu lines into <file>, which appears only once
# they are complete; its time is logged at the debug level
fzx::_menu_module() {
  local name="$1" dir="$2" out="$3" start="$EPOCHREALTIME"
  (
    fzx::menu_entries "$name" "$dir" 2>> "$FZX_LOG_FILE" || {
      fzx::log warn "menu: manifest of $name failed"
      exit 0
    }
    local i label summary file icon mode color
    for i in "${!FZX_ENTRY_TARGETS[@]}"; do
      fzx::menu_entry_args "$i"
      if declare -F "$name::applicable" > /dev/null &&
        ! "$name::applicable" "${FZX_ENTRY_TARGETS[i]}" "${FZX_ARGS[@]}" 2>> "$FZX_LOG_FILE"; then
        continue
      fi
      label="${FZX_ENTRY_TARGETS[i]}${FZX_ENTRY_ARGS[i]:+ ${FZX_ENTRY_ARGS[i]}}"
      summary=""
      if declare -F "$name::summary" > /dev/null; then
        fzx::summary_path file "$name" "$i"
        [[ -f "$file" ]] && summary="$(< "$file")"
      fi
      # an icon (a Nerd Font glyph) in front, in the nerd icon style only: the mode's (FZX_ICON_MODES),
      # else the module's prompt icon, in FZX_COLORS[<module>_icon_<mode>] or [<module>_icon]
      icon=""
      if [[ "${FZX_ICONS:-nerd}" == nerd ]]; then
        mode=""
        [[ "${FZX_ENTRY_TARGETS[i]}" == *:* ]] && mode="${FZX_ENTRY_TARGETS[i]#*:}"
        icon="${FZX_ICON_MODES[$mode]:-${FZX_ICON:- }}"
        color="${FZX_COLORS[${name}_icon_$mode]:-${FZX_COLORS[${name}_icon]:-${FZX_COLORS[menu_target]:-0}}}"
        icon=$'\e['"${color}m$icon"$'\e[0m '
      fi
      printf '%s\t%s\e[%sm%-24s\e[0m %-42s \e[%sm%s\e[0m\n' \
        "$name#$i" "$icon" "${FZX_COLORS[menu_target]:-0}" "$label" "${FZX_ENTRY_DESCS[i]}" \
        "${FZX_COLORS[menu_summary]:-0}" "$summary"
    done
  ) > "$out.part"
  mv -- "$out.part" "$out"
  local end="$EPOCHREALTIME"
  fzx::log debug "menu: $name listed in $(((${end/./} - ${start/./}) / 1000))ms"
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
        fzx::summary_path file "$name" "$i"
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
