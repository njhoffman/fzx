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

git::g() { command git -C "$GIT_TOP" "$@"; }

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

# status --porcelain -z: "XY path" entries; renames and copies are followed by the original path
git::source_status() {
  local entry xy path orig x y
  git::g status --porcelain=v1 -z --untracked-files=all |
    while IFS= read -r -d '' entry; do
      xy="${entry:0:2}" path="${entry:3}" orig=""
      [[ "$xy" == R* || "$xy" == C* ]] && IFS= read -r -d '' orig
      x="${xy:0:1}" y="${xy:1:1}"
      if [[ "$xy" == '??' ]]; then
        printf '%s/%s\t\e[31m??\e[0m %s\n' "$GIT_TOP" "$path" "$path"
      else
        printf '%s/%s\t\e[32m%s\e[31m%s\e[0m %s%s\n' "$GIT_TOP" "$path" "$x" "$y" "$path" \
          "${orig:+ $'\e[38;5;244m'<- $orig$'\e[0m'}"
      fi
    done
}

git::source_log() {
  local scope=()
  ((GIT_ALL)) && scope=(--all)
  [[ -n "$GIT_REV" ]] && scope+=("$GIT_REV")
  git::g log "${scope[@]}" --max-count="${FZX_GIT_LOG_LIMIT:-1000}" --date=short --color=always \
    --format=$'%H\t%C(yellow)%h%C(reset) %C(green)%ad%C(reset) %C(blue)%<(14,trunc)%an%C(reset)%C(auto)%d%C(reset) %s'
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
  git::g stash list --format=$'%gd\t\e[33m%gd\e[0m \e[38;5;244m%cr\e[0m %s'
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

[[ "${BASH_SOURCE[0]}" == "$0" ]] && git::source "$@"
