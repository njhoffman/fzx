#!/usr/bin/env bash
# colors actions: copy the selection's hex values, SGR parameters or escape sequences; the theme's reset,
# revert, save, copy and sample; the transforms behind the theme's enter (edit) and the picker's (pick)

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# colors::action <hex|sgr|escape|reset|revert|save|colors|sample> <values...> (hex: the hex fields; sgr,
# escape: the sgr fields; reset: ids)
colors::action() {
  local action="${1:-}" v out=()
  shift
  fzx::require builtin
  case "$action" in
    hex | sgr) for v; do [[ -n "$v" ]] && out+=("$v"); done ;;
    escape) for v; do [[ -n "$v" ]] && out+=("\\e[${v}m"); done ;;
    reset) colors::theme_reset "$@"; return ;;
    revert) colors::theme_revert; return ;;
    save) colors::theme_save; return ;;
    colors)
      colors::theme_fzf_spec v
      [[ -n "$v" ]] || { printf 'colors: no fzf colors set\n' >&2; return 1; }
      out+=("--color=$v")
      ;;
    sample) colors::theme_sample toggle; return ;;
    *)
      printf 'colors: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  ((${#out[@]})) || return 0
  printf '%s\n' "${out[@]}" | fzx::clip
}

# colors::theme_dir <var>: the colors session's directory (the picker's parent from colors:pick)
colors::theme_dir() {
  local _f
  colors::theme_pending_file _f || return 1
  printf -v "$1" '%s' "${_f%/state/theme_pending}"
}

# colors::theme_reset <id...>: back to the value without the theme: a pending edit is dropped, a saved
# override becomes a pending reset (it goes when the theme is saved)
colors::theme_reset() {
  local id saved
  saved="$(colors::theme_saved)"
  colors::theme_unpend "$@"
  for id; do
    [[ -n "$id" && "$id" != - ]] || continue
    awk -F'\t' -v id="$id" '$1 == id { f = 1 } END { exit !f }' <<< "$saved" && colors::theme_pend "$id" -
  done
  colors::theme_sample refresh
}

# colors::theme_revert: drop every unsaved edit
colors::theme_revert() {
  local f
  colors::theme_pending_file f || return 1
  rm -f -- "$f"
  colors::theme_sample refresh
}

# colors::theme_save: the saved overrides with the pending edits on top, into theme.sh; pending is emptied
colors::theme_save() {
  local f pending saved fzf="" line id val
  local -a fzx=()
  colors::theme_pending_file f || return 1
  pending="$(colors::theme_pending)"
  [[ -n "$pending" ]] || { printf 'colors: nothing to save\n' >&2; return 1; }
  saved="$(colors::theme_saved)"
  while IFS=$'\t' read -r id val; do
    [[ -n "$id" && "$val" != - ]] || continue
    if [[ "$id" == fzf:* ]]; then
      fzf+="${fzf:+,}${id#fzf:}:$val"
    else
      fzx+=("FZX_COLORS[${id#fzx:}]=\"$val\"")
    fi
  done < <(printf '%s\n%s\n' "$saved" "$pending" | awk -F'\t' 'NF { v[$1] = $2; if (!($1 in o)) { o[$1] = ++n; k[n] = $1 } }
    END { for (i = 1; i <= n; i++) print k[i] "\t" v[k[i]] }')
  mkdir -p -- "$(dirname -- "$(colors::theme_file)")" || return 1
  {
    printf '#!/usr/bin/env bash\n'
    printf '# fzx colors:theme writes this file when you save there: it is a config layer after config.sh, so what\n'
    printf '# it sets wins over it. Saving again rewrites it: keep hand-made settings in config.sh.\n'
    printf '# shellcheck disable=SC2034\n'
    printf 'declare -gA FZX_COLORS\n'
    # shellcheck disable=SC2016  # written as is: theme.sh expands it when it is loaded
    [[ -n "$fzf" ]] && printf 'FZX_FZF_COLORS+="${FZX_FZF_COLORS:+,}%s"\n' "$fzf"
    for line in "${fzx[@]}"; do printf '%s\n' "$line"; done
  } > "$(colors::theme_file).tmp" && mv -- "$(colors::theme_file).tmp" "$(colors::theme_file)" || return 1
  rm -f -- "$f"
  colors::theme_sample refresh
}

# colors::theme_fzf_spec <var>: the fzf colors fzx gives fzf on top of the user's fzf options, with the
# theme and the pending edits: config.sh's FZX_FZF_COLORS, the saved theme, the edits
colors::theme_fzf_spec() {
  local _id _val _org _items=""
  while IFS=$'\x1f' read -r _id _val _org _ _; do
    [[ "$_id" == fzf:* && -n "$_val" ]] || continue
    case "$_org" in fzx | theme | pending | reset) _items+="${_items:+,}${_id#fzf:}:$_val" ;; esac
  done < <(colors::theme_values | tr '\t' '\037')
  printf -v "$1" '%s' "$_items"
}

