#!/usr/bin/env bash
# capture source: text pulled out of a tmux pane. Rows are "text<TAB>display<TAB>y": the text is what enter
# prints and paste sends, the display puts where it was in front ("vis" on the screen, "↑N" lines above it,
# "↓N" below it when copy mode has scrolled up), y is its tmux line (0 the screen's top, negative in the
# scrollback) for the preview. Order: the screen first, newest line first, then the scrollback nearest
# first; a value found more than once keeps its nearest place.
# Mode from $FZX_MODE: lines, urls, paths, words, hashes, ips. Toggle visible: the screen only.
# The pane: --pane %N (the one fzx was opened from), or the one alt-. / alt-, moved to (state/capture_pane).
# Under fzx the origin pane is read once, before fzf starts (state/capture_snapshot): fzf may draw over it.

# capture::args [--pane %N] [--]: the origin pane into CAPTURE_ORIGIN, the pane to read into CAPTURE_PANE
capture::args() {
  declare -g CAPTURE_ORIGIN="${FZX_TMUX_PANE:-${TMUX_PANE:-}}" CAPTURE_PANE=""
  while (($#)); do
    case "$1" in
      --pane)
        [[ "${2:-}" =~ ^%[0-9]+$ ]] || {
          printf 'capture: --pane needs a pane id (%%N)\n' >&2
          return 2
        }
        CAPTURE_ORIGIN="$2"
        shift 2
        ;;
      --) shift; break ;;
      *) printf 'capture: unknown argument: %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n "$CAPTURE_ORIGIN" ]] || CAPTURE_ORIGIN="$(command tmux display-message -p '#{pane_id}' 2> /dev/null)"
  [[ -n "$CAPTURE_ORIGIN" ]] || { printf 'capture: not in tmux and no --pane\n' >&2; return 2; }
  # under fzx the pane alt-. / alt-, chose, while it still exists
  [[ -n "${FZX_SESSION_DIR:-}" ]] && declare -F fzx::require > /dev/null && fzx::require session
  if declare -F fzx::state_get > /dev/null && [[ -n "${FZX_SESSION_DIR:-}" ]] &&
    fzx::state_get capture_pane CAPTURE_PANE 2> /dev/null && [[ -n "$CAPTURE_PANE" ]] &&
    command tmux display-message -p -t "$CAPTURE_PANE" '' > /dev/null 2>&1; then
    :
  else
    CAPTURE_PANE="$CAPTURE_ORIGIN"
  fi
}

# capture::geometry <pane>: "height scroll history" into CAPTURE_HEIGHT, CAPTURE_SCROLL (copy mode's lines
# scrolled up, 0 otherwise) and CAPTURE_HISTORY (lines in the scrollback)
capture::geometry() {
  local h s y
  # ":"-separated: scroll_position is empty outside copy mode, which a space-split read would swallow
  IFS=: read -r h s y < <(command tmux display-message -p -t "$1" '#{pane_height}:#{scroll_position}:#{history_size}')
  [[ "$h" =~ ^[0-9]+$ ]] || h=24
  [[ "$s" =~ ^[0-9]+$ ]] || s=0
  [[ "$y" =~ ^[0-9]+$ ]] || y=0
  declare -g CAPTURE_HEIGHT="$h" CAPTURE_SCROLL="$s" CAPTURE_HISTORY="$y"
}

# capture::lines <pane>: "y<TAB>where<TAB>text" per line, in the order rows are listed: the screen (the
# copy-mode view when scrolled) newest first, the scrollback above it nearest first, then what is below
# the view. Wrapped lines are joined (-J), so a long line counts once, at its last row.
capture::lines() {
  local pane="$1" top bottom above="" limit="${FZX_CAPTURE_LINES:-}"
  capture::geometry "$pane"
  top=$((-CAPTURE_SCROLL)) bottom=$((CAPTURE_HEIGHT - 1 - CAPTURE_SCROLL))
  # the screen: y from its last line up
  command tmux capture-pane -p -J -t "$pane" -S "$top" -E "$bottom" |
    awk -v y="$bottom" '{ l[NR] = $0 } END { for (i = NR; i >= 1; i--) printf "%d\tvis\t%s\n", y - (NR - i), l[i] }'
  [[ " ${FZX_TOGGLES:-} " == *" visible "* ]] && return 0
  # the scrollback above the screen, nearest first; FZX_CAPTURE_LINES bounds how far up
  if ((CAPTURE_HISTORY + top > 0)); then
    above="-"
    [[ "$limit" =~ ^[1-9][0-9]*$ ]] && above=$((top - limit))
    command tmux capture-pane -p -J -t "$pane" -S "$above" -E "$((top - 1))" |
      awk -v y="$((top - 1))" '{ l[NR] = $0 } END { for (i = NR; i >= 1; i--) { d = NR - i; printf "%d\t%s\t%s\n", y - d, "↑" (d + 1), l[i] } }'
  fi
  # below the copy-mode view: nearest first
  if ((CAPTURE_SCROLL > 0)); then
    command tmux capture-pane -p -J -t "$pane" -S "$((bottom + 1))" -E "$((CAPTURE_HEIGHT - 1))" |
      awk -v y="$((bottom + 1))" '{ printf "%d\t%s\t%s\n", y + NR - 1, "↓" NR, $0 }'
  fi
}

