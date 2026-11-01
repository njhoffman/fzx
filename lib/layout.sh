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

# fzx::breakpoint_pick <cols> <var> <entry...>: of "MINCOLS:SPEC" entries, the one with the largest MINCOLS
# that is <= cols (FZX_PREVIEW_LAYOUTS, FZX_POPUP_LAYOUTS); entries not starting with a number are skipped;
# fails when none fits
fzx::breakpoint_pick() {
  local _cols="$1" _var="$2" _e _best="" _min=-1
  shift 2
  for _e in "$@"; do
    [[ "$_e" =~ ^[0-9]+: ]] || continue
    ((${_e%%:*} <= _cols && ${_e%%:*} > _min)) || continue
    _min="${_e%%:*}" _best="$_e"
  done
  [[ -n "$_best" ]] || return 1
  printf -v "$_var" '%s' "$_best"
}

# fzx::layout_pick <cols> <var>: the session's preview layout entry for that width; fails when none is
fzx::layout_pick() {
  local _entries=()
  fzx::layout_entries _entries
  fzx::breakpoint_pick "$1" "$2" "${_entries[@]}"
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
