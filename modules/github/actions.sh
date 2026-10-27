#!/usr/bin/env bash
# github actions on the selected rows' URLs, the enter and ctrl-o transforms, and fetch, which also runs on
# its own: `actions.sh fetch [--dest DIR] URL...` (the shell's ghfetch).

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# show a failure until a key is pressed; execute would otherwise wipe it at once
github::_report() {
  local rc="$1"
  ((rc == 0)) && return 0
  printf '\n\e[31mfailed (exit %s)\e[0m, press a key ' "$rc"
  IFS= read -rsn1 < /dev/tty || :
  return "$rc"
}

# github::_pause: after output worth reading (what was cloned or fetched), wait for a key under fzf
github::_pause() {
  [[ -n "${FZX_SESSION_DIR:-}" ]] || return 0
  printf '\npress a key '
  IFS= read -rsn1 < /dev/tty || :
}

# github::uri <text>: each "/"-separated part percent-encoded
github::uri() {
  command jq -rn --arg p "$1" '$p | split("/") | map(@uri) | join("/")'
}

# github::download <owner/name> <ref> <path> <target>: one file's contents (the contents API, raw)
github::download() {
  local tmp="$4.$BASHPID"
  mkdir -p -- "${4%/*}" || return
  if github::api "repos/$1/contents/$(github::uri "$3")?ref=$(github::uri "$2")" > "$tmp"; then
    mv -f -- "$tmp" "$4"
  else
    rm -f -- "$tmp"
    return 1
  fi
}

# github::clone <owner/name>: through ghq (its root and layout), printing where it is
github::clone() {
  if ! command -v ghq > /dev/null; then
    printf 'github: clone needs ghq\n' >&2
    return 1
  fi
  command ghq get -- "github.com/$1" || return
  command ghq list -p -e -- "github.com/$1" 2> /dev/null
}

