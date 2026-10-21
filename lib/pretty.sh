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

# fzx::pretty_sound: the installed prettypath passes every path through intact. Older versions strip "%"
# from %path% (the id fzx prints) and drop paths directly under / without a word. Probed once per
# prettypath binary (keyed by its path and mtime) and remembered in FZX_CACHE_DIR.
fzx::pretty_sound() {
  local bin mtime key file probe=$'/fzx-probe%x/a b\n/fzx-probe' want=$'/fzx-probe%x/a b\n/fzx-probe' got
  bin="$(command -v prettypath)" || return 1
  mtime="$(stat -L -c %Y -- "$bin" 2> /dev/null)" || mtime=0
  key="$(printf '%s:%s' "$bin" "$mtime" | md5sum)"
  file="$FZX_CACHE_DIR/prettypath/${key%% *}"
  if [[ -f "$file" ]]; then
    [[ "$(< "$file")" == sound ]]
    return
  fi
  got="$(printf '%s\n' "$probe" | command prettypath --stat_file=false --format=%path% 2> /dev/null)"
  mkdir -p -- "${file%/*}"
  if [[ "$got" == "$want" ]]; then
    echo sound > "$file"
    return 0
  fi
  echo legacy > "$file"
  fzx::log warn "prettypath mangles or drops some paths (old version); those are shown without icons"
  return 1
}

# fzx::pretty [base]: absolute paths on stdin -> "path<TAB>display", the display without the base
# directory (as prettypath shows it, under ~). With an older prettypath (fzx::pretty_sound), the paths it
# would mangle (a "%" in them, or directly under /) skip it and get a plain display.
fzx::pretty() {
  local base="${1:-}" shown="" cmd
  [[ -n "$base" ]] && shown="${base/#$HOME/\~}/"
  cmd="prettypath --stat_file=false --format='%path%"$'\t'"%icon% %dir%%name%'"
  if fzx::pretty_sound; then
    sed 's:/$::' | command prettypath --stat_file=false --format=$'%path%\t%icon% %dir%%name%'
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
