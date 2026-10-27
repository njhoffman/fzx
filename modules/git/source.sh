#!/usr/bin/env bash
# git source. Lines are "id<TAB>display" in every mode, so modes switch without restarting fzf:
#   status    id: absolute path        log       id: commit hash
#   branches  id: short ref name       tags      id: tag name
#   stash     id: stash@{n}            reflog    id: commit hash
#   worktrees id: the work tree's path commit    id: absolute path, then "<TAB>original path" for renames
# commit (hidden: opened by ctrl-o) lists the files the --rev commit changed against its first parent.
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

# FZX_SORT: recent (last commit first, default) or name; the sorted column is drawn in FZX_COLORS[sorted] too
git::source_branches() {
  local sort=-committerdate
  [[ "${FZX_SORT:-recent}" == name ]] && sort=refname
  # filtered on the full ref name: newer git shortens refs/remotes/origin/HEAD to just "origin"
  git::g for-each-ref --sort="$sort" refs/heads refs/remotes \
    --format=$'%(refname)\t%(refname:short)\t%(HEAD)\t%(upstream:track)\t%(committerdate:relative)\t%(subject)' |
    awk -F'\t' -v sort="${FZX_SORT:-recent}" -v hl="${FZX_COLORS[sorted]:-4}" '
      function cell(color, text, w, on) { return "\033[" color (on ? ";" hl : "") "m" text "\033[0m" sprintf("%" (w - length(text) > 0 ? w - length(text) : 0) "s", "") }
      $1 ~ /\/HEAD$/ { next }
      { cur = $3 == "*" ? "\033[32m*\033[0m" : " "
        clr = $1 ~ /^refs\/remotes\// ? "31" : "32"
        printf "%s\t%s %s \033[36m%-16s\033[0m %s %s\n", $2, cur, cell(clr, $2, 40, sort == "name"), $4,
          cell("38;5;244", $5, 16, sort == "recent"), $6 }'
}

git::source_stash() {
  git::g stash list --format=$'%gd\t\e[38;5;255m%gd\e[0m \e[38;5;244m%cr\e[0m %s'
}

git::source_tags() {
  # creatordate: the tagger's date for annotated tags, the commit's for lightweight ones
  git::g for-each-ref --sort=-creatordate refs/tags \
    --format=$'%(refname:short)\t%(creatordate:short)\t%(objecttype)\t%(subject)' |
    awk -F'\t' '{ kind = $3 == "tag" ? "" : "\033[38;5;244mlightweight\033[0m "
      printf "%s\t\033[1;38;5;117m%-24s\033[0m \033[32m%s\033[0m %s%s\n", $1, $1, $2, kind, $4 }'
}

# reflog of HEAD, or of --rev REF
git::source_reflog() {
  git::g reflog show --max-count="${FZX_GIT_LOG_LIMIT:-1000}" --color=always \
    --format=$'%H\t%C(white)%h%C(reset) %C(cyan)%<(12)%gd%C(reset) %C(green)%<(14,trunc)%cr%C(reset) %gs' \
    "${GIT_REV:-HEAD}" --
}

# worktree list --porcelain: records of "key value" lines, a blank line after each
git::source_worktrees() {
  git::g worktree list --porcelain |
    awk -v top="$GIT_TOP" -v home="$HOME" '
      function flush() {
        if (path == "") return
        shown = path; if (index(shown, home "/") == 1) shown = "~" substr(shown, length(home) + 1)
        cur = path == top ? "\033[32m*\033[0m" : " "
        ref = bare ? "\033[38;5;244mbare\033[0m" : branch != "" ? "\033[32m" branch "\033[0m" : "\033[38;5;244mdetached\033[0m"
        printf "%s\t%s %-50s %s \033[38;5;252m%s\033[0m%s\n", path, cur, shown, ref, substr(head, 1, 8), flags
        path = ""; branch = ""; head = ""; bare = 0; flags = ""
      }
      /^worktree / { flush(); path = substr($0, 10); next }
      /^HEAD / { head = $2; next }
      /^branch / { branch = $2; sub(/^refs\/heads\//, "", branch); next }
      /^bare$/ { bare = 1; next }
      /^(locked|prunable)/ { flags = flags " \033[38;5;203m" $1 "\033[0m"; next }
      END { flush() }'
}

# git::commit_base <var>: the --rev commit's first parent, or empty for a root commit
git::commit_base() {
  if git::g rev-parse --quiet --verify "$GIT_REV^1" > /dev/null 2>&1; then
    printf -v "$1" '%s' "$GIT_REV^1"
  else
    printf -v "$1" ''
  fi
}

# the files --rev changed, with their state like status: "A", "M", "D", "R" (renames name the original)
git::source_commit() {
  local base st path orig icon
  [[ -n "$GIT_REV" ]] || {
    printf 'git: the commit mode needs --rev\n' >&2
    return 2
  }
  git::g rev-parse --quiet --verify "$GIT_REV^{commit}" > /dev/null || {
    printf 'git: not a commit: %s\n' "$GIT_REV" >&2
    return 2
  }
  fzx::require icons
  git::commit_base base
  if [[ -n "$base" ]]; then
    git::g diff -M --name-status -z "$base" "$GIT_REV" --
  else
    git::g diff-tree --root -r -M --no-commit-id --name-status -z "$GIT_REV" --
  fi |
    while IFS= read -r -d '' st; do
      orig=""
      if [[ "$st" == R* || "$st" == C* ]]; then
        IFS= read -r -d '' orig
      fi
      IFS= read -r -d '' path
      st="${st:0:1}"
      [[ "$st" == T ]] && st=M
      git::status_icon "$st " icon
      printf '%s/%s\t\e[32m%s\e[0m %s%s%s\t%s\n' "$GIT_TOP" "$path" "$st" "$icon" "$path" \
        "${orig:+ $'\e[38;5;244m'<- $orig$'\e[0m'}" "$orig"
    done
}

# git::source [--all] [--rev REV] [DIR]
git::source() {
  git::args "$@" || return
  case "${FZX_MODE:-status}" in
    status) git::source_status ;;
    log) git::source_log ;;
    branches) git::source_branches ;;
    tags) git::source_tags ;;
    stash) git::source_stash ;;
    reflog) git::source_reflog ;;
    worktrees) git::source_worktrees ;;
    commit) git::source_commit ;;
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
