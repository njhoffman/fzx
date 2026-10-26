#!/usr/bin/env bash
# layout: the preview window picked from the terminal width (FZX_PREVIEW_LAYOUTS), applied on fzf's start
# and resize events through `fzx _cb layout`. Loaded by callbacks: needs only core, log and session.

# fzx::layout_entries <var>: FZX_PREVIEW_LAYOUTS as kept in the session meta (opts_build writes it), an
# array of "MINCOLS:SPEC"
fzx::layout_entries() {
  local _raw=""
  fzx::meta_get preview_layouts _raw || :
  IFS=$'\t' read -ra "$1" <<< "$_raw"
}

# fzx::layout_pick <cols> <var>: the entry with the largest MINCOLS that is <= cols; fails when none is
fzx::layout_pick() {
  local _e _best="" _min=-1 _entries=()
  fzx::layout_entries _entries
  for _e in "${_entries[@]}"; do
    ((${_e%%:*} <= $1 && ${_e%%:*} > _min)) || continue
    _min="${_e%%:*}" _best="$_e"
  done
  [[ -n "$_best" ]] || return 1
  printf -v "$2" '%s' "$_best"
}

# fzx::layout <start|resize>: prints change-preview-window(...) for the entry the width falls in.
# A resize within the same entry prints nothing, so a manual toggle stays. A preview the user hid (hidden
# now while the last entry applied shows it) stays hidden when the entry changes: the new spec is applied
# with ",hidden", so toggling it back shows the new layout. One the user showed while the entry hides it
# stays shown. Across become() the hidden state rides along in state/preview_hidden (fzx::layout_save).
fzx::layout() {
  local event="${1:-resize}" entry prev="" spec prev_spec user_hidden=0 flag=""
  fzx::layout_pick "${FZF_COLUMNS:-0}" entry || return 0
  fzx::state_get layout prev || :
  spec="${entry#*:}"
  prev_spec="${prev#*:}"
  if [[ "$event" == start ]]; then
    fzx::state_get preview_hidden flag || :
    [[ "$flag" == 1 ]] && user_hidden=1
  else
    [[ "$entry" == "$prev" ]] && return 0
    [[ -z "${FZF_PREVIEW_COLUMNS:-}" && -n "$prev" && "$prev_spec" != hidden ]] && user_hidden=1
  fi
  fzx::state_set layout "$entry"
  local note=""
  ((user_hidden)) && note=" (kept hidden)"
  fzx::log info "layout $event ${FZF_COLUMNS:-?} cols: ${prev:-none} -> $entry$note"
  if [[ "$spec" == hidden ]]; then
    # shown by hand while the previous entry hid it: leave it
    [[ "$event" == resize && -n "${FZF_PREVIEW_COLUMNS:-}" && "$prev_spec" == hidden ]] && return 0
    printf 'change-preview-window(hidden)'
  elif ((user_hidden)); then
    printf 'change-preview-window(%s)' "${spec:+$spec,}hidden"
  elif [[ -n "$spec" || "$event" == resize ]]; then
    # an empty spec is the module's own --preview-window, which a new fzf already has
    printf 'change-preview-window(%s)' "$spec"
  fi
}

# fzx::layout_save: before become(), remember whether the user hid a preview the current entry shows
fzx::layout_save() {
  local prev=""
  fzx::state_get layout prev || return 0
  if [[ -z "${FZF_PREVIEW_COLUMNS:-}" && "${prev#*:}" != hidden ]]; then
    fzx::state_set preview_hidden 1
  else
    rm -f -- "$FZX_SESSION_DIR/state/preview_hidden"
  fi
}
