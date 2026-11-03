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

# fzx::edit_text <var>: stdin edited on the terminal in $VISUAL / $EDITOR (a shell function name falls back
# to nvim, then vi), the result into <var>. False, <var> empty, when the editor fails (vim's :cq) or the
# text is emptied: the caller cancels. The newline editors add at the end is dropped when stdin had none.
# FZX_TTY (default /dev/tty): the editor's terminal, for tests.
fzx::edit_text() {
  local _file _nl="" _editor _rc=0
  _file="$(mktemp "${TMPDIR:-/tmp}/fzx-edit.XXXXXX")" || return
  command cat > "$_file"
  [[ "$(tail -c1 -- "$_file" | wc -l)" -eq 1 ]] && _nl=1
  read -ra _editor <<< "${VISUAL:-${EDITOR:-vi}}"
  type -P "${_editor[0]}" > /dev/null || _editor=("$(type -P nvim || echo vi)")
  "${_editor[@]}" -- "$_file" <> "${FZX_TTY:-/dev/tty}" >&0 || _rc=$?
  printf -v "$1" '%s' ""
  if ((_rc == 0)); then
    # x keeps the trailing newlines command substitution would strip
    printf -v "$1" '%s' "$(command cat -- "$_file"; printf x)"
    printf -v "$1" '%s' "${!1%x}"
    [[ -n "$_nl" ]] || printf -v "$1" '%s' "${!1%$'\n'}"
  fi
  rm -f -- "$_file"
  ((_rc == 0)) && [[ -n "${!1}" ]]
}

# fzx::confirm <what> [args...]: ask on the terminal (FZX_TTY, default /dev/tty); true on y. The answers
# come through one descriptor per process, so a test's FZX_TTY file of answers ("yn") feeds them in turn.
fzx::confirm() {
  local what="$1" ans="" tty="${FZX_TTY:-/dev/tty}"
  shift
  if [[ -z "${_FZX_CONFIRM_FD:-}" ]]; then
    exec {_FZX_CONFIRM_FD}< "$tty" || return 1
  fi
  printf '\n\e[1m%s\e[0m %s\n[y/N] ' "$what" "$*" >> "$tty"
  IFS= read -rsn1 ans <&"$_FZX_CONFIRM_FD" || :
  printf '\n' >> "$tty"
  [[ "$ans" == [yY] ]]
}

# fzx::builtin <copy|copy-line|view|confirm> [args...]
fzx::builtin() {
  local name="${1:-}"
  shift
  case "$name" in
    copy-line)
      (($#)) || return 0
      # the line as the source wrote it: a display split for --freeze-left whole again
      local _k=""
      [[ -n "${FZX_SESSION_DIR:-}" ]] && fzx::_kv_get "$FZX_SESSION_DIR/meta/freeze" _k 2> /dev/null
      if [[ -n "$_k" ]]; then
        printf '%s\n' "$@" | awk -F'\t' -v OFS='\t' -v k="$_k" '{ last = $NF; NF--; if (last != "") $k = $k " " last; print }' | fzx::clip
      else
        printf '%s\n' "$@" | fzx::clip
      fi
      ;;
    copy)
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
