#!/usr/bin/env bash
# git source. Lines are "id<TAB>display" in every mode, so modes switch without restarting fzf:
#   status    id: absolute path        log     id: commit hash
#   branches  id: short ref name       stash   id: stash@{n}
# Mode from $FZX_MODE (default status).

# git::args [--all] [--rev REV] [DIR]: GIT_TOP (work tree root), GIT_ALL, GIT_REV
git::args() {
  local dir=""
  GIT_ALL=0 GIT_REV=""
  while (($#)); do
    case "$1" in
      --all) GIT_ALL=1 ;;
      --rev)
        [[ -n "${2:-}" ]] || {
          printf 'git: --rev needs a revision\n' >&2
          return 2
        }
        GIT_REV="$2"
        shift
        ;;
      -*)
        printf 'git: unknown option: %s\n' "$1" >&2
        return 2
        ;;
      *)
        [[ -z "$dir" ]] || {
          printf 'git: at most one directory, got: %s %s\n' "$dir" "$1" >&2
          return 2
        }
        dir="$1"
        ;;
    esac
    shift
  done
  GIT_TOP="$(command git -C "${dir:-.}" rev-parse --show-toplevel 2> /dev/null)" || {
    printf 'git: not inside a git work tree: %s\n' "${dir:-$PWD}" >&2
    return 2
  }
}

# git::g <args...>: git in the work tree, with FZX_GIT_COLOR_CONFIG's color settings over the user's
git::g() {
  local cfg=() kv
  for kv in "${FZX_GIT_COLOR_CONFIG[@]}"; do cfg+=(-c "$kv"); done
  command git -C "$GIT_TOP" "${cfg[@]}" "$@"
}

# git::split [module args...] -- [ids...]: callbacks get the module args explicitly (they are not in the
# environment, and a standalone run has no session to read them from); ids into GIT_IDS
git::split() {
  local args=()
  while (($#)) && [[ "$1" != -- ]]; do
    args+=("$1")
    shift
  done
  [[ "${1:-}" == -- ]] && shift
  # shellcheck disable=SC2034  # read by the caller (preview, actions)
  GIT_IDS=("$@")
  git::args "${args[@]}"
}

# git::status_icon <XY> <var>: the icon for the entry's state, colored by kind (conflict, deleted, renamed,
# added, modified, untracked), with a space after it; empty with FZX_ICONS=none
git::status_icon() {
  local _kind _clr _glyph
  case "$1" in
    '??') _kind=untracked _clr='38;5;244' ;;
    U? | ?U | AA | DD) _kind=conflict _clr='1;38;5;203' ;;
    *D*) _kind=deleted _clr='38;5;203' ;;
    R* | C*) _kind=renamed _clr='38;5;147' ;;
    A*) _kind=added _clr='38;5;114' ;;
    *) _kind=modified _clr='38;5;81' ;;
  esac
  fzx::icon "$_kind" _glyph
  if [[ -n "$_glyph" ]]; then
    printf -v "$2" '\e[%sm%s\e[0m ' "$_clr" "$_glyph"
  else
    printf -v "$2" ''
  fi
}

# status --porcelain -z: "XY path" entries; renames and copies are followed by the original path
git::source_status() {
  local entry xy path orig x y icon
  fzx::require icons
  git::g status --porcelain=v1 -z --untracked-files=all |
    while IFS= read -r -d '' entry; do
      xy="${entry:0:2}" path="${entry:3}" orig=""
      [[ "$xy" == R* || "$xy" == C* ]] && IFS= read -r -d '' orig
      x="${xy:0:1}" y="${xy:1:1}"
      git::status_icon "$xy" icon
      if [[ "$xy" == '??' ]]; then
        printf '%s/%s\t\e[31m??\e[0m %s%s\n' "$GIT_TOP" "$path" "$icon" "$path"
      else
        printf '%s/%s\t\e[32m%s\e[31m%s\e[0m %s%s%s\n' "$GIT_TOP" "$path" "$x" "$y" "$icon" "$path" \
          "${orig:+ $'\e[38;5;244m'<- $orig$'\e[0m'}"
      fi
    done
}

git::source_log() {
  local scope=()
  ((GIT_ALL)) && scope=(--all)
  [[ -n "$GIT_REV" ]] && scope+=("$GIT_REV")
  git::g log "${scope[@]}" --max-count="${FZX_GIT_LOG_LIMIT:-1000}" --date=short --color=always \
    --format=$'%H\t%C(white)%h%C(reset) %C(green)%ad%C(reset) %C(blue)%<(14,trunc)%an%C(reset)%C(auto)%d%C(reset) %s'
}

git::source_branches() {
  # filtered on the full ref name: newer git shortens refs/remotes/origin/HEAD to just "origin"
  git::g for-each-ref --sort=-committerdate refs/heads refs/remotes \
    --format=$'%(refname)\t%(refname:short)\t%(HEAD)\t%(upstream:track)\t%(committerdate:relative)\t%(subject)' |
    awk -F'\t' '
      $1 ~ /\/HEAD$/ { next }
      { cur = $3 == "*" ? "\033[32m*\033[0m" : " "
        clr = $1 ~ /^refs\/remotes\// ? "\033[31m" : "\033[32m"
        printf "%s\t%s %s%-40s\033[0m \033[36m%-16s\033[0m \033[38;5;244m%-16s\033[0m %s\n", $2, cur, clr, $2, $4, $5, $6 }'
}

git::source_stash() {
  git::g stash list --format=$'%gd\t\e[38;5;255m%gd\e[0m \e[38;5;244m%cr\e[0m %s'
}

# git::source [--all] [--rev REV] [DIR]
git::source() {
  git::args "$@" || return
  case "${FZX_MODE:-status}" in
    status) git::source_status ;;
    log) git::source_log ;;
    branches) git::source_branches ;;
    stash) git::source_stash ;;
    *)
      printf 'git: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  git::source "$@"
}
