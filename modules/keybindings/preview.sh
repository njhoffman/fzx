#!/usr/bin/env bash
# keybindings preview. zsh: the widget, what it is (zle's description, or the user function and its
# file), every key bound to it and what the same key does in the other keymaps. tmux: the tmux module's
# preview. fzf: the action in full and the default it replaces.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

keybindings::preview_zsh() {
  local id="$1" widget="$2" cols="${FZF_PREVIEW_COLUMNS:-80}" dump rows raw="" fn file desc
  local B=$'\e[1m' D=$'\e[38;5;244m' R=$'\e[0m'
  [[ "$id" =~ ^bindkey\ -M\ [^\ ]+\ (\"([^\"\\]|\\.)*\") ]] && raw="${BASH_REMATCH[1]}"
  dump="$(keybindings::zsh_dump 2> /dev/null)" || return 0
  printf '%s%s%s\n' "$B" "$widget" "$R"
  IFS=$'\t' read -r _ _ fn file < <(awk -F'\t' -v w="$widget" '$1 == "user" && $2 == w' <<< "$dump")
  if [[ -n "$fn" ]]; then
    printf '%suser widget%s  %s%s\n' "$D" "$R" "$fn" "${file:+  ${D}in${R} ${file/#"$HOME"/\~}}"
  elif [[ "$widget" == \"* ]]; then
    printf '%stypes%s %s\n' "$D" "$R" "$widget"
  else
    desc="$(keybindings::zle_docs | awk -F'\t' -v w="$widget" '$1 == w { print $3; exit }')"
    [[ -n "$desc" ]] && printf '\n%s\n' "$desc" | fold -s -w "$cols"
  fi
  rows="$(keybindings::zsh_rows <<< "$dump")"
  printf '\n%sbound to%s\n' "$B" "$R"
  # the keymap and key columns of the display
  awk -F'\t' -v w="$widget" '$3 == w { d = $2; gsub(/\033\[[0-9;]*m/, "", d); print "  " substr(d, 1, 27) }' <<< "$rows"
  if [[ -n "$raw" ]]; then
    printf '\n%sthe same key in each keymap%s\n' "$B" "$R"
    awk -F'\t' -v k="$raw" '{ s = $1; sub(/^bindkey -M [^ ]+ /, "", s) } index(s, k " ") == 1 { print "  " $2 }' <<< "$rows"
  fi
}

keybindings::preview_fzf() {
  local key="$1" from="$2" action def
  local B=$'\e[1m' D=$'\e[38;5;244m' R=$'\e[0m'
  fzx::require keys
  def="$(awk -F'\t' -v k="$key" '$1 == k { print $2; exit }' <<< "$FZX_FZF_DEFAULT_BINDS")"
  if [[ "$from" == yours ]]; then
    action="$(fzx::user_binds 2> /dev/null | awk -F'\t' -v k="$key" '$1 == k { print $2; exit }')"
  else
    action="$def"
  fi
  printf '%s%s%s  %s%s%s\n\n' "$B" "$key" "$R" "$D" "$from" "$R"
  printf '%s\n' "$action" | sed 's/+/\n  +/g' | fold -s -w "${FZF_PREVIEW_COLUMNS:-80}"
  [[ "$from" == yours && -n "$def" ]] && printf '\n%sover fzf%s  %s\n' "$D" "$R" "$def"
  return 0
}

# keybindings::preview <id> <display> <data>
keybindings::preview() {
  [[ -n "${1:-}" ]] || return 0
  case "${FZX_MODE:-zsh}" in
    zsh) keybindings::preview_zsh "$1" "${3:-}" ;;
    tmux) FZX_MODE=keys "$FZX_ROOT/modules/tmux/preview.sh" -- "$@" ;;
    fzf) keybindings::preview_fzf "$1" "${3:-}" ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$KEYS_DIR" keybindings
  keybindings::preview "$@"
}
