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

# fzx::pretty [base]: absolute paths on stdin -> "path<TAB>display", the display without the base
# directory (as prettypath shows it, under ~). Paths must be absolute: prettypath drops relative ones.
fzx::pretty() {
  local base="${1:-}" shown=""
  [[ -n "$base" ]] && shown="${base/#$HOME/\~}/"
  sed 's:/$::' |
    command prettypath --stat_file=false --format=$'%path%\t%icon% %dir%%name%' |
    awk -F'\t' -v shown="$shown" 'BEGIN { OFS = "\t" }
      { if (shown != "" && (i = index($2, shown))) $2 = substr($2, 1, i - 1) substr($2, i + length(shown))
        print }'
}
