#!/usr/bin/env bash
# ssh preview: what ssh would use for the target (ssh -G: no connection), whether known_hosts has its key
# (ssh-keygen -F reads hashed entries too), and the last commands that named it

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# ssh::preview <target> [host]
ssh::preview() {
  local t="${1:-}" h="${2:-${1#*@}}" b=$'\e[1m' dim=$'\e['"${FZX_COLORS[ssh_dim]:-38;5;244}m" ok=$'\e['"${FZX_COLORS[ssh_known]:-38;5;114}m" r=$'\e[0m'
  local db="${FZX_SSH_HISTDB:-${HISTDB_FILE:-$HOME/.histdb/zsh-history.db}}" q
  [[ -n "${NO_COLOR:+x}" ]] && b="" dim="" ok="" r=""
  [[ -n "$t" ]] || return 0
  printf '%s%s%s\n\n' "$b" "$t" "$r"
  command ssh -G "$t" 2> /dev/null | awk -v d="$dim" -v r="$r" '
    $1 ~ /^(hostname|user|port|identityfile|proxyjump|proxycommand|forwardagent)$/ && !seen[$1]++ { printf "%s%-14s%s %s\n", d, $1, r, substr($0, length($1) + 2) }'
  if command ssh-keygen -F "$h" -f "${FZX_SSH_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}" > /dev/null 2>&1; then
    printf '%s%-14s%s %sin known_hosts%s\n' "$dim" known "$r" "$ok" "$r"
  else
    printf '%s%-14s%s not in known_hosts (ssh asks to trust its key)\n' "$dim" known "$r"
  fi
  [[ -f "$db" ]] && command -v sqlite3 > /dev/null || return 0
  q="${h//\'/\'\'}"
  printf '\n%slast commands%s\n' "$b" "$r"
  # shellcheck disable=SC2119  # no fields: the whole text
  command sqlite3 -readonly -separator $'\t' "$db" "
    select datetime(max(h.start_time), 'unixepoch', 'localtime'), replace(replace(c.argv, char(10), ' '), char(9), ' ')
    from history h join commands c on c.id = h.command_id
    where (c.argv glob 'ssh *' or c.argv glob 'scp *' or c.argv glob 'rsync *' or c.argv glob 'mosh *' or c.argv glob 'sftp *')
      and c.argv like '%$q%'
    group by c.argv order by max(h.start_time) desc limit ${FZX_SSH_PREVIEW_COMMANDS:-8}" 2> /dev/null | fzx::glyphs_plain |
    while IFS=$'\t' read -r when cmd; do printf '  %s%s%s  %s\n' "$dim" "${when% *}" "$r" "$cmd"; done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" ssh
  ssh::preview "$@"
}
