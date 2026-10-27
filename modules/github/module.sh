#!/usr/bin/env bash
# github: search GitHub's repositories and code, list your repositories and stars, browse a repository's
# files; open, clone, fetch, star or edit them. `fzx -m github[:code] [--query Q]`, `fzx -m github:mine
# [--owner NAME]`, `fzx -m github:starred`, `fzx -m github:tree --repo OWNER/REPO [--ref REF]` (ctrl-o on
# a repository or a code hit). In repos and code, typing does not filter: enter runs the search (a new
# query) or prints the row's URL (the same query); an empty query lists the mode's recent searches;
# ctrl-t filters the results with fzf instead.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS: read by lib/actions.sh
github::opts() {
  github::args "${FZX_ARGS[@]}" || return
  local a="" header
  ((${#FZX_ARGS[@]})) && printf -v a '%q ' "${FZX_ARGS[@]}"
  a+="--"
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=6
    --accept-nth=1
    --tiebreak=index
    --multi
    --preview "$(fzx::cb preview '{1}' '{2}' '{3}' '{4}' '{5}')"
    "--preview-window=right,55%,wrap,nohidden"
  )
  FZX_ACTION_ARGS="$a {+1}"
  case "${FZX_MODE:-repos}" in
    tree)
      header="$GITHUB_REPO"
      [[ "$GITHUB_REF" != HEAD ]] && header+=" @ ${GITHUB_REF:0:12}"
      FZX_OPTS+=("--header=$header" --scheme=path --tiebreak=index)
      ;;
    mine) FZX_OPTS+=("--header=${GITHUB_OWNER:-your} repositories, last pushed first") ;;
    starred) FZX_OPTS+=("--header=your stars, last starred first") ;;
    *)
      github::search_header header
      FZX_OPTS+=(--disabled "--header=$header")
      ;;
  esac
  if fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb transform enter "$a" '{1}' '{2}' '{3}')" \
      "search for the query, or print the row's URL"
    fzx::bind "${FZX_KEYS[github.into]}" "transform:$(fzx::cb transform into "$a" '{1}' '{2}' '{3}')" \
      "browse the repository's files"
    fzx::bind "${FZX_KEYS[github.narrow]}" "transform:$(fzx::cb transform narrow "$a" '{1}' '{2}' '{3}')" \
      "code: search again in this repository only; repos, mine, starred: search this repository's code"
    fzx::bind "${FZX_KEYS[github.filter]}" "transform:$(fzx::cb transform filter "$a" '{1}' '{2}' '{3}')" \
      "repos, code: filter the results with fzf instead of searching, and back"
  elif [[ "${FZX_MODE:-repos}" == repos || "${FZX_MODE:-repos}" == code ]]; then
    # standalone has no transform callback: search once typing pauses (GitHub allows 30 searches a minute)
    FZX_OPTS+=(--bind "change:reload:sleep 1; $(fzx::cb source)")
  fi
}

fzx::module_main "$@"