# capture::snapshot_file <var>: the session's snapshot of the origin pane (empty outside a session)
capture::snapshot_file() {
  printf -v "$1" '%s' "${FZX_SESSION_DIR:+$FZX_SESSION_DIR/state/capture_snapshot}"
}

# capture::snapshot: under fzx, capture::lines of the origin pane before fzf starts (capture::opts), once
# per session: run inline, fzf draws over that very pane, and reading it afterwards would capture fzf
capture::snapshot() {
  local file
  capture::snapshot_file file
  [[ -n "$file" && ! -f "$file" ]] || return 0
  mkdir -p -- "${file%/*}"
  (FZX_TOGGLES="" capture::lines "$CAPTURE_ORIGIN") > "$file.$$" && mv -f -- "$file.$$" "$file"
}

# capture::read <pane>: capture::lines, from the snapshot for the origin pane when there is one; the
# visible toggle keeps the screen's lines
capture::read() {
  local file
  capture::snapshot_file file
  if [[ "$1" == "$CAPTURE_ORIGIN" && -n "$file" && -f "$file" ]]; then
    if [[ " ${FZX_TOGGLES:-} " == *" visible "* ]]; then awk -F'\t' '$2 == "vis"' "$file"; else command cat -- "$file"; fi
  else
    capture::lines "$1"
  fi
}

# capture::extract <mode>: "y<TAB>where<TAB>text" lines -> "value<TAB>where<TAB>y" per value, the first
# (nearest) place of each. Plain text only: nothing is run or pasted.
capture::extract() {
  awk -F'\t' -v kind="$1" '
    function emit(s) { if (!seen[s]++) print s "\t" where "\t" y }
    {
      y = $1; where = $2; t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t)
      if (kind == "lines") { gsub(/\t/, "    ", t); if (t ~ /[^ ]/) emit(t); next }
      if (kind == "urls") {
        while (match(t, /(https?|ftp|file):\/\/[^[:space:]<>"\047]+/)) {
          s = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
          sub(/[.,;!?)\]}]+$/, "", s); emit(s)
        }
        next
      }
      if (kind == "paths") {
        n = split(t, w, /[ \t]+/)
        for (i = 1; i <= n; i++) {
          s = w[i]
          if (s ~ /:\/\//) continue
          sub(/^[\047"(<\[]+/, "", s); sub(/[\047")>\],;]+$/, "", s)
          if ((s ~ /\// || s ~ /^[[:alnum:]_-]+\.[[:alnum:]_.-]+(:[0-9]+)*$/) && s ~ /^[~./[:alnum:]_-]/) emit(s)
        }
        next
      }
      pattern = kind == "words" ? "[[:alnum:]_]+([.-][[:alnum:]_]+)*" : kind == "hashes" ? "[[:xdigit:]]+" : "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"
      while (match(t, pattern)) {
        s = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
        if (kind == "hashes" && (length(s) < 7 || length(s) > 64 || s !~ /[a-fA-F]/)) continue
        if (kind == "ips") {
          split(s, parts, "."); ok = 1
          for (i = 1; i <= 4; i++) if (parts[i] > 255) ok = 0
          if (!ok) continue
        }
        emit(s)
      }
    }'
}

# capture::source [--pane %N] [--]
capture::source() {
  local mode="${FZX_MODE:-lines}" vis off rst=$'\e[0m'
  case "$mode" in lines | urls | paths | words | hashes | ips) ;; *) printf 'capture: unknown mode: %s\n' "$mode" >&2; return 2 ;; esac
  capture::args "$@" || return
  vis=$'\e['"${FZX_COLORS[capture_visible]:-38;5;81}m" off=$'\e['"${FZX_COLORS[capture_offscreen]:-38;5;244}m"
  [[ -n "${NO_COLOR+x}" ]] && vis="" off="" rst=""
  capture::read "$CAPTURE_PANE" | capture::extract "$mode" |
    awk -F'\t' -v vis="$vis" -v off="$off" -v rst="$rst" '
      # padded by hand: the arrow is one cell but several bytes, which some awks and locales count
      { w = $2; n = w; gsub(/↑|↓/, "x", n); pad = 6 - length(n); if (pad < 0) pad = 0
        printf "%s\t%s%" (pad ? pad : "") "s%s%s  %s\t%s\n", $1, ($2 == "vis" ? vis : off), "", w, rst, $1, $3 }'
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" capture
  capture::source "$@"
}
