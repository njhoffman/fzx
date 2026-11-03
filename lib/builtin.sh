#!/usr/bin/env bash
# builtin: actions every module gets (config/components.tsv), run as `fzx builtin <name> [args...]`.
# They need no session, so they work standalone too.

# fzx::clip: stdin to the clipboard (Wayland, X11, macOS, then tmux's paste buffer)
fzx::clip() {
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy > /dev/null; then
    wl-copy
  elif [[ -n "${DISPLAY:-}" ]] && command -v xclip > /dev/null; then
    xclip -selection clipboard
  elif [[ -n "${DISPLAY:-}" ]] && command -v xsel > /dev/null; then
    xsel --clipboard --input
  elif command -v pbcopy > /dev/null; then
    pbcopy
  elif [[ -n "${TMUX:-}" ]]; then
    tmux load-buffer -
  else
    printf 'fzx: no clipboard tool found (wl-copy, xclip, xsel, pbcopy or tmux)\n' >&2
    return 1
  fi
}

# fzx::open_url <url...>: each in the default browser (xdg-open, else macOS open); false if one failed
fzx::open_url() {
  local opener u rc=0
  if command -v xdg-open > /dev/null; then
    opener=xdg-open
  elif command -v open > /dev/null; then
    opener=open
  else
    printf 'fzx: no URL opener found (xdg-open or open)\n' >&2
    return 1
  fi
  for u in "$@"; do
    command "$opener" "$u" > /dev/null 2>&1 || rc=$?
  done
  return "$rc"
}

# fzx::confirm <what> [args...]: ask on the terminal; true on y
fzx::confirm() {
  local what="$1" ans=""
  shift
  printf '\n\e[1m%s\e[0m %s\n[y/N] ' "$what" "$*" > /dev/tty
  IFS= read -rsn1 ans < /dev/tty || :
  printf '\n' > /dev/tty
  [[ "$ans" == [yY] ]]
}

# fzx::builtin <copy|copy-line|view|confirm> [args...]
fzx::builtin() {
  local name="${1:-}"
  shift
  case "$name" in
    copy | copy-line)
      (($#)) || return 0
      printf '%s\n' "$@" | fzx::clip
      ;;
    view)
      # the module's preview of the selection, in a pager (under fzx through the preview callback)
      if [[ -n "${FZX_SESSION:-}" ]]; then
        "$FZX_BIN" _cb preview "$@"
      elif [[ -n "${FZX_MODULE_DIR:-}" && -x "$FZX_MODULE_DIR/preview.sh" ]]; then
        "$FZX_MODULE_DIR/preview.sh" "$@"
      else
        printf '%s\n' "$@"
      fi | ${PAGER:-less -R}
      ;;
    confirm) fzx::confirm "$@" ;;
    *)
      printf 'fzx: unknown builtin action: %s\n' "$name" >&2
      return 2
      ;;
  esac
}
