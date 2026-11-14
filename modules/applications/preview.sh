#!/usr/bin/env bash
# applications preview: the icon (looked up in the icon theme, drawn with chafa), the name, generic name and
# comment, then the ID, command, categories, keywords, the entry's own actions and its file

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# applications::icon_theme: the icon theme name (FZX_APPLICATIONS_ICON_THEME, GTK's settings.ini, gsettings)
applications::icon_theme() {
  local t="${FZX_APPLICATIONS_ICON_THEME:-}"
  [[ -n "$t" ]] || t="$(sed -n 's/^gtk-icon-theme-name *= *//p' "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2> /dev/null | head -1)"
  [[ -n "$t" ]] || ! command -v gsettings > /dev/null ||
    t="$(command gsettings get org.gnome.desktop.interface icon-theme 2> /dev/null | tr -d "'")"
  printf '%s\n' "${t:-hicolor}"
}

# applications::icon_bases: the directories icon themes live in
applications::icon_bases() {
  local d bases=("${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons") IFS=:
  for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do bases+=("$d/icons"); done
  printf '%s\n' "${bases[@]}"
}

# applications::icon_file <icon> <var>: the file for an Icon= value: a path as it is, else a lookup in the
# theme, the theme it inherits and hicolor (apps directories in both layouts, apps/48 and 48x48/apps; an
# SVG first, else the largest PNG), then pixmaps. Fails when nothing is found
applications::icon_file() {
  local _icon="$1" _theme _t _b _f _best="" _size _bsize=-1 _themes=() _bases=() _inh _d
  printf -v "$2" '%s' ""
  [[ -n "$_icon" ]] || return 1
  if [[ "$_icon" == /* ]]; then
    [[ -f "$_icon" ]] || return 1
    printf -v "$2" '%s' "$_icon"
    return 0
  fi
  mapfile -t _bases < <(applications::icon_bases)
  _theme="$(applications::icon_theme)"
  _themes=("$_theme")
  for _b in "${_bases[@]}"; do
    [[ -f "$_b/$_theme/index.theme" ]] || continue
    _inh="$(sed -n 's/^Inherits *= *//p' "$_b/$_theme/index.theme" | head -1)"
    local IFS=,
    for _t in $_inh; do [[ "$_t" != hicolor ]] && _themes+=("$_t"); done
    unset IFS
    break
  done
  [[ "$_theme" != hicolor ]] && _themes+=(hicolor)
  local _old
  _old="$(shopt -p nullglob)"
  shopt -s nullglob
  for _t in "${_themes[@]}"; do
    for _b in "${_bases[@]}"; do
      [[ -d "$_b/$_t" ]] || continue
      for _f in "$_b/$_t"/*/apps/"$_icon".svg "$_b/$_t"/apps/*/"$_icon".svg; do
        _best="$_f"
        break 3
      done
      for _f in "$_b/$_t"/*/apps/"$_icon".png "$_b/$_t"/apps/*/"$_icon".png; do
        _d="${_f%/"$_icon".png}" _d="${_d%/apps}" _d="${_d##*/}"
        _size="${_d%%[!0-9]*}"
        [[ -n "$_size" ]] || _size=0
        ((_size > _bsize)) && _bsize="$_size" _best="$_f"
      done
      [[ -n "$_best" ]] && break 2
    done
  done
  if [[ -z "$_best" ]]; then
    for _d in "${_bases[@]%/icons}"; do
      for _f in "$_d/pixmaps/$_icon".svg "$_d/pixmaps/$_icon".png; do [[ -f "$_f" ]] && _best="$_f" && break 2; done
    done
  fi
  eval "$_old"
  [[ -n "$_best" ]] || return 1
  printf -v "$2" '%s' "$_best"
}

# applications::_field <file> <key>: a key's value in the [Desktop Entry] group
applications::_field() {
  awk -v k="$2" '
    /^\[/ { g = $0; next }
    g == "[Desktop Entry]" && index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$1" 2> /dev/null
}

# applications::_action_field <file> <action> <key>: a key's value in that [Desktop Action] group
applications::_action_field() {
  awk -v g="[Desktop Action $2]" -v k="$3" '
    /^\[/ { in_g = ($0 == g); next }
    in_g && index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$1" 2> /dev/null
}

# applications::preview <file> <id>; an action's row (<file>#action:<key>): its name, command and file
applications::preview() {
  local file="${1:-}" id="${2:-}" icon img="" rows="${FZX_APPLICATIONS_ICON_ROWS:-8}" v key
  local b=$'\e[1m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && b="" d="" r=""
  [[ "$file" != - ]] || return 0
  if [[ "$file" == *"#action:"* ]]; then
    local action="${file##*#action:}"
    file="${file%#action:*}"
    printf '%s%s%s\n%s%s%s\n\n%s\n' "$b" "$(applications::_action_field "$file" "$action" Name)" "$r" "$d" \
      "$(applications::_field "$file" Name)" "$r" "$(applications::_action_field "$file" "$action" Exec)"
    printf '\n%s%s%s\n' "$d" "$file" "$r"
    return 0
  fi
  [[ -f "$file" ]] || { printf 'no file %s\n' "$file"; return 0; }
  icon="$(applications::_field "$file" Icon)"
  applications::icon_file "$icon" img || img=""
  if [[ -n "$img" ]] && ((rows > 0)) && command -v chafa > /dev/null; then
    command chafa --format="${FZX_PREVIEW_IMAGE_FORMAT:-symbols}" --size="$((rows * 2))x$rows" --animate=off -- "$img" 2> /dev/null
    printf '\n'
  fi
  printf '%s%s%s\n' "$b" "$(applications::_field "$file" Name)" "$r"
  v="$(applications::_field "$file" GenericName)" && [[ -n "$v" ]] && printf '%s\n' "$v"
  v="$(applications::_field "$file" Comment)" && [[ -n "$v" ]] && printf '%s\n' "$v"
  printf '\n'
  for key in id Exec Categories Keywords Terminal NoDisplay Icon; do
    if [[ "$key" == id ]]; then v="$id"; else v="$(applications::_field "$file" "$key")"; fi
    [[ -n "$v" ]] || continue
    [[ "$key" == Icon && -n "${img:-}" ]] && v+="  $d$img$r"
    printf '%s%-11s%s %s\n' "$d" "${key,,}" "$r" "$v"
  done
  # [Desktop Action x] groups: their names
  v="$(awk '/^\[Desktop Action / { a = 1; next } /^\[/ { a = 0 } a && /^Name=/ { print "  " substr($0, 6) }' "$file")"
  [[ -n "$v" ]] && printf '\n%sactions%s\n%s\n' "$d" "$r" "$v"
  printf '\n%s%s%s\n' "$d" "$file" "$r"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" applications
  applications::preview "$@"
}
