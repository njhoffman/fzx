#!/usr/bin/env bash
# capture preview: where the value was (on the screen, or how far above or below it) and the lines around
# it, the value highlighted
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# capture::preview [--pane %N] -- <value> <y>
capture::preview() {
  local args=() value y top bottom from to where
  while (($#)) && [[ "$1" != -- ]]; do args+=("$1"); shift; done
  shift
  value="${1:-}" y="${2:-}"
  [[ "$y" =~ ^-?[0-9]+$ ]] || return 0
  capture::args "${args[@]}" || return
  capture::geometry "$CAPTURE_PANE"
  top=$((-CAPTURE_SCROLL)) bottom=$((CAPTURE_HEIGHT - 1 - CAPTURE_SCROLL))
  if ((y < top)); then where="$((top - y)) lines above the screen"
  elif ((y > bottom)); then where="$((y - bottom)) lines below the view"
  else where="on the screen"; fi
  local D=$'\e[38;5;244m' H=$'\e[1;38;5;255;48;5;24m' R=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && D="" H="" R=""
  printf '%s%s in %s, %s%s\n\n' "$D" "${CAPTURE_PANE}" "$(command tmux display-message -p -t "$CAPTURE_PANE" '#{pane_current_command}')" "$where" "$R"
  from=$((y - 8)) to=$((y + 8))
  ((from < -CAPTURE_HISTORY)) && from=$((-CAPTURE_HISTORY))
  ((to > CAPTURE_HEIGHT - 1)) && to=$((CAPTURE_HEIGHT - 1))
  # the hit's line highlighted, the value within it marked: the line nearest y that holds the value (joined
  # wrapped lines can shift the count by a few). The origin pane from the snapshot (fzf may be on it now).
  local file
  capture::snapshot_file file
  if [[ "$CAPTURE_PANE" == "$CAPTURE_ORIGIN" && -n "$file" && -f "$file" ]]; then
    awk -F'\t' -v from="$from" -v to="$to" '$1 >= from && $1 <= to { t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t); print $1 "\t" t }' "$file" |
      sort -t $'\t' -k1,1n | cut -f2-
  else
    command tmux capture-pane -p -J -t "$CAPTURE_PANE" -S "$from" -E "$to"
  fi |
    awk -v at="$((y - from + 1))" -v v="$value" -v d="$D" -v h="$H" -v r="$R" '
      { l[NR] = $0; if (v != "" && index($0, v)) { dist = NR > at ? NR - at : at - NR; if (best == "" || dist < bd) { best = NR; bd = dist } } }
      END {
        if (best == "") best = at
        for (i = 1; i <= NR; i++) {
          if (i != best) { print d "  " l[i] r; continue }
          t = l[i]; j = index(t, v)
          if (j && v != "") t = substr(t, 1, j - 1) h v r substr(t, j + length(v))
          print "▶ " t
        }
      }'
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" capture
  capture::preview "$@"
}
