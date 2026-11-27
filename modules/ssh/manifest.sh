#!/usr/bin/env bash
# ssh menu entry, where ssh is installed and a host is known

ssh::manifest() { fzx::entry ssh "SSH hosts: connect, send, fetch"; }

ssh::applicable() {
  command -v ssh > /dev/null || return 1
  # shellcheck source=./source.sh
  source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :
  [[ -n "$(ssh::hosts | head -n 1)" ]]
}

# ssh::summary: how many hosts, and the last one used
ssh::summary() {
  # shellcheck source=./source.sh
  source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :
  ssh::hosts | LC_ALL=C sort -t$'\t' -k4,4nr | awk -F'\t' "$FZX_AWK_PLURAL"'
    { n++ } NR == 1 && $4 > 0 { last = $1 }
    END { printf "%s%s\n", plural(n, "host"), (last != "" ? ", last: " last : "") }'
}

# the summaries are cached once for every directory: they describe the machine, not the directory
ssh::summary_global() { :; }
