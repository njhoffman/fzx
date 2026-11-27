#!/usr/bin/env bash
# files source. Lines are "absolute path<TAB>display" (files, dirs), sorted by path, or
# "absolute path<TAB>line<TAB>display" (grep). Mode from $FZX_MODE: files (default), dirs, grep, locate
# (plocate or locate, as you type: "absolute path<TAB>display").
# grep searches for $FZF_QUERY, which fzf exports to the reload it runs on every query change, with ripgrep,
# else grep; while fzf filters the matches (files::transform filter) it searches the term frozen then. Toggles: hidden (on at start), ignored, follow (symbolic links listed, not entered, while off), multiline
# (grep: ripgrep's -U).
# Sorts: path, recent.

# files::base [DIR]: absolute base directory into FILES_BASE; a file argument means its directory
files::base() {
  local dir="${1:-$PWD}"
  if [[ -f "$dir" ]]; then
    if [[ "$dir" == */* ]]; then dir="${dir%/*}"; else dir=.; fi
    dir="${dir:-/}"
  fi
  if [[ ! -d "$dir" ]]; then
    printf 'files: not a directory: %s\n' "$dir" >&2
    return 2
  fi
  # physical path: fd and rg report resolved paths, so a symlinked base would never prefix-match
  FILES_BASE="$(cd -- "$dir" && pwd -P)"
}

# fd is packaged as fdfind on Debian/Ubuntu
files::fd() {
  if command -v fd > /dev/null; then
    command fd "$@"
  else
    command fdfind "$@"
  fi
}

# files::on <toggle>: that toggle is on (hidden is on at start, ignored and follow off)
files::on() { [[ " ${FZX_TOGGLES-hidden} " == *" $1 "* ]]; }

# files::sort: paths in the order of the sort: path (component by component: "a/b" before "a-b", "fzf/"
# before "fzf-rsc/") or recent (newest modification first)
files::sort() {
  if [[ "${FZX_SORT:-path}" == recent ]]; then
    # %Y of the link itself when it is broken (stat -L fails); -- keeps "-" names as paths
    xargs -r -d '\n' stat -L -c $'%Y\t%n' -- 2> /dev/null | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 | cut -f2-
  else
    awk '{ k = $0; sub(/\/$/, "", k); gsub(/\//, "\001", k); print k "\t" $0 }' | LC_ALL=C sort -t $'\t' -k1,1 | cut -f2-
  fi
}

# files::fd_args <var>: fd's options for the toggles and FZX_FILES_EXCLUDES
files::fd_args() {
  local -n _args="$1"
  local _ex
  _args=(--color=never --absolute-path)
  files::on hidden && _args+=(--hidden)
  files::on ignored && _args+=(--no-ignore)
  for _ex in "${FZX_FILES_EXCLUDES[@]}"; do _args+=(--exclude "$_ex"); done
  files::flags_add fd _args
}

# files::list <f|d>: absolute paths under FILES_BASE, directories with a trailing "/", in sort order. With
# follow off, symbolic links are listed by what they point to (a link to a directory in dirs, to a file in
# files; broken ones dropped) but never descended into.
files::list() {
  local type="$1" args link rc
  files::fd_args args
  if files::on follow; then
    files::fd --type "$type" --follow "${args[@]}" . "$FILES_BASE" | files::sort
    return "${PIPESTATUS[0]}"
  fi
  {
    files::fd --type "$type" "${args[@]}" . "$FILES_BASE"
    rc=$?
    files::fd --type l "${args[@]}" . "$FILES_BASE" | while IFS= read -r link; do
      if [[ -d "$link" ]]; then
        [[ "$type" == d ]] && printf '%s/\n' "$link"
      elif [[ -e "$link" && "$type" == f ]]; then
        printf '%s\n' "$link"
      fi
    done
    return "$rc"
  } | files::sort
  return "${PIPESTATUS[0]}"
}

# files::grep <pattern>: "path:line:text" for every match under FILES_BASE. ripgrep (smart case); without it
# grep -E (case-insensitive unless the pattern has a capital, binary files skipped). The toggles apply to
# both, except that grep has no ignore files: it searches what .gitignore excludes too, and cannot match
# across lines (the multiline toggle is ripgrep's -U, each line of a match its own row). Both exit 1 when
# nothing matches.
files::grep() {
  local args ex
  if command -v rg > /dev/null; then
    files::rg_args args
    args+=(--color=never)
    files::on multiline && args+=(--multiline --multiline-dotall)
    command rg "${args[@]}" -- "$1" "$FILES_BASE"
  else
    args=(--line-number --color=never --binary-files=without-match -E)
    if files::on follow; then args+=(-R); else args+=(-r); fi
    [[ "$1" == *[[:upper:]]* ]] || args+=(-i)
    # '.?*', not '.*': grep matches --exclude-dir against the "." it is given too
    files::on hidden || args+=(--exclude='.*' --exclude-dir='.?*')
    for ex in "${FZX_FILES_EXCLUDES[@]}"; do args+=(--exclude-dir="$ex"); done
    # from inside the base: --exclude-dir would skip a base like ~/.config given by its path
    (cd -- "$FILES_BASE" && command grep "${args[@]}" -- "$1" .) | awk -v base="$FILES_BASE/" '{ sub(/^\.\//, ""); print base $0 }'
    return "${PIPESTATUS[0]}"
  fi
}

# files::grep_term <var>: the term grep mode searches while fzf filters its matches (the var is left alone
# otherwise, and outside a session)
files::grep_term() {
  local _on="" _term=""
  [[ -n "${FZX_SESSION_DIR:-}" ]] && declare -F fzx::state_get > /dev/null || return 0
  fzx::state_get files_grep_filter _on 2> /dev/null || return 0
  [[ -n "$_on" ]] || return 0
  fzx::state_get files_grep_term _term 2> /dev/null || _term=""
  printf -v "$1" '%s' "$_term"
}

# files::args [DIR] [--term T] [--tool rg|fd]: FILES_DIR (the directory argument), FILES_TERM (the replace mode's
# term) and FILES_TOOL (the args mode's: whose flags it edits)
files::args() {
  declare -g FILES_DIR="" FILES_TERM="" FILES_TOOL=""
  while (($#)); do
    case "$1" in
      --term)
        FILES_TERM="${2-}"
        (($# > 1)) && shift
        shift
        ;;
      --tool)
        FILES_TOOL="${2-}"
        [[ "$FILES_TOOL" == rg || "$FILES_TOOL" == fd ]] || {
          printf 'files: --tool is rg or fd, got: %s\n' "$FILES_TOOL" >&2
          return 2
        }
        shift 2
        ;;
      --) shift ;;
      *)
        if [[ -n "$FILES_DIR" ]]; then
          printf 'files: at most one directory, got: %s %s\n' "$FILES_DIR" "$*" >&2
          return 2
        fi
        FILES_DIR="$1"
        shift
        ;;
    esac
  done
}

# files::rg_args <var>: ripgrep's options for the toggles and FZX_FILES_EXCLUDES (grep and replace)
files::rg_args() {
  local -n _a="$1"
  local _ex
  _a=(--line-number --no-heading --smart-case)
  files::on hidden && _a+=(--hidden)
  files::on ignored && _a+=(--no-ignore)
  files::on follow && _a+=(--follow)
  for _ex in "${FZX_FILES_EXCLUDES[@]}"; do _a+=(--glob "!$_ex"); done
  files::flags_add rg _a
}

# The flags alt-a may add to rg (grep, replace) and fd (files, dirs), as "names<TAB>value<TAB>description" with
# names "|"-separated and value 1 when the flag takes one (the next word, attached to a short flag, or after
# "=" on a long one). Only flags that leave the rows as the source reads them: not rg's --json, -l, -c,
# --vimgrep or context lines, not rg's -e (the term would be read as a path), not fd's -t (the mode's) or -g
# (fd would read the "." pattern as a glob). The toggles cover hidden, ignored, follow and multiline.
# shellcheck disable=SC2034  # read through namerefs (FILES_FLAGS_${tool^^})
FILES_FLAGS_RG=(
  $'-t|--type\t1\tonly files of this type (rg --type-list)'
  $'-T|--type-not\t1\tnot files of this type'
  $'-g|--glob\t1\tonly paths matching the glob; !GLOB leaves them out'
  $'--iglob\t1\tthe same, ignoring case'
  $'-F|--fixed-strings\t0\tthe term is a plain string, not a regular expression'
  $'-w|--word-regexp\t0\tonly matches with word boundaries around them'
  $'-x|--line-regexp\t0\tonly matches that are the whole line'
  $'-s|--case-sensitive\t0\tcase-sensitive (smart case is the default)'
  $'-i|--ignore-case\t0\tcase-insensitive'
  $'-P|--pcre2\t0\tPCRE2 regular expressions (look-around, backreferences)'
  $'-d|--max-depth\t1\tdescend at most this many directories'
  $'-m|--max-count\t1\tat most this many matching lines per file'
  $'--max-filesize\t1\tskip files larger than this (50K, 10M)'
)
# shellcheck disable=SC2034  # read through namerefs
FILES_FLAGS_FD=(
  $'-e|--extension\t1\tonly this extension (repeat for more)'
  $'-E|--exclude\t1\tleave out paths matching the glob'
  $'-d|--max-depth\t1\tdescend at most this many directories'
  $'--min-depth\t1\tonly paths at least this deep'
  $'-S|--size\t1\tby size: +10k at least, -1M at most'
  $'--changed-within\t1\tmodified within: 2weeks, 1d, 2026-01-01'
  $'--changed-before\t1\tmodified before: the same forms'
  $'-o|--owner\t1\tby owner: user, :group, user:group'
)

# Why a flag left out of the lists above is refused, as "names<TAB>reason": a toggle's own flags name the toggle
# (the reason is then "toggle NAME"), the others say what they would break
# shellcheck disable=SC2034  # read through namerefs (FILES_FLAGS_OUT_${tool^^})
FILES_FLAGS_OUT_RG=(
  $'--hidden|-.\ttoggle hidden'
  $'--no-ignore|-u|-uu|-uuu|--no-ignore-vcs\ttoggle ignored'
  $'-L|--follow\ttoggle follow'
  $'-U|--multiline|--multiline-dotall\ttoggle multiline'
  $'-e|--regexp\tthe term is what you type in grep, not a flag (as a flag the term would be read as a path)'
  $'-r|--replace\tthe replacement is what you type on the replace screen (alt-s)'
  $'--json|-l|--files-with-matches|--files-without-match|-c|--count|--count-matches|--vimgrep|-o|--only-matching|-N|--no-line-number|--no-filename|-I|-0|--null|--null-data|-b|--byte-offset|--column|--heading|-p|--pretty|--files|--type-list|--stats\tit changes the rows rg prints, which fzx reads as path, line and text'
  $'-A|--after-context|-B|--before-context|-C|--context|--passthru\tcontext lines are rows fzx would read as matches (the preview shows the context)'
)
# shellcheck disable=SC2034  # read through namerefs
FILES_FLAGS_OUT_FD=(
  $'-H|--hidden\ttoggle hidden'
  $'-I|--no-ignore|-u|--unrestricted|--no-ignore-vcs\ttoggle ignored'
  $'-L|--follow\ttoggle follow'
  $'-t|--type\tthe type is the mode'"'"'s: files or dirs'
  $'-g|--glob\tfd would read the "." pattern fzx passes as a glob (-E excludes by glob)'
  $'-x|--exec|-X|--exec-batch\tit runs a command on every path'
  $'-l|--list-details|-0|--print0|-a|--absolute-path|--format|-p|--full-path|--strip-cwd-prefix\tit changes the paths fd prints, which fzx reads'
)

# files::_flag_names <rg|fd> <array var>: every name the tool's list allows
files::_flag_names() {
  local -n _fn_rows="FILES_FLAGS_${1^^}" _fn_out="$2"
  local _fn_row _fn_names
  _fn_out=()
  for _fn_row in "${_fn_rows[@]}"; do
    IFS='|' read -ra _fn_names <<< "${_fn_row%%$'\t'*}"
    _fn_out+=("${_fn_names[@]}")
  done
}

# files::_distance <a> <b> <var>: the edit distance (insert, delete, substitute) between two words
files::_distance() {
  local _d_a="$1" _d_b="$2" _d_i _d_j _d_cost _d_prev=() _d_cur=() _d_m
  for ((_d_j = 0; _d_j <= ${#_d_b}; _d_j++)); do _d_prev[_d_j]=$_d_j; done
  for ((_d_i = 1; _d_i <= ${#_d_a}; _d_i++)); do
    _d_cur=("$_d_i")
    for ((_d_j = 1; _d_j <= ${#_d_b}; _d_j++)); do
      _d_cost=1
      [[ "${_d_a:_d_i-1:1}" == "${_d_b:_d_j-1:1}" ]] && _d_cost=0
      _d_m=$((_d_prev[_d_j] + 1))
      ((_d_cur[_d_j - 1] + 1 < _d_m)) && _d_m=$((_d_cur[_d_j - 1] + 1))
      ((_d_prev[_d_j - 1] + _d_cost < _d_m)) && _d_m=$((_d_prev[_d_j - 1] + _d_cost))
      _d_cur[_d_j]=$_d_m
    done
    _d_prev=("${_d_cur[@]}")
  done
  printf -v "$3" '%s' "${_d_prev[${#_d_b}]}"
}

# files::_flag_nearest <rg|fd> <flag> <var>: the allowed name closest to the flag, among names of its kind
# (long or short), when it is close enough to be a typo (a third of its length, at least 2); empty otherwise
files::_flag_nearest() {
  local _nr_names=() _nr_n _nr_d _nr_best="" _nr_bd=99 _nr_max
  files::_flag_names "$1" _nr_names
  _nr_max=$((${#2} / 3))
  ((_nr_max < 2)) && _nr_max=2
  for _nr_n in "${_nr_names[@]}"; do
    [[ "$2" == --* && "$_nr_n" != --* ]] && continue
    [[ "$2" != --* && "$_nr_n" == --* ]] && continue
    files::_distance "$2" "$_nr_n" _nr_d
    ((_nr_d < _nr_bd)) && _nr_bd=$_nr_d _nr_best="$_nr_n"
  done
  ((_nr_bd <= _nr_max)) || _nr_best=""
  printf -v "$3" '%s' "$_nr_best"
}

# files::_flag_refusal <rg|fd> <flag> <var>: why the flag is not taken: the reason it was left out, the toggle
# that does it, or that alt-a does not know it (with the nearest name it knows)
files::_flag_refusal() {
  local -n _rf_rows="FILES_FLAGS_OUT_${1^^}"
  local _rf_row _rf_why _rf_near _rf_key=""
  for _rf_row in "${_rf_rows[@]}"; do
    [[ "|${_rf_row%%$'\t'*}|" == *"|$2|"* ]] || continue
    _rf_why="${_rf_row#*$'\t'}"
    if [[ "$_rf_why" == "toggle "* ]]; then
      _rf_why="${_rf_why#toggle }"
      # the toggle's key: the session's components when loaded, else the module's own row
      if ! { declare -F fzx::comp_field > /dev/null && fzx::comp_field toggle "$_rf_why" key _rf_key 2> /dev/null; }; then
        _rf_key="$(awk -v n="$_rf_why" '$1 == "toggle" && $2 == n { print $3; exit }' \
          "$(dirname "${BASH_SOURCE[0]}")/components.tsv" 2> /dev/null)"
      fi
      [[ "$_rf_key" == - ]] && _rf_key=""
      printf -v "$3" '%s is the %s toggle%s' "$2" "$_rf_why" "${_rf_key:+ ($_rf_key)}"
    else
      printf -v "$3" '%s: %s' "$2" "$_rf_why"
    fi
    return 0
  done
  if [[ "$2" == --* ]]; then
    files::_flag_nearest "$1" "$2" _rf_near
    printf -v "$3" 'not a flag alt-a takes: %s%s' "$2" "${_rf_near:+ (did you mean $_rf_near?)}"
    return 0
  fi
  # one letter is an edit from any other: the same letter in the other case, else the short ones it takes
  local _rf_names=() _rf_n _rf_short=() _rf_other
  files::_flag_names "$1" _rf_names
  _rf_other="${2:1}"
  [[ "$_rf_other" == [[:lower:]] ]] && _rf_other="${_rf_other^^}" || _rf_other="${_rf_other,,}"
  for _rf_n in "${_rf_names[@]}"; do
    [[ "$_rf_n" == --* ]] && continue
    [[ "$_rf_n" == "-$_rf_other" ]] && _rf_near="$_rf_n"
    _rf_short+=("$_rf_n")
  done
  if [[ -n "${_rf_near:-}" ]]; then
    printf -v "$3" 'not a flag alt-a takes: %s (did you mean %s?)' "$2" "$_rf_near"
  else
    printf -v "$3" 'not a flag alt-a takes: %s (short ones: %s)' "$2" "${_rf_short[*]}"
  fi
}

# files::_flag_desc <rg|fd> <flag> <var>: the flag's description in the tool's list
files::_flag_desc() {
  local -n _fd_rows="FILES_FLAGS_${1^^}"
  local _fd_row
  for _fd_row in "${_fd_rows[@]}"; do
    [[ "|${_fd_row%%$'\t'*}|" == *"|$2|"* ]] || continue
    printf -v "$3" '%s' "${_fd_row##*$'\t'}"
    return 0
  done
  return 1
}

# files::_flag_spec <rg|fd> <flag> <var>: the flag's value column (0 or 1) into var; fails for one not allowed
files::_flag_spec() {
  local -n _fs_rows="FILES_FLAGS_${1^^}"
  local _fs_row _fs_names
  for _fs_row in "${_fs_rows[@]}"; do
    _fs_names="${_fs_row%%$'\t'*}"
    if [[ "|$_fs_names|" == *"|$2|"* ]]; then
      _fs_row="${_fs_row#*$'\t'}"
      printf -v "$3" '%s' "${_fs_row%%$'\t'*}"
      return 0
    fi
  done
  return 1
}

# files::flags_parse <rg|fd> <text> <var> [error var]: the text's flags as words into the array var, each checked
# against the tool's list; words split on blanks (no quoting). Short flags without a value may be joined (-wi),
# one that takes a value may carry it (-tpy). Fails on a flag not allowed or a missing value, saying which in
# the error var (no subshell: the words must reach the caller), or on stderr without one.
files::flags_parse() {
  local -n _fp_out="$3"
  local _fp_words=() _fp_i _fp_w _fp_name _fp_takes _fp_rest _fp_err=""
  _fp_out=()
  read -ra _fp_words <<< "$2"
  for ((_fp_i = 0; _fp_i < ${#_fp_words[@]}; _fp_i++)); do
    _fp_w="${_fp_words[_fp_i]}"
    if [[ "$_fp_w" == --*=* ]]; then
      _fp_name="${_fp_w%%=*}"
      if ! files::_flag_spec "$1" "$_fp_name" _fp_takes; then
        files::_flag_refusal "$1" "$_fp_name" _fp_err
        break
      elif [[ "$_fp_takes" != 1 ]]; then
        _fp_err="$_fp_name takes no value (in $_fp_w)"
        break
      fi
      _fp_out+=("$_fp_name" "${_fp_w#*=}")
    elif [[ "$_fp_w" =~ ^-[A-Za-z].+$ ]]; then
      # joined short flags, or a short flag with its value attached
      _fp_rest="${_fp_w:1}"
      while [[ -n "$_fp_rest" ]]; do
        _fp_name="-${_fp_rest:0:1}" _fp_rest="${_fp_rest:1}"
        files::_flag_spec "$1" "$_fp_name" _fp_takes || {
          # a whole word the out list names (-uu) says so; else the letter that is not allowed
          if [[ "$_fp_name" != "$_fp_w" ]] && files::_flag_refusal "$1" "$_fp_w" _fp_err && [[ "$_fp_err" != "not a flag"* ]]; then
            break 2
          fi
          files::_flag_refusal "$1" "$_fp_name" _fp_err
          [[ "$_fp_name" != "$_fp_w" ]] && _fp_err+=" (in $_fp_w)"
          break 2
        }
        if [[ "$_fp_takes" == 1 ]]; then
          _fp_out+=("$_fp_name" "$_fp_rest")
          _fp_rest=""
        else
          _fp_out+=("$_fp_name")
        fi
      done
    elif ! files::_flag_spec "$1" "$_fp_w" _fp_takes; then
      files::_flag_refusal "$1" "$_fp_w" _fp_err
      break
    else
      _fp_out+=("$_fp_w")
      if [[ "$_fp_takes" == 1 ]]; then
        ((_fp_i + 1 < ${#_fp_words[@]})) || {
          local _fp_desc=""
          files::_flag_desc "$1" "$_fp_w" _fp_desc
          _fp_err="$_fp_w needs a value${_fp_desc:+: $_fp_desc}"
          break
        }
        _fp_out+=("${_fp_words[++_fp_i]}")
      fi
    fi
  done
  [[ -z "$_fp_err" ]] && return 0
  _fp_out=()
  if [[ -n "${4:-}" ]]; then printf -v "$4" '%s: %s' "$1" "$_fp_err"; else printf '%s: %s\n' "$1" "$_fp_err" >&2; fi
  return 1
}

# files::_flags_file <rg|fd> <var>: where the session tree keeps the tool's flags (its root's state); fails
# outside a session
files::_flags_file() {
  local _ff_root=""
  [[ -n "${FZX_SESSION_DIR:-}" ]] && declare -F fzx::meta_get > /dev/null || return 1
  fzx::meta_get root _ff_root 2> /dev/null || _ff_root="${FZX_SESSION:-}"
  [[ -n "$_ff_root" ]] || return 1
  printf -v "$2" '%s/%s/state/files_flags_%s' "$FZX_SESSIONS_DIR" "$_ff_root" "$1"
}

# files::flags_label <tool> <flags> <var>: "rg: FLAGS  " for the front of the header (before the path, so a long
# path is what the terminal's edge cuts off, not the flags in effect), empty without flags
files::flags_label() {
  if [[ -n "$2" ]]; then printf -v "$3" '%s: %s  ' "$1" "$2"; else printf -v "$3" ''; fi
}

# files::flags_get <rg|fd> <var> / files::flags_set <rg|fd> <text>: the flags alt-a set in this session tree
# (every files screen of it: they stay through into, up, alt-r and mode changes); empty outside a session
files::flags_get() {
  local _fg_file
  printf -v "$2" '%s' ""
  files::_flags_file "$1" _fg_file && [[ -f "$_fg_file" ]] || return 0
  fzx::_kv_get "$_fg_file" "$2"
}
files::flags_set() {
  local _fs_file
  files::_flags_file "$1" _fs_file || return 1
  fzx::_kv_set "$_fs_file" "$2"
}

# files::flags_add <rg|fd> <array var>: the saved flags appended to a command's options (they were checked
# when saved; a list that no longer passes is left out and logged)
files::flags_add() {
  local _fa_text _fa_words=()
  files::flags_get "$1" _fa_text
  [[ -n "$_fa_text" ]] || return 0
  if files::flags_parse "$1" "$_fa_text" _fa_words 2> /dev/null; then
    local -n _fa_into="$2"
    _fa_into+=("${_fa_words[@]}")
  else
    declare -F fzx::log > /dev/null && fzx::log warn "files: saved $1 flags refused, left out: $_fa_text"
  fi
  return 0
}

# files::mode_tool <mode> <var>: whose flags the mode takes: rg (grep and replace, with ripgrep), fd (files,
# dirs); empty for the others
files::mode_tool() {
  case "$1" in
    grep | replace) if command -v rg > /dev/null; then printf -v "$2" rg; else printf -v "$2" ''; fi ;;
    files | dirs) printf -v "$2" fd ;;
    *) printf -v "$2" '' ;;
  esac
}

# files::flags_rows <rg|fd>: the args screen's rows, "names<TAB>display"
files::flags_rows() {
  local -n _fr_rows="FILES_FLAGS_${1^^}"
  local row names takes desc shown val b=$'\e[1m' dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && b="" dim="" rst=""
  for row in "${_fr_rows[@]}"; do
    IFS=$'\t' read -r names takes desc <<< "$row"
    val=""
    [[ "$takes" == 1 ]] && val=" VALUE"
    shown="${names//|/, }$val"
    printf '%s\t%s%-28s%s %s%s%s\n' "$names" "$b" "$shown" "$rst" "$dim" "$desc" "$rst"
  done
}

# files::replace_matches <term>: "path<TAB>line" of every line the term matches under FILES_BASE (never
# multiline: a replacement must keep each file's line count)
files::replace_matches() {
  local args
  files::rg_args args
  command rg "${args[@]}" --color=never --no-config --field-match-separator=$'\x1f' -- "$1" "$FILES_BASE" |
    awk -F '\x1f' -v OFS='\t' '{ print $1, $2 }'
  return 0
}

# files::replace_rows <term>: "path<TAB>line<TAB>display" per match: with a query (FZF_QUERY set and not
# empty) the line as the replacement leaves it, the new text green; without one the line as it is, the match
# red (an empty replacement deletes it)
files::replace_rows() {
  local args dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m' colors=()
  files::rg_args args
  if [[ -n "${FZF_QUERY:-}" ]]; then
    args+=(--replace "$FZF_QUERY")
    colors=(--colors 'match:fg:green' --colors 'match:style:bold')
  else
    colors=(--colors 'match:fg:red')
  fi
  [[ -n "${NO_COLOR:+x}" ]] && dim="" rst=""
  command rg "${args[@]}" --no-config --field-match-separator=$'\x1f' \
    "$([[ -n "${NO_COLOR:+x}" ]] && echo --color=never || echo --color=always)" \
    --colors 'path:none' --colors 'line:none' --colors 'match:none' "${colors[@]}" -- "$1" "$FILES_BASE" |
    awk -F '\x1f' -v base="$FILES_BASE/" -v dim="$dim" -v rst="$rst" '
      { path = $1; gsub(/\033\[[0-9;]*m/, "", path); line = $2; gsub(/\033\[[0-9;]*m/, "", line)
        text = $0; sub(/^[^\x1f]*\x1f[^\x1f]*\x1f/, "", text)
        rel = substr(path, 1, length(base)) == base ? substr(path, length(base) + 1) : path
        printf "%s\t%s\t%s%s:%s:%s %s\n", path, line, dim, rel, line, rst, text }'
  local rc="${PIPESTATUS[0]}"
  ((rc <= 1)) || return "$rc"
  return 0
}

# files::locate_db <var>: the database plocate (else locate) reads; fails without either tool
files::locate_db() {
  local _db
  if command -v plocate > /dev/null; then _db="${FZX_FILES_LOCATE_DB:-/var/lib/plocate/plocate.db}"
  elif command -v locate > /dev/null; then _db="${FZX_FILES_LOCATE_DB:-/var/lib/mlocate/mlocate.db}"
  else return 1; fi
  printf -v "$1" '%s' "$_db"
}

# files::_age <path> <var>: how long ago the file changed: "40m", "3h", "2d" (nothing when it cannot be read)
files::_age() {
  local _m _s
  _m="$(stat -c %Y -- "$1" 2> /dev/null)" || return 0
  _s=$((EPOCHSECONDS - _m))
  if ((_s < 3600)); then printf -v "$2" '%sm' $((_s / 60))
  elif ((_s < 86400)); then printf -v "$2" '%sh' $((_s / 3600))
  else printf -v "$2" '%sd' $((_s / 86400)); fi
}

# files::locate <words>: paths the locate database has that contain every word (any case), under FILES_BASE
# unless the everywhere toggle is on; hidden ones (a dot-named part, below the base) only with the hidden
# toggle, FZX_FILES_EXCLUDES never; paths gone since the database was built left out; at most
# FZX_FILES_LOCATE_LIMIT (2000), in sort order. The base goes to locate as one more word, so it only reads
# the paths that hold it, and the prefix is checked after
files::locate() {
  local tool=locate words=() every="" hidden="" ex
  command -v plocate > /dev/null && tool=plocate
  read -ra words <<< "$1"
  ((${#words[@]})) || return 0
  files::on everywhere && every=1
  files::on hidden && hidden=1
  [[ -n "$every" ]] || words+=("$FILES_BASE/")
  command "$tool" -i -- "${words[@]}" 2> /dev/null |
    awk -v base="$FILES_BASE/" -v every="$every" -v hidden="$hidden" -v excl="${FZX_FILES_EXCLUDES[*]}" '
      BEGIN { n = split(excl, e, " "); for (i = 1; i <= n; i++) ex[e[i]] = 1 }
      {
        if (every == "") { if (substr($0, 1, length(base)) != base) next; rel = substr($0, length(base) + 1) }
        else rel = substr($0, 2)
        k = split(rel, part, "/")
        for (i = 1; i <= k; i++) { if (part[i] in ex) next; if (hidden == "" && substr(part[i], 1, 1) == ".") next }
        print
      }' |
    command xargs -r -d '\n' stat -c %n -- 2> /dev/null |
    head -n "${FZX_FILES_LOCATE_LIMIT:-2000}" | files::sort
  return 0
}

# files::source [DIR]
files::source() {
  local mode="${FZX_MODE:-files}" dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" rst=$'\e[0m'
  files::args "$@" || return
  files::base "$FILES_DIR" || return
  case "$mode" in
    files | dirs)
      local type=f
      [[ "$mode" == dirs ]] && type=d
      fzx::require pretty
      if fzx::pretty_on; then
        files::list "$type" | fzx::pretty "$FILES_BASE"
        return "${PIPESTATUS[0]}"
      fi
      files::list "$type" |
        awk -v base="$FILES_BASE/" -v dim="$dim" -v rst="$rst" '
          { path = $0; sub(/\/$/, "", path); rel = substr(path, 1, length(base)) == base ? substr(path, length(base) + 1) : path
            n = split(rel, parts, "/"); dir = substr(rel, 1, length(rel) - length(parts[n]))
            printf "%s\t%s%s%s%s\n", path, dim, dir, rst, parts[n] }'
      return "${PIPESTATUS[0]}"
      ;;
    args)
      [[ -n "$FILES_TOOL" ]] || {
        printf 'files: args needs --tool rg|fd\n' >&2
        return 2
      }
      files::flags_rows "$FILES_TOOL"
      ;;
    replace)
      [[ -n "$FILES_TERM" ]] || {
        printf 'files: replace needs --term TERM\n' >&2
        return 2
      }
      files::replace_rows "$FILES_TERM"
      ;;
    locate)
      [[ -n "${FZF_QUERY:-}" ]] || return 0
      files::locate "$FZF_QUERY" |
        awk -v base="$FILES_BASE/" -v home="$HOME/" -v dim="$dim" -v rst="$rst" '
          { path = $0
            if (substr(path, 1, length(base)) == base) rel = substr(path, length(base) + 1)
            else if (substr(path, 1, length(home)) == home) rel = "~/" substr(path, length(home) + 1)
            else rel = path
            n = split(rel, parts, "/"); dir = substr(rel, 1, length(rel) - length(parts[n]))
            printf "%s\t%s%s%s%s\n", path, dim, dir, rst, parts[n] }'
      return 0
      ;;
    grep)
      local query="${FZF_QUERY:-}" rc
      files::grep_term query
      [[ -n "$query" ]] || return 0
      files::grep "$query" |
        awk -v base="$FILES_BASE/" -v dim="$dim" -v rst="$rst" '
          { i = index($0, ":"); path = substr($0, 1, i - 1); rest = substr($0, i + 1)
            j = index(rest, ":"); line = substr(rest, 1, j - 1); text = substr(rest, j + 1)
            rel = substr(path, 1, length(base)) == base ? substr(path, length(base) + 1) : path
            printf "%s\t%s\t%s%s:%s:%s %s\n", path, line, dim, rel, line, rst, text }'
      rc="${PIPESTATUS[0]}"
      # rg and grep exit 1 when nothing matches
      ((rc <= 1)) || return "$rc"
      return 0
      ;;
    *)
      printf 'files: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" files
  files::source "$@"
}
