#!/usr/bin/env bash
# workspaces preview: what `workspace type KEY` says (name, type, root, state); an open session's windows
# and panes with each pane's command; a closed one's layout (its file's header comment); for claude and git
# types the root's branch and changes, for claude its open TODO.md items

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# workspaces::layout_file <key> <type> <var>: the layout a closed workspace would be built from
workspaces::layout_file() {
  local -n _lf_out="$3"
  local _lf_cmd _lf_dir _lf_f
  _lf_out=""
  _lf_cmd="$(workspaces::cmd)" || return 1
  if [[ "$1" != /* ]] && _lf_f="$("$_lf_cmd" predefined "$1" 2> /dev/null)" && [[ -f "$_lf_f" ]]; then
    _lf_out="$_lf_f"
    return 0
  fi
  _lf_cmd="$(readlink -f "$_lf_cmd")"
  _lf_dir="${WORKSPACE_LAYOUTS:-${_lf_cmd%/scripts/*}/layouts}"
  for _lf_f in "$_lf_dir"/[0-9][0-9]-"$2".sh; do
    [[ -f "$_lf_f" ]] && { _lf_out="$_lf_f"; return 0; }
  done
  return 1
}

# workspaces::panes <session>: the session's windows, each with its panes' commands and directories
workspaces::panes() {
  command tmux list-panes -s -t "=$1" \
    -F $'#{window_index}\t#{window_name}\t#{pane_index}\t#{pane_current_command}\t#{pane_current_path}\t#{window_active}#{pane_active}' 2> /dev/null |
    command awk -F'\t' -v b="$WP_B" -v d="$WP_D" -v r="$WP_R" -v home="$HOME" '
      {
        if ($1 != w) { w = $1; printf "%s%s: %s%s%s\n", (NR > 1 ? "\n" : ""), $1, b, $2, r }
        p = $5; if (p == home) p = "~"; else if (index(p, home "/") == 1) p = "~" substr(p, length(home) + 1)
        printf "  %s%s %s  %s%s%s\n", ($6 == "11" ? "*" : " "), $3, $4, d, p, r
      }'
}

# workspaces::repo <root> <type>: the branch and changes of a git root; a claude project's open TODO items
workspaces::repo() {
  local root="$1" branch changes n
  [[ -d "$root" ]] || return 0
  if branch="$(command git -C "$root" branch --show-current 2> /dev/null)"; then
    changes="$(command git -C "$root" status --porcelain 2> /dev/null | command wc -l)"
    printf '\n%sbranch%s  %s%s\n' "$WP_D" "$WP_R" "${branch:-(detached)}" \
      "$( ((changes)) && printf ', %d changed' "$changes")"
    command git -C "$root" status --short 2> /dev/null | command head -n 8 | command sed 's/^/  /'
  fi
  if [[ "$2" == claude && -f "$root/TODO.md" ]]; then
    n="$(command grep -c '^- \[ \]' "$root/TODO.md")"
    printf '\n%stodo%s    %d open in TODO.md\n' "$WP_D" "$WP_R" "$n"
  fi
}

# workspaces::preview <key> <state> <type> <root>
workspaces::preview() {
  local key="${1:-}" state="${2:-}" type="${3:-}" root="${4:-}" cmd line name file
  [[ -n "$key" ]] || return 0
  declare -g WP_B=$'\e[1m' WP_D=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" WP_R=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && WP_B="" WP_D="" WP_R=""
  cmd="$(workspaces::cmd)" || { printf 'no workspace command\n'; return 0; }
  name="$key"
  if line="$("$cmd" type "$key" 2> /dev/null)" && [[ -n "$line" ]]; then
    IFS=$'\t' read -r name type root state <<< "$line"
  fi
  printf '%s%s%s\n' "$WP_B" "$name" "$WP_R"
  printf '%stype%s    %s\n%sroot%s    %s\n%sstate%s   %s\n' "$WP_D" "$WP_R" "$type" "$WP_D" "$WP_R" "${root/#"$HOME"/\~}" \
    "$WP_D" "$WP_R" "$state"
  if [[ "$state" == open ]]; then
    printf '\n'
    workspaces::panes "$name"
  elif workspaces::layout_file "$key" "$type" file; then
    printf '\n%slayout%s  %s\n' "$WP_D" "$WP_R" "${file/#"$HOME"/\~}"
    # the header comment: what it builds (shellcheck directives left out)
    command awk '/^#/ { if ($0 ~ /shellcheck/) next; sub(/^# ?/, ""); print "  " $0; next } { exit }' "$file"
  fi
  case "$type" in
    claude | git) workspaces::repo "$root" "$type" ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" workspaces
  workspaces::preview "$@"
}
