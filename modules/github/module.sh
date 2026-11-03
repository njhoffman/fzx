#!/usr/bin/env bash
# github: search GitHub's repositories and code, list your repositories and stars, browse a repository's
# files; open, clone, fetch, star or edit them. `fzx -m github[:code] [--query Q]`, `fzx -m github:mine
# [--owner NAME]`, `fzx -m github:starred`, `fzx -m github:repo --repo OWNER/REPO` (ctrl-o on a repository:
# its files, issues, pull requests and workflow runs), `fzx -m github:runs --repo OWNER/REPO`, `fzx -m
# github:tree --repo OWNER/REPO [--ref REF]` (ctrl-o on a code hit). In repos and code, typing does not filter: enter runs the search (a new
# query) or prints the row's URL (the same query); an empty query lists the mode's recent searches;
# ctrl-t filters the results with fzf instead.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# github::header <var>: the header of the current mode (and toggles), for the launch and for in-place
# switches (github::refresh)
github::header() {
  local _h="" _tkey=""
  case "${FZX_MODE:-repos}" in
    tree)
      _h="$GITHUB_REPO"
      [[ "$GITHUB_REF" != HEAD ]] && _h+=" @ ${GITHUB_REF:0:12}"
      ;;
    mine) _h="${GITHUB_OWNER:-your} repositories, last pushed first" ;;
    repo) github::hub_header _h ;;
    runs)
      local _repo=""
      github::scope_repo _repo 2> /dev/null || _repo="no repository"
      _h="workflow runs of $_repo, latest first"
      ;;
    starred) _h="your stars, last starred first" ;;
    notifications)
      fzx::comp_field toggle read key _tkey 2> /dev/null || _tkey=""
      _h="your unread notifications, latest first${_tkey:+ ($_tkey: read ones too)}"
      ;;
    issues | prs)
      # the list's scope, and the repository the everywhere toggle leaves (its key from the components table)
      local _scope _repo _what=issues
      [[ "$FZX_MODE" == prs ]] && _what="pull requests"
      github::issues_scope _scope
      FZX_TOGGLES="" github::issues_scope _repo
      fzx::comp_field toggle everywhere key _tkey 2> /dev/null || _tkey=""
      _h="$_what involving you, last updated first"
      if [[ -n "$_scope" ]]; then
        _h="$_what of $_scope, last updated first${_tkey:+ ($_tkey: involving you anywhere)}"
      elif [[ -n "$_repo" ]]; then
        _h+="${_tkey:+ ($_tkey: $_repo only)}"
      fi
      ;;
    *) github::search_header _h ;;
  esac
  printf -v "$1" '%s' "$_h"
}

# github::refresh: an in-place mode or toggle switch (lib/nav.sh): the new header, and fzf's search off in
# the search modes (typing is the query; a ctrl-t filter left on is dropped, as a restart dropped it) and
# on in the lists fzf filters
# shellcheck disable=SC2034  # FZX_REFRESH_*: read by lib/nav.sh
github::refresh() {
  github::args "${FZX_ARGS[@]}" 2> /dev/null || return 0
  github::header FZX_REFRESH_HEADER
  case "${FZX_MODE:-repos}" in
    repos | code)
      FZX_REFRESH_SEARCH=off
      fzx::state_set "github_filter_$FZX_MODE" ""
      ;;
    *) FZX_REFRESH_SEARCH=on ;;
  esac
}

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
    "--preview-window=right,55%,nohidden"
  )
  FZX_ACTION_ARGS="$a {+1}"
  github::header header
  case "${FZX_MODE:-repos}" in
    tree) FZX_OPTS+=("--header=$header" --scheme=path --tiebreak=index) ;;
    repo) FZX_OPTS+=("--header=$header" --no-sort) ;;
    repos | code) FZX_OPTS+=(--disabled "--header=$header") ;;
    *) FZX_OPTS+=("--header=$header") ;;
  esac
  if fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb transform enter "$a" '{1}' '{2}' '{3}' '{4}')" \
      "search for the query, or print the row's URL; in a repository's hub, open the row's list"
    fzx::bind "${FZX_KEYS[github.into]}" "transform:$(fzx::cb transform into "$a" '{1}' '{2}' '{3}' '{4}')" \
      "a repository: its files, issues, pull requests and runs; a code hit: the files at its commit"
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
