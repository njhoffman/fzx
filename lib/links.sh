#!/usr/bin/env bash
# links: a directory of symbolic links named after each ghq repository (FZX_REPOS_LINKS_DIR, ~/git when it
# exists: ~/git/fzx -> ~/ghq/github.com/njhoffman/fzx), kept by the repos module's links action, the shell's
# `repos` and every clone fzx makes. A name two repositories share keeps the link it has (the first wins).

# fzx::link_repo <repository path> [dry]: link one repository. Prints what it did ("linked NAME") or would
# do ("would link NAME"), nothing when the link is already there; a name taken by another repository or by
# something that is not a link is reported and returns 3. A dead link of the same name is replaced.
fzx::link_repo() {
  local path="${1%/}" dry="${2:-}" dir="${FZX_REPOS_LINKS_DIR:-}" name link target
  [[ -n "$dir" && -n "$path" ]] || return 0
  name="${path##*/}"
  link="$dir/$name"
  if [[ -L "$link" ]]; then
    target="$(readlink -- "$link")"
    target="${target%/}"
    [[ "$target" == "$path" ]] && return 0
    if [[ -e "$link" ]]; then
      printf 'taken: %s -> %s (not %s)\n' "${link/#$HOME/\~}" "${target/#$HOME/\~}" "${path/#$HOME/\~}"
      return 3
    fi
  elif [[ -e "$link" ]]; then
    printf 'taken: %s is not a link (not %s)\n' "${link/#$HOME/\~}" "${path/#$HOME/\~}"
    return 3
  fi
  if [[ -n "$dry" ]]; then
    printf 'would link %s -> %s\n' "$name" "${path/#$HOME/\~}"
    return 0
  fi
  mkdir -p -- "$dir" && ln -sfn -- "$path" "$link" || return
  printf 'linked %s -> %s\n' "$name" "${path/#$HOME/\~}"
}

# fzx::link_repos [--dry-run]: link every ghq repository and remove the dead links in the directory, then a
# summary line (dry: what would change, nothing changes)
fzx::link_repos() {
  local dry="" dir="${FZX_REPOS_LINKS_DIR:-}" path out linked=0 taken=0 dead=0 link
  [[ "${1:-}" == --dry-run || "${1:-}" == -n ]] && dry=1
  if [[ -z "$dir" ]]; then
    printf 'fzx: FZX_REPOS_LINKS_DIR is empty: no links to keep\n' >&2
    return 2
  fi
  command -v ghq > /dev/null || { printf 'fzx: links need ghq\n' >&2; return 2; }
  local -A claimed=()
  while IFS= read -r path; do
    # a name an earlier repository of this run took (what a dry run cannot see on disk)
    if [[ -n "${claimed[${path##*/}]:-}" && "${claimed[${path##*/}]}" != "$path" ]]; then
      printf 'taken: %s by %s (not %s)\n' "${path##*/}" "${claimed[${path##*/}]/#$HOME/\~}" "${path/#$HOME/\~}"
      taken=$((taken + 1))
      continue
    fi
    claimed[${path##*/}]="$path"
    out="$(fzx::link_repo "$path" "$dry")"
    case $? in
      0) [[ -n "$out" ]] && { printf '%s\n' "$out"; linked=$((linked + 1)); } ;;
      3) printf '%s\n' "$out"; taken=$((taken + 1)) ;;
      *) return 1 ;;
    esac
  done < <(command ghq list -p)
  if [[ -d "$dir" ]]; then
    while IFS= read -r -d '' link; do
      dead=$((dead + 1))
      if [[ -n "$dry" ]]; then printf 'would remove dead %s\n' "${link##*/}"; else rm -f -- "$link" && printf 'removed dead %s\n' "${link##*/}"; fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -xtype l -print0)
  fi
  printf '%s%d linked, %d dead removed, %d names taken (in %s)\n' "${dry:+dry run: }" "$linked" "$dead" "$taken" "${dir/#$HOME/\~}"
}
