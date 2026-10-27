#!/usr/bin/env bash
# git actions (bound with execute, in the foreground) and the ctrl-o transform.
# Each action applies to one mode and does nothing in the others, so one binding serves every mode.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# show a failure until a key is pressed; execute would otherwise wipe it at once
git::_report() {
  local rc="$1"
  ((rc == 0)) && return 0
  printf '\n\e[31mfailed (exit %s)\e[0m, press a key ' "$rc"
  IFS= read -rsn1 < /dev/tty || :
  return "$rc"
}

# git::ask <prompt> <var>: a line from the terminal (from stdin when that is a pipe or a file)
git::ask() {
  local fd
  if [[ -p /dev/stdin || -f /dev/stdin ]]; then
    IFS= read -r "$2" || :
  elif { exec {fd}< /dev/tty; } 2> /dev/null; then
    IFS= read -r -p "$1" -u "$fd" "$2" || :
    exec {fd}<&-
  else
    printf -v "$2" ''
  fi
}

# git::ordered <oldest|newest> <commits...>: the commits, deduplicated, in history order whatever order
# they were selected in (cherry-pick wants the oldest first, revert the newest); topological, since
# commit dates tie within a second. The walk stops once every commit has been seen.
git::ordered() {
  local order="$1" h
  local -A want=()
  shift
  for h; do
    h="$(git::g rev-parse --verify --quiet "$h^{commit}")" && want[$h]=1
  done
  ((${#want[@]})) || return 0
  git::g rev-list --topo-order "${!want[@]}" |
    awk -v n="${#want[@]}" 'NR == FNR { w[$1] = 1; next } $1 in w { print; if (++seen == n) exit }' \
      <(printf '%s\n' "${!want[@]}") - |
    if [[ "$order" == oldest ]]; then tac; else command cat; fi
}

# switch in commit mode: the files as they were in --rev, staged; files with local changes, or not in
# that commit, are skipped
git::restore_at() {
  local f rel rc=0 ok=()
  for f; do
    rel="${f#"$GIT_TOP"/}"
    if [[ -n "$(git::g status --porcelain -- "$rel")" ]]; then
      printf 'skipped, it has local changes: %s\n' "$rel" >&2
      rc=1
    elif ! git::g cat-file -e "$GIT_REV:$rel" 2> /dev/null; then
      printf 'skipped, not in %s: %s\n' "$GIT_REV" "$rel" >&2
      rc=1
    else
      ok+=("$rel")
    fi
  done
  if ((${#ok[@]})); then
    git::g restore --source="$GIT_REV" --staged --worktree -- "${ok[@]}" || rc=$?
  fi
  return "$rc"
}

# the selected paths, anchored to the work tree's root, appended to its .gitignore unless already there
git::ignore() {
  local f line file="$GIT_TOP/.gitignore"
  for f; do
    line="/${f#"$GIT_TOP"/}"
    grep -qxF -- "$line" "$file" 2> /dev/null && continue
    [[ -s "$file" && -n "$(tail -c 1 "$file")" ]] && printf '\n' >> "$file"
    printf '%s\n' "$line" >> "$file"
    git::g ls-files --error-unmatch -- "$f" > /dev/null 2>&1 &&
      printf 'note: %s is tracked; ignoring it does not untrack it (git rm --cached)\n' "$line" >&2
  done
  return 0
}

# a new branch at the selection, switched to; an empty name cancels
git::new_branch() {
  local name
  git::ask "new branch at $1: " name
  [[ -n "$name" ]] || return 0
  git::g switch -c "$name" "$1"
}

# the destructive verbs run only with FZX_GIT_DESTRUCTIVE=1 (their rows are not even listed without it)
git::destructive() {
  [[ "${FZX_GIT_DESTRUCTIVE:-0}" == 1 ]] && return 0
  printf 'git: %s is destructive: set FZX_GIT_DESTRUCTIVE=1 to allow it\n' "$1" >&2
  return 1
}

# drop in status: tracked files lose their unstaged changes (the staged ones stay), untracked ones are
# deleted
git::discard() {
  local f tracked=() untracked=() rc=0
  for f; do
    if git::g ls-files --error-unmatch -- "$f" > /dev/null 2>&1; then tracked+=("$f"); else untracked+=("$f"); fi
  done
  if ((${#tracked[@]})); then
    git::g restore --worktree -- "${tracked[@]}" || rc=$?
  fi
  if ((${#untracked[@]})); then
    git::g clean -f -d -- "${untracked[@]}" || rc=$?
  fi
  return "$rc"
}

# drop in branches: local branches, force-deleted (asked first); remote-tracking ones are left alone
git::delete_branches() {
  local b rc=0
  for b; do
    if git::g show-ref --verify --quiet "refs/heads/$b"; then
      git::g branch -D -- "$b" || rc=$?
    else
      printf 'skipped, not a local branch: %s (remote branches are not deleted here)\n' "$b" >&2
      rc=1
    fi
  done
  return "$rc"
}

# drop in stash: highest index first, so the others keep their names until their turn
git::drop_stashes() {
  local s rc=0
  while IFS= read -r s; do
    git::g stash drop "$s" || rc=$?
  done < <(printf '%s\n' "$@" | sort -t'{' -k2 -rn)
  return "$rc"
}

# git::rewritable <commit>: the commit is in HEAD's history and no merge follows it (rebase would
# flatten the merge)
git::rewritable() {
  if ! git::g merge-base --is-ancestor "$1" HEAD 2> /dev/null; then
    printf 'git: %s is not in the current branch'"'"'s history\n' "$1" >&2
    return 1
  fi
  if [[ -n "$(git::g rev-list --merges "$1..HEAD")" ]]; then
    printf 'git: merges follow %s; rewrite them by hand (git rebase --rebase-merges)\n' "$1" >&2
    return 1
  fi
}

# git::rebase_from <commit> <args...>: rebase -i from the commit's parent (--root for the first commit),
# stashing local changes around it
git::rebase_from() {
  local c="$1"
  shift
  if git::g rev-parse --quiet --verify "$c^" > /dev/null; then
    git::g -c core.abbrev=40 rebase -i --autostash "$@" "$c^"
  else
    git::g -c core.abbrev=40 rebase -i --autostash "$@" --root
  fi
}

# git::rewrite <fixup|squash|reword|rebase> <commit>
git::rewrite() {
  local verb="$1" c
  c="$(git::g rev-parse --verify --quiet "$2^{commit}")" || {
    printf 'git: not a commit: %s\n' "$2" >&2
    return 1
  }
  git::rewritable "$c" || return
  case "$verb" in
    fixup)
      if git::g diff --cached --quiet; then
        printf 'git: nothing staged to fold into %s\n' "${c:0:8}" >&2
        return 1
      fi
      git::g commit --quiet --fixup="$c" || return
      GIT_SEQUENCE_EDITOR=: git::rebase_from "$c" --autosquash
      ;;
    reword) GIT_SEQUENCE_EDITOR="sed -i 's/^pick $c /reword $c /'" git::rebase_from "$c" ;;
    squash)
      if ! git::g rev-parse --quiet --verify "$c^" > /dev/null; then
        printf 'git: %s is the first commit: nothing to squash it into\n' "${c:0:8}" >&2
        return 1
      fi
      GIT_SEQUENCE_EDITOR="sed -i 's/^pick $c /squash $c /'" git::rebase_from "$(git::g rev-parse "$c^")"
      ;;
    rebase) git::g rebase -i --autostash "$c" ;;
  esac
}

# amend rewrites the last commit: refused when a remote branch holds it, unless FZX_GIT_DESTRUCTIVE=1
git::amend() {
  if [[ "${FZX_GIT_DESTRUCTIVE:-0}" != 1 && -n "$(git::g branch -r --contains HEAD 2> /dev/null)" ]]; then
    printf 'git: HEAD is on a remote branch; amending would rewrite published history (FZX_GIT_DESTRUCTIVE=1 allows it)\n' >&2
    return 1
  fi
  git::g commit --amend
}

# git::action <name> [module args...] -- <ids...>: the verbs of components.tsv. commit, amend and fetch
# need no selection; the others act on it, in the modes their description names, and do nothing elsewhere.
git::action() {
  local action="${1:-}" refs=()
  shift
  git::split "$@" || return
  set -- "${GIT_IDS[@]}"
  case "$action" in
    commit) git::g commit; git::_report $?; return ;;
    amend) git::amend; git::_report $?; return ;;
    fetch) git::g fetch --all --prune; git::_report $?; return ;;
    stage | unstage | patch | edit | switch | pick | revert | branch | stash | ignore) ;;
    drop | fixup | squash | reword | rebase) git::destructive "$action" || { git::_report 1; return; } ;;
    *)
      printf 'git: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  (($#)) || return 0
  case "$action:${FZX_MODE:-status}" in
    stage:status) git::g add -- "$@" ;;
    unstage:status) git::g restore --staged -- "$@" ;;
    patch:status) git::g add -p -- "$@" ;;
    edit:status | edit:commit) "${EDITOR:-vi}" -- "$@" ;;
    switch:branches)
      if git::g show-ref --verify --quiet "refs/heads/$1"; then
        git::g switch -- "$1"
      else
        git::g switch --track -- "$1"
      fi
      ;;
    switch:log | switch:reflog | switch:tags) git::g switch --detach "$1" ;;
    switch:commit) git::restore_at "$@" ;;
    pick:log | pick:reflog)
      mapfile -t refs < <(git::ordered oldest "$@")
      git::g cherry-pick "${refs[@]}"
      ;;
    pick:stash) git::g stash apply "$1" ;;
    revert:log | revert:reflog)
      mapfile -t refs < <(git::ordered newest "$@")
      git::g revert --no-edit "${refs[@]}"
      ;;
    branch:branches | branch:tags | branch:log | branch:reflog) git::new_branch "$1" ;;
    stash:status) git::g stash push --include-untracked -- "$@" ;;
    stash:stash) git::g stash pop "$1" ;;
    ignore:status) git::ignore "$@" ;;
    drop:status) git::discard "$@" ;;
    drop:branches) git::delete_branches "$@" ;;
    drop:stash) git::drop_stashes "$@" ;;
    fixup:log | squash:log | reword:log | rebase:log) git::rewrite "$action" "$1" ;;
    *) return 0 ;;
  esac
  git::_report $?
}

