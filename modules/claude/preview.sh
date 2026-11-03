#!/usr/bin/env bash
# claude preview: the project's directory, kind and version, git state and last commit, its open TODO.md
# items (highest priority first) and its recent Claude Code sessions (title or last prompt, age). Drawn from
# the cached row and cheap reads; `claude-projects show` (the full card, with test totals and CHANGELOG.md's
# Unreleased entries) is the claude-card action, since it takes seconds.

# claude::session_dir <dir>: where Claude Code keeps the transcripts of sessions started in <dir> (the path
# with every character other than letters, digits and - turned into -)
claude::session_dir() {
  local dir="${1//[^A-Za-z0-9-]/-}"
  printf '%s/projects/%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$dir"
}

# claude::session_line <transcript>: "title<TAB>last prompt" from its custom-title and last-prompt records
claude::session_line() {
  command -v jq > /dev/null || return 0
  grep -E '^\{"type":"(custom-title|last-prompt)"' -- "$1" 2> /dev/null |
    jq -rs '[(map(select(.type == "custom-title"))[-1].customTitle // ""),
             (map(select(.type == "last-prompt"))[-1].lastPrompt // "" | gsub("\\s+"; " "))] | @tsv' 2> /dev/null
}

# claude::preview <dir>
claude::preview() {
  local dir="${1:-}" D=$'\e[2m' R=$'\e[0m' row cache
  [[ -d "$dir" ]] || { printf 'no such directory: %s\n' "$dir"; return 1; }
  local name kind version p1 overdue sessions src
  # the scan's cache (source.sh, which a preview callback does not load)
  cache="$FZX_CACHE_DIR/claude/projects"
  # split on \x1f: read folds runs of tabs (IFS whitespace), which would shift past empty fields
  row="$(awk -F'\t' -v OFS=$'\x1f' -v d="$dir" '$1 == d { $1 = $1; print; exit }' "$cache" 2> /dev/null)"
  IFS=$'\x1f' read -r _ name kind version _ _ _ _ _ p1 overdue _ sessions src <<< "$row"
  local c_text=$'\e['"${FZX_COLORS[claude_name]:-1;38;5;111}m" c_kind
  case "$kind" in
    git) c_kind=$'\e['"${FZX_COLORS[claude_mode_git]:-38;5;110}m" ;;
    dotbare) c_kind=$'\e['"${FZX_COLORS[claude_mode_dotbare]:-38;5;140}m" ;;
    plain) c_kind=$'\e['"${FZX_COLORS[claude_mode_plain]:-38;5;180}m" ;;
    *) c_kind="$D" ;;
  esac
  local l_dir l_remote l_todo l_clock remote
  fzx::require icons
  fzx::icon_label folder "${dir/#$HOME/\~}" 1 l_dir
  printf '%s\n' "$l_dir"
  printf '  %s%s%s%s  %s%s%s' "$c_text" "${name:-${dir##*/}}" "$R" "$([[ "$src" == own ]] || printf '%s (sessions only)%s' "$D" "$R")" \
    "$c_kind" "${kind:-?}" "$R"
  [[ -n "$version" ]] && printf '  %s%s%s' "$D" "$version" "$R"
  printf '\n'
  if [[ "$kind" == git ]] || git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
    if remote="$(git -C "$dir" remote get-url origin 2> /dev/null)"; then
      fzx::icon_label remote "$remote" 2 l_remote
      printf '%s\n' "$l_remote"
    fi
    printf '\n'
    timeout 2 git -C "$dir" -c color.status=always status -sb 2> /dev/null | head -n 10 ||
      printf '%s(status took too long)%s\n' "$D" "$R"
    git -C "$dir" -c "color.decorate.tag=bold 117" -c color.diff.commit=252 log --color=always \
      --format='%C(white)%h%C(reset) %s %C(dim)%cr%C(reset)%C(auto)%d' -n 5 2> /dev/null
  fi
  local todo="$dir/TODO.md"
  if [[ -f "$todo" ]] && grep -q '^- \[ \]' "$todo"; then
    fzx::icon_label todo TODO 1 l_todo
    printf '\n%s %s(%s open' "$l_todo" "$D" "$(grep -c '^- \[ \]' "$todo")"
    ((${p1:-0})) && printf ', %s P1' "$p1"
    ((${overdue:-0})) && printf ', %s overdue' "$overdue"
    printf ')%s\n' "$R"
    grep -n '^- \[ \]' "$todo" | sed -E 's/^([0-9]+):- \[ \] \*\*([^*]+)\*\*.*\((p[123])\).*/\3\t\2\t\1/' |
      grep -E '^p[123]'$'\t' | sort -s -k1,1 | head -n 6 |
      awk -F'\t' -v d="$D" -v r="$R" -v c1=$'\e['"${FZX_COLORS[claude_p1]:-38;5;203}m" '
        { p = ($1 == "p1") ? c1 : ($1 == "p2") ? "\033[38;5;255m" : d; printf "  %s%s%s %s %s:%s%s\n", p, toupper($1), r, $2, d, $3, r }'
  fi
  # the newest transcripts of sessions started in the project's own directory
  local sdir f t title prompt
  sdir="$(claude::session_dir "$dir")"
  fzx::icon_label clock "Sessions" 1 l_clock
  printf '\n%s %s(%s)%s\n' "$l_clock" "$D" "${sessions:-0}" "$R"
  if [[ -d "$sdir" ]]; then
    while IFS= read -r f; do
      IFS=$'\t' read -r title prompt <<< "$(claude::session_line "$f")"
      t="$(date -d "@$(stat -c %Y -- "$f")" '+%F %H:%M')"
      printf '  %s%s%s  %s\n' "$D" "$t" "$R" "${title:-${prompt:0:80}}"
      [[ -n "$title" && -n "$prompt" ]] && printf '  %s%s%s\n' "$D" "${prompt:0:100}" "$R"
    done < <(find "$sdir" -maxdepth 1 -name '*.jsonl' -type f -printf '%T@\t%p\n' 2> /dev/null | sort -rn | head -n 5 | cut -f2-)
  elif ((${sessions:-0})); then
    printf '  %s(started in subdirectories)%s\n' "$D" "$R"
  else
    printf '  %snone%s\n' "$D" "$R"
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  claude::preview "$@"
}