# github::fetch [--dest DIR] [--] <url...>: a repository is cloned (ghq); a file is written into DIR, a
# directory as DIR/<its name>/... (the repository's name for its top). Existing files are kept. Each fetch
# is logged in $FZX_STATE_DIR/github/fetched.
github::fetch() {
  local dest="${FZX_GITHUB_FETCH_DIR:-$PWD}" url rc=0 sha tree target name n total path blob
  while (($#)); do
    case "$1" in
      --dest) dest="${2:-}" && shift 2 ;;
      --) shift; break ;;
      -*) printf 'github: unknown option: %s\n' "$1" >&2; return 2 ;;
      *) break ;;
    esac
  done
  (($#)) || { printf 'usage: ghfetch URL... [--dest DIR]\n' >&2; return 2; }
  dest="${dest/#\~/$HOME}"
  dest="$(realpath -m -- "$dest")"
  for url in "$@"; do
    if ! github::parse_url "$url"; then
      printf 'github: not a GitHub URL: %s\n' "$url" >&2
      rc=1
      continue
    fi
    if [[ "$GH_KIND" == repo ]]; then
      github::clone "$GH_REPO" || rc=1
      continue
    fi
    github::split_ref "$GH_REPO" "$GH_REST"
    if [[ "$GH_KIND" == blob ]]; then
      target="$dest/${GH_PATH##*/}"
      if [[ -e "$target" ]]; then
        printf 'exists, kept: %s\n' "$target"
        continue
      elif github::download "$GH_REPO" "$GH_REF" "$GH_PATH" "$target"; then
        printf '%s\n' "$target"
      else
        printf 'github: cannot fetch %s\n' "$url" >&2
        rc=1
        continue
      fi
    else
      # a directory: its blobs from the commit's tree, each by its sha
      if ! github::resolve "$GH_REPO" "$GH_REF" sha || ! github::tree_file "$GH_REPO" "$sha" tree; then
        printf 'github: cannot list %s\n' "$url" >&2
        rc=1
        continue
      fi
      name="${GH_PATH##*/}"
      [[ -n "$name" ]] || name="${GH_REPO#*/}"
      n=0
      total="$(command jq --arg p "${GH_PATH:+$GH_PATH/}" '[.tree[] | select(.type == "blob" and (.path | startswith($p)))] | length' -- "$tree")"
      while IFS=$'\t' read -r path blob; do
        n=$((n + 1))
        target="$dest/$name/${path#"${GH_PATH:+$GH_PATH/}"}"
        if [[ -e "$target" ]]; then
          printf '%d/%d exists, kept: %s\n' "$n" "$total" "$target"
          continue
        fi
        if mkdir -p -- "${target%/*}" && github::blob "$GH_REPO" "$blob" blob && command cp -- "$blob" "$target"; then
          printf '%d/%d %s\n' "$n" "$total" "$target"
        else
          printf 'github: cannot fetch %s\n' "$path" >&2
          rc=1
        fi
      done < <(command jq -r --arg p "${GH_PATH:+$GH_PATH/}" '.tree[] | select(.type == "blob" and (.path | startswith($p))) |
        [.path, .sha] | join("\t")' -- "$tree")
      target="$dest/$name"
    fi
    mkdir -p -- "$FZX_STATE_DIR/github" &&
      printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$url" "$target" >> "$FZX_STATE_DIR/github/fetched"
  done
  return "$rc"
}

# github::local <url> <var>: a read-only local copy of a file (by its ref: a sha in the module's own URLs)
github::local() {
  local _file
  github::parse_url "$1" && [[ "$GH_KIND" == blob ]] || return 1
  github::split_ref "$GH_REPO" "$GH_REST"
  _file="$FZX_CACHE_DIR/github/files/$GH_REPO/$GH_REF/$GH_PATH"
  if [[ ! -f "$_file" ]]; then
    github::download "$GH_REPO" "$GH_REF" "$GH_PATH" "$_file" || return 1
    chmod a-w -- "$_file"
  fi
  printf -v "$2" '%s' "$_file"
}

# github::open <url...>: in the browser
github::open() {
  local u
  for u in "$@"; do
    if command -v xdg-open > /dev/null; then xdg-open "$u"; else open "$u"; fi > /dev/null 2>&1
  done
}

# github::action <browser|clone|fetch|edit|web> [module args...] -- <urls...>: rows without a URL (recent
# searches, errors) are skipped
github::action() {
  local action="${1:-}" urls=() u repos=() file type=repositories
  shift
  if [[ "$action" == fetch && " $* " != *" -- "* ]]; then
    github::fetch "$@"
    return
  fi
  # module args (the tree's --repo) are not acted on
  while (($#)) && [[ "$1" != -- ]]; do shift; done
  (($#)) && shift
  for u in "$@"; do
    [[ "$u" == https://* ]] && urls+=("$u")
  done
  case "$action" in
    web)
      [[ "${FZX_MODE:-repos}" == code ]] && type=code
      [[ -n "${FZF_QUERY:-}" ]] || return 0
      github::open "https://github.com/search?type=$type&q=$(command jq -rn --arg q "$FZF_QUERY" '$q | @uri')"
      return
      ;;
  esac
  ((${#urls[@]})) || return 0
  case "$action" in
    browser) github::open "${urls[@]}" ;;
    clone)
      for u in "${urls[@]}"; do
        github::parse_url "$u" && [[ " ${repos[*]} " != *" $GH_REPO "* ]] && repos+=("$GH_REPO")
      done
      for u in "${repos[@]}"; do
        github::clone "$u" || { github::_report $?; return; }
      done
      github::_pause
      ;;
    fetch)
      github::fetch -- "${urls[@]}"
      github::_report $? && github::_pause
      ;;
    star)
      # starred: unstar; elsewhere star. The stars list is fetched again afterwards
      local method=PUT verb=starred
      [[ "${FZX_MODE:-repos}" == starred ]] && method=DELETE verb=unstarred
      for u in "${urls[@]}"; do
        github::parse_url "$u" && [[ " ${repos[*]} " != *" $GH_REPO "* ]] && repos+=("$GH_REPO")
      done
      for u in "${repos[@]}"; do
        command gh api -X "$method" "user/starred/$u" --silent || { github::_report $?; return; }
        printf '%s %s\n' "$verb" "$u"
      done
      local list
      github::list_file starred list
      rm -f -- "$list"
      ;;
    fork)
      for u in "${urls[@]}"; do
        github::parse_url "$u" && [[ " ${repos[*]} " != *" $GH_REPO "* ]] && repos+=("$GH_REPO")
      done
      for u in "${repos[@]}"; do
        command gh repo fork "$u" --clone=false || { github::_report $?; return; }
      done
      github::_pause
      ;;
    settings)
      github::parse_url "${urls[0]}" && github::open "https://github.com/$GH_REPO/settings"
      ;;
    edit)
      if ! github::local "${urls[0]}" file; then
        printf 'github: edit opens a file (code and tree rows)\n'
        github::_report 1
        return
      fi
      "${EDITOR:-vi}" -- "$file"
      ;;
    *)
      printf 'github: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

# github::_arg <action> <text> [var]: action(text) with a delimiter pair fzf accepts that text does not
# close, into var when given, else printed
github::_arg() {
  local _d _out
  for _d in '()' '[]' '{}' '<>' '~~' '!!' '@@' '##' '$$' '%%' '^^' '&&' '**' ';;' '//' '||'; do
    [[ "$2" == *"${_d:1:1}"* ]] && continue
    _out="$1${_d:0:1}$2${_d:1:1}"
    if [[ -n "${3:-}" ]]; then printf -v "$3" '%s' "$_out"; else printf '%s' "$_out"; fi
    return 0
  done
  return 1
}

# github::transform <enter|into|narrow|filter> [module args...] -- <first field> <kind> <repo>
#   enter:  searches when the query is new (or reruns the recent search the cursor is on, if nothing new
#           was typed; a cleared query lists the recent searches again), otherwise accepts the row (prints
#           its URL). While filtering, and in mine, starred and tree, it accepts
#   into:   ctrl-o. A repository or a code hit opens the repository's files (tree) as a child session; a
#           code hit at the commit GitHub found it in
#   narrow: alt-p. In code, the search again within the repository under the cursor (its repo: qualifier
#           replacing any other); elsewhere, code mode searching that repository
#   filter: ctrl-t. In repos and code, fzf filters the results instead of the query searching, and back
#           (the searched query returns). Filtering is per mode; switching modes in place keeps fzf's
#           search as it was, so switch back first
github::transform() {
  local name="${1:-}" mode="${FZX_MODE:-repos}" query last="" reload q text kind repo sha filter="" h
  shift
  while (($#)) && [[ "$1" != -- ]]; do shift; done
  (($#)) && shift
  text="${1:-}" kind="${2:-}" repo="${3:-}"
  case "$name" in
    enter)
      case "$kind" in search | error) ;; *) [[ "$mode" =~ ^(tree|mine|starred)$ ]] && { printf 'accept'; return 0; } ;; esac
      github::trim "${FZF_QUERY:-}" query
      fzx::state_get "github_query_$mode" last || last=""
      fzx::state_get "github_filter_$mode" filter 2> /dev/null || filter=""
      fzx::require opts
      fzx::reload_action "$(fzx::cb source)" reload
      if [[ -n "$filter" ]]; then
        # filtering: a row is accepted; a recent search is searched again, back in search mode
        if [[ "$kind" == search && -n "$text" ]]; then
          fzx::state_set "github_filter_$mode" ""
          github::search_header h
          github::_arg change-query "$text" q || return 0
          printf 'disable-search+%s+%s+%s' "$q" "$(github::_arg change-header "$h")" "$reload"
        elif [[ "$kind" == repo || "$kind" == code ]]; then
          printf 'accept'
        fi
      elif [[ "$kind" == search && "$query" == "$last" && -n "$text" ]]; then
        github::_arg change-query "$text" q || return 0
        printf '%s+%s' "$q" "$reload"
      elif [[ "$query" != "$last" ]]; then
        # a new search, or back to the recent searches once the query is cleared
        printf '%s' "$reload"
      elif [[ "$kind" == repo || "$kind" == code ]]; then
        printf 'accept'
      fi
      ;;
    into)
      fzx::require nav
      case "$kind" in
        repo) fzx::nav goto github:tree --repo "$repo" ;;
        code)
          sha="${text#*/blob/}" sha="${sha%%/*}"
          fzx::nav goto github:tree --repo "$repo" --ref "$sha"
          ;;
        *) return 0 ;;
      esac
      ;;
    narrow)
      [[ "$kind" == repo || "$kind" == code ]] || return 0
      fzx::require opts
      if [[ "$mode" == code ]]; then
        github::trim "${FZF_QUERY:-}" query
        fzx::state_set github_filter_code ""
        # any repo: qualifier gives way to this one
        q="$(printf '%s' "$query" | sed -E 's/(^| )repo:[^ ]+//g; s/  +/ /g; s/^ +//')"
        q="${q:+$q }repo:$repo"
        fzx::reload_action "$(fzx::cb source)" reload
        github::search_header h
        github::_arg change-query "$q" q || return 0
        printf 'disable-search+%s+%s+%s' "$q" "$(github::_arg change-header "$h")" "$reload"
      else
        # code mode, searching the repository: in place from repos (the reload sees the new query), through
        # a restart from mine and starred (which keeps FZF_QUERY as the query)
        q="repo:$repo "
        export FZF_QUERY="$q"
        fzx::require nav
        github::_arg change-query "$q" text || return 0
        # through a file, not $(...): nav_mode records its stats in this shell; nothing (a session without
        # code mode) leaves the query alone
        local out="" file="$FZX_SESSION_DIR/narrow.$BASHPID"
        fzx::nav_mode code > "$file"
        out="$(< "$file")"
        rm -f -- "$file"
        [[ -n "$out" ]] && printf '%s+%s' "$text" "$out"
      fi
      ;;
    filter)
      [[ "$mode" == repos || "$mode" == code ]] || return 0
      fzx::state_get "github_filter_$mode" filter 2> /dev/null || filter=""
      fzx::state_get "github_query_$mode" last || last=""
      if [[ -z "$filter" ]]; then
        fzx::state_set "github_filter_$mode" 1
        printf 'enable-search+change-query()+%s' \
          "$(github::_arg change-header "filtering the results of: ${last:-recent searches} (${FZX_KEYS[github.filter]:-ctrl-t} searches again)")"
      else
        fzx::state_set "github_filter_$mode" ""
        github::search_header h
        github::_arg change-query "$last" q || q="change-query()"
        # fzf keeps the filtered matches when search is turned off: the list again, from the session's cache
        fzx::require opts
        fzx::reload_action "$(fzx::cb load)" reload
        printf 'disable-search+%s+%s+%s' "$q" "$(github::_arg change-header "$h")" "$reload"
      fi
      ;;
    *)
      printf 'github: unknown transform: %s\n' "$name" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" github
  github::action "$@"
}