# git::transform <into|view> [module args...] -- <id>
#   into: ctrl-o. Branches and tags open their log, log, reflog and stash entries the files the commit
#         changed, a work tree its status; each as a child session
#   view: alt-v. Status and commit previews switch between the diff and the blame
git::transform() {
  local name="${1:-}" view=""
  shift
  case "$name" in
    into)
      git::split "$@" || return
      local id="${GIT_IDS[0]:-}"
      [[ -n "$id" ]] || return 0
      fzx::require nav
      case "${FZX_MODE:-}" in
        branches | tags) fzx::nav goto git:log --rev "$id" "$GIT_TOP" ;;
        log | reflog | stash) fzx::nav goto git:commit --rev "$id" "$GIT_TOP" ;;
        worktrees) fzx::nav goto git:status "$id" ;;
        *) return 0 ;;
      esac
      ;;
    view)
      [[ "${FZX_MODE:-}" == status || "${FZX_MODE:-}" == commit ]] || return 0
      fzx::state_get git_view view 2> /dev/null || view=""
      if [[ "$view" == blame ]]; then view="diff"; else view="blame"; fi
      fzx::state_set git_view "$view"
      printf 'change-preview-label( %s )+refresh-preview' "$view"
      ;;
    *)
      printf 'git: unknown transform: %s\n' "$name" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && git::action "$@"
