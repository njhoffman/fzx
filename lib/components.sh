#!/usr/bin/env bash
# components: a module's modes, toggles, sort keys and actions, declared in one table.
#
# <module dir>/components.tsv, one row per component (columns split on tabs or on runs of 2+ spaces):
#   kind    name    key     description              flags
#   mode    user    f3      your processes           default
#   toggle  threads alt-t   include threads          on
#   action  term    ctrl-x  send SIGTERM             silent,reload
# kind: mode | toggle | sort | action; key and flags may be "-". If the file is executable it is run
# and its output read as the table (rows can then depend on what is installed or configured).
# ~/.config/fzx/modules/<module>/components.tsv replaces rows by kind+name: a field of "=" keeps the
# module's value, the flag "off" removes the row, rows with new names are added.
# The resolved table is stored in the session (meta/components), so callbacks read it without config.

# fzx::_comp_parse < table: normalized "kind<TAB>name<TAB>key<TAB>description<TAB>flags" rows
fzx::_comp_parse() {
  awk -v src="$1" 'BEGIN { OFS = "\t" }
    /^[ \t]*(#|$)/ { next }
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line); gsub(/\t+/, "  ", line)
      n = split(line, f, /  +/)
      if (n < 2 || f[1] !~ /^(mode|toggle|sort|action)$/ || f[2] !~ /^[A-Za-z0-9_-]+$/) {
        printf "fzx: %s:%d: bad component row: %s\n", src, NR, $0 > "/dev/stderr"; next }
      for (i = n + 1; i <= 5; i++) f[i] = "-"
      print f[1], f[2], f[3], f[4], f[5] }'
}

# fzx::_comp_read <file>: a table file's rows (run when executable)
fzx::_comp_read() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if [[ -x "$file" ]]; then
    FZX_MODULE_DIR="$FZX_MODULE_DIR" FZX_MODULE="$FZX_MODULE" "$file" | fzx::_comp_parse "$file"
  else
    # shellcheck disable=SC2094  # the name is only used in error messages
    fzx::_comp_parse "$file" < "$file"
  fi
}

# fzx::comp_load <module_dir> <module>: resolve the table into FZX_COMP (rows) and FZX_MODES
fzx::comp_load() {
  local dir="$1" module="$2"
  FZX_COMP=()
  mapfile -t FZX_COMP < <(
    { fzx::_comp_read "$dir/components.tsv" | sed 's/^/0\t/'
      fzx::_comp_read "$FZX_CONFIG_DIR/modules/$module/components.tsv" | sed 's/^/1\t/'; } |
      awk -F'\t' 'BEGIN { OFS = "\t" }
        { key = $2 SUBSEP $3
          if ($1 == 0 || !(key in row)) { if (!(key in row)) order[++n] = key; row[key] = $2 OFS $3 OFS $4 OFS $5 OFS $6; next }
          split(row[key], old, "\t")
          for (i = 3; i <= 5; i++) if ($(i + 1) == "=") $(i + 1) = old[i]
          row[key] = $2 OFS $3 OFS $4 OFS $5 OFS $6 }
        END { for (i = 1; i <= n; i++) { split(row[order[i]], f, "\t"); if (("," f[5] ",") !~ /,off,/) print row[order[i]] } }'
  )
  fzx::_comp_modes
}

# fzx::comp_load_session: the table stored at launch (callbacks); resolved from the module when a
# session has none (created without a launch, or by an older fzx)
fzx::comp_load_session() {
  FZX_COMP=()
  if [[ -f "$FZX_SESSION_DIR/meta/components" ]]; then
    mapfile -t FZX_COMP < "$FZX_SESSION_DIR/meta/components"
    fzx::_comp_modes
  else
    fzx::comp_load "$FZX_MODULE_DIR" "$FZX_MODULE"
  fi
}

fzx::comp_save() {
  printf '%s\n' "${FZX_COMP[@]}" > "$FZX_SESSION_DIR/meta/components"
}

