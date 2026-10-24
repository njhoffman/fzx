#!/usr/bin/env bash
# youtube preview: a video's title, channel, duration, views and description from the search row (no
# request), or for a recent search what enter does and its cached results.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# youtube::preview <url|search|error> <title|query|message> [channel duration views description]
youtube::preview() {
  local kind="${1:-}" text="${2:-}" dim=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" bold=$'\e[1m' rst=$'\e[0m'
  local width="${FZF_PREVIEW_COLUMNS:-80}" file
  case "$kind" in
    search)
      printf '%senter%s searches again for %s%s%s\n' "$bold" "$rst" "$bold" "$text" "$rst"
      youtube::search_file "$text" file
      [[ -f "$file" ]] || return 0
      printf '\n%scached results:%s\n' "$dim" "$rst"
      cut -f2 -- "$file"
      ;;
    error) printf '%s\n' "$text" ;;
    http*)
      printf '%s%s%s\n\n' "$bold" "$text" "$rst"
      [[ -n "${3:-}" ]] && printf '%schannel%s   %s\n' "$dim" "$rst" "$3"
      printf '%sduration%s  %s\n' "$dim" "$rst" "${4:-live}"
      [[ "${5:-}" =~ ^[0-9]+$ ]] && printf "%sviews%s     %'d\n" "$dim" "$rst" "$5"
      printf '%surl%s       %s\n' "$dim" "$rst" "$kind"
      [[ -n "${6:-}" ]] && printf '\n%s\n' "$6" | fold -s -w "$width"
      ;;
    *) return 0 ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && youtube::preview "$@"
