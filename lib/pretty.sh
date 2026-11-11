#!/usr/bin/env bash
# pretty: file and directory names with icons and colors from prettypath (github.com/njhoffman/prettypath),
# for the display column only; ids stay plain absolute paths, so what fzx prints does not change.
# FZX_PRETTY: auto (when prettypath 0.2.0 or later is installed), 1 or 0.

# fzx::pretty_on: prettypath is wanted, installed and 0.2.0 or later (fzx::pretty_level); an older one counts
# as absent, so the lists keep their plain displays
fzx::pretty_on() {
  case "${FZX_PRETTY:-auto}" in
    0 | off | false) return 1 ;;
  esac
  local level
  level="$(fzx::pretty_level)" && [[ "$level" == current ]]
}

# fzx::pretty_level: whether the installed prettypath is one fzx can use, from its --version
# ("prettypath X.Y.Z"): current (0.2.0 or later, with --base, --dirs and --field) or legacy (anything else:
# older, a dev build printing "prettypath dev-N", or one from before --version, which reads stdin instead,
# hence < /dev/null). Checked once per prettypath binary (keyed by its path and mtime) and remembered in
# FZX_CACHE_DIR; a legacy one is logged once, there. Prints nothing and fails without prettypath.
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
  [[ "$got" =~ ^prettypath\ ([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] &&
    ((BASH_REMATCH[1] > 0 || BASH_REMATCH[2] >= 2)) && level=current
  mkdir -p -- "${file%/*}"
  echo "$level" > "$file"
  [[ "$level" == legacy ]] && declare -F fzx::log > /dev/null &&
    fzx::log warn "prettypath ${got:-without --version} at $bin is older than 0.2.0; lists are shown without its icons"
  echo "$level"
}

# fzx::pretty [--dirs] [base]: absolute paths on stdin -> "path<TAB>display", the display without the base
# directory (as prettypath shows it, under ~). A trailing "/" marks a directory (fd prints one), which
# prettypath shows with the folder icon and drops from %path%; --dirs marks every path as one (zoxide's
# lists have no slash). Callers check fzx::pretty_on first.
fzx::pretty() {
  local args=(--format=$'%path%\t%icon% %dir%%name%')
  [[ "${1:-}" == --dirs ]] && { args+=(--dirs); shift; }
  [[ -n "${1:-}" ]] && args+=("--base=$1")
  command prettypath "${args[@]}"
}

# fzx::pretty_field N [--dirs] [base]: tab-separated rows on stdin -> the same rows, in order, with
# prettypath's display of field N (a path; a trailing "/" marks a directory) appended as a last column:
# prettypath decorates a copy of the field in place (--field), one pass with nothing to join. Callers check
# fzx::pretty_on first.
fzx::pretty_field() {
  local n="$1" args=(--field=-1 --format='%icon% %dir%%name%')
  shift
  [[ "${1:-}" == --dirs ]] && { args+=(--dirs); shift; }
  [[ -n "${1:-}" ]] && args+=("--base=$1")
  awk -F'\t' -v n="$n" '{ print $0 "\t" $n; fflush() }' | command prettypath "${args[@]}"
}