# FZX_MODES from the mode rows, the "default" one first ("main" when there are none)
fzx::_comp_modes() {
  local row kind name flags def=""
  FZX_MODES=()
  for row in "${FZX_COMP[@]}"; do
    IFS=$'\t' read -r kind name _ _ flags <<< "$row"
    [[ "$kind" == mode ]] || continue
    FZX_MODES+=("$name")
    [[ -z "$def" && ",$flags," == *,default,* ]] && def="$name"
  done
  ((${#FZX_MODES[@]})) || FZX_MODES=(main)
  # shellcheck disable=SC2034  # read by lib/run.sh
  FZX_MODE_DEFAULT="${def:-${FZX_MODES[0]}}"
}

# fzx::comp_rows <kind>: rows of one kind, in table order
fzx::comp_rows() {
  local row
  for row in "${FZX_COMP[@]}"; do
    [[ "$row" == "$1"$'\t'* ]] && printf '%s\n' "$row"
  done
}

# fzx::comp_has <kind>: the table has at least one row of that kind (no pipe: under pipefail a
# "comp_rows | grep -q" fails when grep exits first and the writer gets SIGPIPE)
fzx::comp_has() {
  local _row
  for _row in "${FZX_COMP[@]}"; do
    [[ "$_row" == "$1"$'\t'* ]] && return 0
  done
  return 1
}

# fzx::comp_field <kind> <name> <key|description|flags> <var>; fails when there is no such row
fzx::comp_field() {
  local _row _k _n _key _desc _flags
  for _row in "${FZX_COMP[@]}"; do
    IFS=$'\t' read -r _k _n _key _desc _flags <<< "$_row"
    [[ "$_k" == "$1" && "$_n" == "$2" ]] || continue
    case "$3" in
      key) printf -v "$4" '%s' "$_key" ;;
      description) printf -v "$4" '%s' "$_desc" ;;
      flags) printf -v "$4" '%s' "$_flags" ;;
    esac
    return 0
  done
  return 1
}

# fzx::comp_flag <kind> <name> <flag>: the row carries the flag
fzx::comp_flag() {
  # not _flags: comp_field has a local of that name, which would swallow the result
  local __cf_flags
  fzx::comp_field "$1" "$2" flags __cf_flags && [[ ",$__cf_flags," == *",$3,"* ]]
}

# fzx::comp_current: resolve and export FZX_TOGGLES (names that are on, space-separated, table order)
# and FZX_SORT. Session state wins (state/toggles, state/sort); otherwise the environment (a standalone
# run), otherwise the table's defaults (toggles flagged "on", the sort flagged "default", else the first).
fzx::comp_current() {
  local _row _k _n _f _have_state=0 _t="" _s="" _first_sort="" _def_sort=""
  if [[ -n "${FZX_SESSION_DIR:-}" && -f "$FZX_SESSION_DIR/state/toggles" ]]; then
    fzx::_kv_get "$FZX_SESSION_DIR/state/toggles" _t || :
    _have_state=1
  elif [[ -n "${FZX_TOGGLES+set}" ]]; then
    _t="$FZX_TOGGLES"
    _have_state=1
  fi
  for _row in "${FZX_COMP[@]}"; do
    IFS=$'\t' read -r _k _n _ _ _f <<< "$_row"
    if [[ "$_k" == toggle ]] && ((!_have_state)) && [[ ",$_f," == *,on,* ]]; then
      _t+="${_t:+ }$_n"
    elif [[ "$_k" == sort ]]; then
      [[ -n "$_first_sort" ]] || _first_sort="$_n"
      [[ -z "$_def_sort" && ",$_f," == *,default,* ]] && _def_sort="$_n"
    fi
  done
  if [[ -n "${FZX_SESSION_DIR:-}" ]] && fzx::_kv_get "$FZX_SESSION_DIR/state/sort" _s 2> /dev/null; then
    :
  else
    _s="${FZX_SORT:-}"
  fi
  # a sort name that is not (or no longer) in the table falls back to the default
  [[ -n "$_s" ]] && ! fzx::comp_field sort "$_s" key _ 2> /dev/null && _s=""
  [[ -n "$_s" ]] || _s="${_def_sort:-$_first_sort}"
  FZX_TOGGLES="$_t" FZX_SORT="$_s"
  export FZX_TOGGLES FZX_SORT
}

# fzx::comp_on <toggle>: the toggle is on (expects comp_current)
fzx::comp_on() {
  [[ " $FZX_TOGGLES " == *" $1 "* ]]
}

# fzx::data_key <var>: cache key for the current view: the mode, plus "+toggles" and "@sort" when the
# table has toggles / sort keys, so each combination is cached on its own
fzx::data_key() {
  local _key="$FZX_MODE"
  fzx::comp_has toggle && _key+="+${FZX_TOGGLES// /,}"
  [[ -n "$FZX_SORT" ]] && _key+="@$FZX_SORT"
  printf -v "$1" '%s' "$_key"
}
