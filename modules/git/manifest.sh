#!/usr/bin/env bash
# git menu entries, shown only inside a work tree; summaries describe the repository here

git::manifest() {
  fzx::entry git "Changed files: stage, unstage, edit"
  fzx::entry git:log "Commits on the current branch"
  fzx::entry git:log "Commits on all branches" --all
  fzx::entry git:branches "Local and remote branches, newest first"
  fzx::entry git:stash "Stashes"
}

git::applicable() {
  command git rev-parse --is-inside-work-tree > /dev/null 2>&1 || return 1
  [[ "$1" != git:stash ]] || command git rev-parse --quiet --verify refs/stash > /dev/null
}

git::summary() {
  local target="$1" n counts ahead behind upstream
  shift
  case "$target" in
    git)
      command git status --porcelain=v1 | awk '
        /^\?\?/ { u++; next } { if (substr($0, 1, 1) != " ") s++; if (substr($0, 2, 1) != " ") m++ }
        END { printf "%d staged, %d modified, %d untracked\n", s, m, u }'
      ;;
    git:log)
      if [[ "${1:-}" == --all ]]; then
        n="$(command git rev-list --all --count)"
        printf '%s commits on all refs\n' "$n"
        return
      fi
      n="$(command git rev-list --count HEAD)" || return 1
      if upstream="$(command git rev-parse --abbrev-ref '@{upstream}' 2> /dev/null)" &&
        counts="$(command git rev-list --left-right --count 'HEAD...@{upstream}' 2> /dev/null)"; then
        read -r ahead behind <<< "$counts"
        printf '%s commits, %s ahead / %s behind %s\n' "$n" "$ahead" "$behind" "$upstream"
      else
        printf '%s commits, no upstream\n' "$n"
      fi
      ;;
    git:branches)
      printf '%s local, %s remote, on %s\n' \
        "$(command git for-each-ref refs/heads --format=x | wc -l)" \
        "$(command git for-each-ref refs/remotes --format='%(refname)' | grep -vc '/HEAD$')" \
        "$(command git symbolic-ref --quiet --short HEAD || echo detached)"
      ;;
    git:stash) printf '%s stashes\n' "$(command git stash list | wc -l)" ;;
    *) return 0 ;;
  esac
}
