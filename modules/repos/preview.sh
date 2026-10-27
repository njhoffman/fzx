#!/usr/bin/env bash
# repos preview: where the repository is, its branch against the upstream, the remote, its changes, the
# recent commits and its open TODO.md items (highest priority first)

# repos::preview <dir>
repos::preview() {
  local dir="${1:-}" D=$'\e[2m' R=$'\e[0m' C=$'\e[36m' remote todo
  [[ -d "$dir" ]] || { printf 'no such repository: %s\n' "$dir"; return 1; }
  # headings with their icons (lib/icons.sh)
  local l_dir l_remote l_todo
  fzx::require icons
  fzx::icon_label folder "${dir/#$HOME/\~}" 1 l_dir
  printf '%s\n' "$l_dir"
  if remote="$(git -C "$dir" remote get-url origin 2> /dev/null)"; then
    fzx::icon_label remote "$remote" 2 l_remote
    printf '%s\n' "$l_remote"
  fi
  printf '\n'
  # -sb: the branch line with ahead/behind, then the changes; a huge checkout gets two seconds
  timeout 2 git -C "$dir" -c color.status=always status -sb 2> /dev/null | head -n 15 ||
    printf '%s(status took too long)%s\n' "$D" "$R"
  printf '\n'
  # cool colors for tags and the decoration parentheses (git's defaults are yellow), as the git module
  git -C "$dir" -c "color.decorate.tag=bold 117" -c color.diff.commit=252 log --color=always --graph --format='%C(white)%h%C(reset) %s %C(dim)%cr%C(reset)%C(auto)%d' -n 10 2> /dev/null
  todo="$dir/TODO.md"
  if [[ -f "$todo" ]] && grep -q '^- \[ \]' "$todo"; then
    fzx::icon_label todo TODO 1 l_todo
    printf '\n%s %s(%s open)%s\n' "$l_todo" "$D" "$(grep -c '^- \[ \]' "$todo")" "$R"
    grep -n '^- \[ \]' "$todo" | sed -E 's/^([0-9]+):- \[ \] \*\*([^*]+)\*\*.*\((p[123])\).*/\3\t\2\t\1/' |
      grep -E '^p[123]'$'\t' | sort -s -k1,1 | head -n 8 |
      awk -F'\t' -v c="$C" -v d="$D" -v r="$R" '{ p = ($1 == "p1") ? "\033[31m" : ($1 == "p2") ? "\033[38;5;255m" : d; printf "  %s%s%s %s %s:%s%s\n", p, toupper($1), r, $2, d, $3, r }'
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  repos::preview "$@"
}