# colors::theme_sample <toggle|refresh>: the sample fzf in a tmux split beside fzx, in the pending colors.
# toggle opens or closes it; refresh restarts it when it is open (fzf cannot change colors while it runs).
# The pane is recorded in the colors session (state/theme_sample) and closes itself when fzx ends.
colors::theme_sample() {
  local dir pane="" spec root="" placement="" cmd
  colors::theme_dir dir || return 1
  fzx::_kv_get "$dir/state/theme_sample" pane 2> /dev/null || :
  if [[ -n "$pane" && "$(tmux display-message -p -t "$pane" '#{pane_id}' 2> /dev/null)" != "$pane" ]]; then
    pane=""
  fi
  case "$1" in
    refresh) [[ -n "$pane" ]] || return 0 ;;
    toggle)
      if [[ -n "$pane" ]]; then
        tmux kill-pane -t "$pane" 2> /dev/null || :
        fzx::_kv_set "$dir/state/theme_sample" ""
        return 0
      fi
      [[ -n "${TMUX:-}" ]] || { printf 'colors: the sample needs tmux\n' >&2; return 1; }
      fzx::_kv_get "$dir/meta/root" root 2> /dev/null || :
      fzx::_kv_get "$FZX_SESSIONS_DIR/${root:-x}/state/placement" placement 2> /dev/null || :
      if [[ "$placement" == popup* ]]; then
        printf 'colors: the sample opens in a split, behind a popup: move fzx inline first (alt-^)\n' >&2
        return 1
      fi
      ;;
  esac
  colors::theme_fzf_spec spec
  fzx::_kv_set "$dir/state/theme_sample_colors" "$spec"
  printf -v cmd '%q %q %q' bash "$COLORS_DIR/sample.sh" "$dir"
  local env=(-e "FZF_DEFAULT_OPTS_FILE=${FZF_DEFAULT_OPTS_FILE:-}" -e "FZF_DEFAULT_OPTS=${FZF_DEFAULT_OPTS:-}")
  if [[ -n "$pane" ]]; then
    tmux respawn-pane -k "${env[@]}" -t "$pane" "$cmd"
  else
    local at=()
    [[ -n "${TMUX_PANE:-}" ]] && at=(-t "$TMUX_PANE")
    pane="$(tmux split-window -d -h -l 45% "${env[@]}" "${at[@]}" -P -F '#{pane_id}' "$cmd")" || return 1
    fzx::_kv_set "$dir/state/theme_sample" "$pane"
  fi
}

