#!/usr/bin/env bash
# workspaces source: `workspace list` (FZX_WORKSPACE_CMD), KEY NAME TYPE ROOT STATE tab-separated, as
# "key<TAB>state<TAB>type<TAB>root<TAB>display", in its order (predefined, the family's open sessions,
# recent directories newest first). KEY is a session name, or the root of a closed recent directory; TYPE
# is claude, git, generic (a layouts/NN-TYPE.sh), a predefined session's name (its layouts/NAME.sh) or
# session (made by hand). Modes: all, open, recent (closed directories), predefined.

# workspaces::cmd: the workspace command, or fails when it is not there
workspaces::cmd() {
  local cmd="${FZX_WORKSPACE_CMD:-$HOME/.config/tmux/scripts/workspace}"
  [[ -x "$cmd" ]] || return 1
  printf '%s' "$cmd"
}

# workspaces::family: the session family's prefix (tmux's @send_session_family, default main)
workspaces::family() {
  local f=""
  [[ -n "${TMUX:-}" ]] && f="$(command tmux show-options -gqv @send_session_family 2> /dev/null)"
  printf '%s' "${f:-main}"
}

# workspaces::type_color <type> <var>: the escape for a type's icon and name
workspaces::type_color() {
  local -n _tc_out="$2"
  local _tc_c="${FZX_COLORS[workspaces_$1]:-${FZX_COLORS[workspaces_predefined]:-38;5;176}}"
  _tc_out=$'\e['"${_tc_c}m"
  [[ -n "${NO_COLOR:+x}" ]] && _tc_out=""
}

workspaces::source() {
  local cmd family on off r d types="" t ic c
  cmd="$(workspaces::cmd)" || { printf 'workspaces: no workspace command (FZX_WORKSPACE_CMD)\n' >&2; return 2; }
  family="$(workspaces::family)"
  fzx::require icons
  fzx::icon running on
  fzx::icon stopped off
  r=$'\e[0m' d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m"
  local con=$'\e['"${FZX_COLORS[workspaces_open]:-38;5;114}m"
  [[ -n "${NO_COLOR:+x}" ]] && r="" d="" con=""
  # type<US>icon<US>escape per known type, for awk
  for t in claude git generic session predefined; do
    ic="${FZX_WORKSPACES_ICONS[$t]:-}"
    [[ "${FZX_ICONS:-nerd}" == nerd ]] || ic=""
    workspaces::type_color "$t" c
    types+="$t"$'\x1f'"$ic"$'\x1f'"$c"$'\n'
  done
  "$cmd" list | LC_ALL=C command awk -F'\t' -v mode="${FZX_MODE:-all}" -v fam="$family-" -v home="$HOME" \
    -v on="${on:-*}" -v off="${off:-.}" -v con="$con" -v d="$d" -v r="$r" -v types="$types" '
    BEGIN {
      n = split(types, tl, "\n")
      for (i = 1; i <= n; i++) if (tl[i] != "") { split(tl[i], f, "\x1f"); icon[f[1]] = f[2]; col[f[1]] = f[3] }
    }
    NF < 5 { next }
    {
      key = $1; state = $5; pre = (key !~ /^\// && $3 == key)
      if (mode == "open" && state != "open") next
      if (mode == "recent" && !(state == "closed" && key ~ /^\//)) next
      if (mode == "predefined" && !pre) next
      name = $2; if (index(name, fam) == 1 && length(name) > length(fam)) name = substr(name, length(fam) + 1)
      root = $4; if (root == home) root = "~"; else if (index(root, home "/") == 1) root = "~" substr(root, length(home) + 1)
      k = pre ? "predefined" : (($3 in icon) ? $3 : "predefined")
      c = ++rows; K[c] = key; S[c] = state; T[c] = $3; R[c] = $4; N[c] = name; P[c] = root; Y[c] = k
      if (length(name) > wn) wn = length(name)
      if (length($3) > wt) wt = length($3)
    }
    END {
      for (i = 1; i <= rows; i++) {
        mark = (S[i] == "open") ? con on r : d off r
        ic = icon[Y[i]]; ty = (ic == "" ? "" : ic " ") T[i]
        printf "%s\t%s\t%s\t%s\t%s %-*s  %s%s%s%*s  %s%s%s\n", K[i], S[i], T[i], R[i], mark, wn, N[i],
          col[Y[i]], ty, r, wt - length(T[i]), "", d, P[i], r
      }
    }'
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" workspaces
  workspaces::source "$@"
}
