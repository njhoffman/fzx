#!/usr/bin/env bash
# repos preview: where the repository is, its branch against the upstream, the remote, its changes, the
# recent commits and its open TODO.md items (highest priority first)

# repos::preview <dir>
repos::preview() {
  local dir="${1:-}" B=$'\e[1m' D=$'\e[2m' R=$'\e[0m' C=$'\e[36m' remote todo
  [[ -d "$dir" ]] || { printf 'no such repository: %s\n' "$dir"; return 1; }
  printf '%s%s%s\n' "$B" "${dir/#$HOME/\~}" "$R"
  remote="$(git -C "$dir" remote get-url origin 2> /dev/null)" && printf '%s%s%s\n' "$D" "$remote" "$R"
  printf '\n'
  # -sb: the branch line with ahead/behind, then the changes; a huge checkout gets two seconds
  timeout 2 git -C "$dir" -c color.status=always status -sb 2> /dev/null | head -n 15 ||
    printf '%s(status took too long)%s\n' "$D" "$R"
  printf '\n'
  git -C "$dir" log --color=always --graph --format='%C(yellow)%h%C(reset) %s %C(dim)%cr%C(reset)%C(auto)%d' -n 10 2> /dev/null
  todo="$dir/TODO.md"
  if [[ -f "$todo" ]] && grep -q '^- \[ \]' "$todo"; then
    printf '\n%sTODO%s %s(%s open)%s\n' "$B" "$R" "$D" "$(grep -c '^- \[ \]' "$todo")" "$R"
    grep -n '^- \[ \]' "$todo" | sed -E 's/^([0-9]+):- \[ \] \*\*([^*]+)\*\*.*\((p[123])\).*/\3\t\2\t\1/' |
      grep -E '^p[123]'$'\t' | sort -s -k1,1 | head -n 8 |
      awk -F'\t' -v c="$C" -v d="$D" -v r="$R" '{ p = ($1 == "p1") ? "\033[31m" : ($1 == "p2") ? "\033[33m" : d; printf "  %s%s%s %s %s:%s%s\n", p, toupper($1), r, $2, d, $3, r }'
  fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && repos::preview "$@"