# colors::_value_attrs <id> <value>: the picker toggles a value has on (bold dim italic underline reverse)
colors::_value_attrs() {
  local t a i on=() p=()
  if [[ "$1" == fzf:* ]]; then
    IFS=: read -r -a p <<< "$2"
    for t in "${p[@]}"; do
      for a in "${COLORS_ATTRS[@]}"; do [[ "$t" == "${a%%:*}" ]] && on+=("$t"); done
    done
  else
    IFS=';:' read -r -a p <<< "$2"
    for ((i = 0; i < ${#p[@]}; i++)); do
      t="${p[i]}"
      # the numbers after 38;5 / 48;5 (one) and 38;2 / 48;2 (three) are a color, not attributes
      if [[ "$t" == 38 || "$t" == 48 ]]; then
        case "${p[i + 1]:-}" in 5) ((i += 2)) ;; 2) ((i += 4)) ;; esac
        continue
      fi
      for a in "${COLORS_ATTRS[@]}"; do [[ "$t" == "${a#*:}" ]] && on+=("${a%%:*}"); done
    done
  fi
  printf '%s' "${on[*]}"
}

# colors::_fzf_color_ok <token>: one fzf color: -1, 0-255, #rrggbb, a name or bright-name
colors::_fzf_color_ok() {
  [[ "$1" =~ ^(-1|[0-9]{1,3}|#[0-9a-fA-F]{6}|(bright-)?(black|red|green|yellow|blue|magenta|cyan|white))$ ]] || return 1
  [[ "$1" =~ ^[0-9]+$ ]] && (($1 > 255)) && return 1
  return 0
}

# colors::fzf_value_ok <value>: fzf's color syntax: colors and attributes, colon-separated
colors::fzf_value_ok() {
  local t IFS=:
  [[ -n "$1" && "$1" != *::* && "$1" != :* && "$1" != *: ]] || return 1
  for t in $1; do
    colors::_fzf_color_ok "$t" && continue
    [[ "$t" =~ ^(regular|bold|dim|italic|underline|reverse|blink|strikethrough|strip)$ ]] || return 1
  done
}

# colors::pick_value <id> <current value> <row id> <query> <var>: what the picker sets: "-" for the reset
# row, a palette number or the typed value with the toggles' attributes; fails on a value that is none
colors::pick_value() {
  local _id="$1" _cur="$2" _row="$3" _q="$4" _color="" _a _attrs=() _codes=() _bg="" _hex
  for _a in "${COLORS_ATTRS[@]}"; do
    [[ " ${FZX_TOGGLES:-} " == *" ${_a%%:*} "* ]] && { _attrs+=("${_a%%:*}"); _codes+=("${_a#*:}"); }
  done
  [[ "$_row" == - ]] && { printf -v "$5" '%s' - && return 0; }
  if [[ "$_id" == fzf:* ]]; then
    if [[ -n "$_row" ]]; then
      _color="$_row"
    elif colors::_fzf_color_ok "$_q"; then
      _color="$_q"
    elif colors::fzf_value_ok "$_q"; then
      printf -v "$5" '%s' "$_q" && return 0
    else
      return 1
    fi
    local IFS=:
    printf -v "$5" '%s' "${_color}${_attrs[*]:+:${_attrs[*]}}"
    return 0
  fi
  # fzx: SGR parameters, the attributes first; the current value's background stays
  [[ "$_cur" =~ (^|;)(48;(5;[0-9]+|2;[0-9]+;[0-9]+;[0-9]+))($|;) ]] && _bg="${BASH_REMATCH[2]}"
  if [[ -n "$_row" ]]; then
    _color="38;5;$_row"
  elif [[ "$_q" =~ ^#[0-9a-fA-F]{6}$ ]]; then
    _hex="${_q:1}"
    _color="38;2;$((16#${_hex:0:2}));$((16#${_hex:2:2}));$((16#${_hex:4:2}))"
  elif [[ "$_q" =~ ^[0-9]{1,3}$ ]] && ((_q < 256)); then
    _color="38;5;$_q"
  elif [[ "$_q" =~ ^[0-9]+([;:][0-9]+)*$ ]]; then
    printf -v "$5" '%s' "$_q" && return 0
  else
    return 1
  fi
  local IFS=';'
  printf -v "$5" '%s' "${_codes[*]}${_codes[*]:+;}$_color${_bg:+;$_bg}"
}

# colors::_pick_args <args...>: the picker's --key ID and --value VALUE into COLORS_PICK_ID, COLORS_PICK_VALUE
colors::_pick_args() {
  COLORS_PICK_ID="" COLORS_PICK_VALUE=""
  while (($#)); do
    case "$1" in
      --key) COLORS_PICK_ID="${2:-}" && shift ;;
      --value) COLORS_PICK_VALUE="${2:-}" && shift ;;
    esac
    shift
  done
  [[ -n "$COLORS_PICK_ID" ]]
}

# colors::transform <edit ID VALUE | pick ROW>
#   edit  enter in colors:theme: the picker for that setting, a child session, its toggles set from the
#         value's attributes and its query emptied
#   pick  enter in colors:pick: the value into the theme's pending edits, the sample restarted, back to the
#         list (which reads its rows again)
colors::transform() {
  case "${1:-}" in
    edit) colors::_transform_edit "${2:-}" "${3:-}" ;;
    pick) colors::_transform_pick "${2:-}" ;;
    *)
      printf 'colors: unknown transform: %s\n' "${1:-}" >&2
      return 2
      ;;
  esac
}

colors::_transform_edit() {
  local id="$1" value="$2" act child
  [[ "$id" == fzf:* || "$id" == fzx:* ]] || { printf 'bell'; return 0; }
  fzx::require nav
  act="$(fzx::nav goto colors:pick --key "$id" --value "$value")" || return
  if [[ "$act" =~ --resume\ ([^ ]+) && -d "$FZX_SESSIONS_DIR/${BASH_REMATCH[1]}" ]]; then
    child="$FZX_SESSIONS_DIR/${BASH_REMATCH[1]}"
    fzx::_kv_set "$child/state/toggles" "$(colors::_value_attrs "$id" "$value")"
    fzx::_kv_set "$child/state/query" ""
    fzx::_kv_set "$child/state/pos" 1
  fi
  printf '%s' "$act"
}

colors::_transform_pick() {
  local row="$1" value dir act
  # the picker's --key and --value: callbacks other than the source do not load the args
  fzx::session_args
  colors::_pick_args "${FZX_ARGS[@]}" || { printf 'bell'; return 0; }
  if ! colors::pick_value "$COLORS_PICK_ID" "$COLORS_PICK_VALUE" "$row" "${FZF_QUERY:-}" value; then
    fzx::require callback
    fzx::footer_note "not a color: ${FZF_QUERY:-} (#rrggbb, 0-255, or fzf's or SGR syntax)" "${FZX_COLORS[notify_fail]:-}" act
    printf '%s' "$act"
    return 0
  fi
  if [[ "$value" == - ]]; then
    colors::theme_reset "$COLORS_PICK_ID"
  else
    colors::theme_pend "$COLORS_PICK_ID" "$value"
    colors::theme_sample refresh
  fi
  # the list reads its rows again when it comes back
  colors::theme_dir dir && fzx::_kv_set "$dir/state/fresh" 1
  fzx::require nav
  fzx::nav back
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log
  colors::action "$@"
}
