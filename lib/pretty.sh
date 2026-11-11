#!/usr/bin/env bash
# pretty: file and directory names with icons and colors from prettypath (github.com/njhoffman/prettypath),
# for the display column only; ids stay plain absolute paths, so what fzx prints does not change.
# FZX_PRETTY: auto (when prettypath is installed), 1 or 0.

# fzx::pretty_on: prettypath is wanted and available
fzx::pretty_on() {
  case "${FZX_PRETTY:-auto}" in
    0 | off | false) return 1 ;;
  esac
  command -v prettypath > /dev/null
}

# fzx::pretty_level: what the installed prettypath can do, from its --version ("prettypath X.Y.Z"):
#   current  0.2.0 or later: --base and --dirs (fzx::pretty passes them instead of fixing the display itself)
#   sound    0.1.x: every path passes through intact
#   legacy   older: strips "%" from %path% (the id fzx prints) and drops paths directly under / without a
#            word; prints "prettypath dev-N" or, before --version existed, reads stdin (hence < /dev/null)
# Checked once per prettypath binary (keyed by its path and mtime) and remembered in FZX_CACHE_DIR. Prints
# nothing and fails without prettypath.
fzx::pretty_level() {
  local bin mtime key file got level=legacy
  bin="$(command -v prettypath)" || return 1
  mtime="$(stat -L -c %Y -- "$bin" 2> /dev/null)" || mtime=0
  key="$(printf '%s:%s' "$bin" "$mtime" | md5sum)"
  file="$FZX_CACHE_DIR/prettypath/${key%% *}"
  if [[ -f "$file" ]]; then
    cat -- "$file"
    return 0
  fi
  got="$(command prettypath --version < /dev/null 2> /dev/null)"
  if [[ "$got" =~ ^prettypath\ ([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    if ((BASH_REMATCH[1] > 0 || BASH_REMATCH[2] >= 2)); then
      level=current
    elif ((BASH_REMATCH[2] >= 1)); then
      level=sound
    fi
  fi
  mkdir -p -- "${file%/*}"
  echo "$level" > "$file"
  [[ "$level" == legacy ]] &&
    fzx::log warn "prettypath mangles or drops some paths (older than 0.1.0); those are shown without icons"
  echo "$level"
}

# fzx::pretty_sound: the installed prettypath passes every path through intact (0.1.0 or later)
fzx::pretty_sound() {
  local level
  level="$(fzx::pretty_level)" && [[ "$level" != legacy ]]
}

# fzx::pretty [--dirs] [base]: absolute paths on stdin -> "path<TAB>display", the display without the base
# directory (as prettypath shows it, under ~). A trailing "/" marks a directory (fd prints one), which
# prettypath shows with the folder icon and drops from %path%; --dirs marks every path as one (zoxide's
# lists have no slash). prettypath 0.2.0 and later do both themselves (--dirs, --base); with 0.1.x fzx adds
# the slash and cuts the base from the display; with an older one (fzx::pretty_level) the paths it would
# mangle (a "%" in them, or directly under /) skip it and get a plain display.
fzx::pretty() {
  local dirs="" base shown="" cmd level args
  [[ "${1:-}" == --dirs ]] && { dirs=1; shift; }
  base="${1:-}"
  level="$(fzx::pretty_level)" || level=legacy
  if [[ "$level" == current ]]; then
    args=(--format=$'%path%\t%icon% %dir%%name%')
    [[ -n "$dirs" ]] && args+=(--dirs)
    [[ -n "$base" ]] && args+=("--base=$base")
    command prettypath "${args[@]}"
    return
  fi
  [[ -n "$base" ]] && shown="${base/#$HOME/\~}/"
  cmd="prettypath --format='%path%"$'\t'"%icon% %dir%%name%'"
  if [[ "$level" == sound ]]; then
    if [[ -n "$dirs" ]]; then sed 's:/*$:/:'; else command cat; fi |
      command prettypath --format=$'%path%\t%icon% %dir%%name%'
  else
    sed 's:/$::' | awk -v cmd="$cmd" -v home="$HOME" '
      /%/ || /^\/[^\/]*$/ { shown = $0; if (index(shown, home "/") == 1) shown = "~" substr(shown, length(home) + 1)
                            printf "%s\t  %s\n", $0, shown; fflush(); next }
      { print | cmd }
      END { close(cmd) }'
  fi |
    awk -F'\t' -v shown="$shown" 'BEGIN { OFS = "\t" }
      { if (shown != "" && (i = index($2, shown))) $2 = substr($2, 1, i - 1) substr($2, i + length(shown))
        print }'
}

# fzx::pretty_field N [--dirs] [base]: tab-separated rows on stdin -> the same rows, in order, with
# prettypath's display of field N (a path; a trailing "/" marks a directory) appended as a last column.
# prettypath 0.2.0 and later decorate a copy of the field in place (--field, one pass, nothing to join); with
# an older one field N goes through fzx::pretty and is joined back by path (the trailing "/" left out of the
# key, as prettypath leaves it out of %path%), and a path it did not return gets a plain display.
fzx::pretty_field() {
  local n="$1" level in args
  shift
  level="$(fzx::pretty_level)" || level=legacy
  if [[ "$level" == current ]]; then
    args=(--field=-1 --format='%icon% %dir%%name%')
    [[ "${1:-}" == --dirs ]] && { args+=(--dirs); shift; }
    [[ -n "${1:-}" ]] && args+=("--base=$1")
    awk -F'\t' -v n="$n" '{ print $0 "\t" $n; fflush() }' | command prettypath "${args[@]}"
    return
  fi
  in="$(cat)"
  [[ -n "$in" ]] || return 0
  awk -F'\t' -v n="$n" 'NR == FNR { shown[$1] = $2; next }
    { key = $n; sub(/\/+$/, "", key); print $0 "\t" ((key in shown) ? shown[key] : "  " key) }' \
    <(cut -f"$n" <<< "$in" | fzx::pretty "$@") - <<< "$in"
}
