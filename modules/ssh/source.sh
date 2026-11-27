#!/usr/bin/env bash
# ssh source: "target<TAB>host<TAB>display" a row, target [user@]host as ssh takes it, from ~/.ssh/config's
# Host entries (Include files too; patterns left out), known_hosts' unhashed entries, and the ssh, scp,
# rsync, mosh and sftp commands zsh-histdb recorded. A target is one row; its sources, last use and count
# are merged. Sort from $FZX_SORT: recent (last use first; never used last, by name) or name.

# ssh::_config_files: ~/.ssh/config (FZX_SSH_CONFIG) and the files its Include lines name, one per line
ssh::_config_files() {
  local conf="${FZX_SSH_CONFIG:-$HOME/.ssh/config}" inc f
  [[ -f "$conf" ]] || return 0
  printf '%s\n' "$conf"
  while read -r inc; do
    [[ "$inc" == /* || "$inc" == "~"* ]] || inc="${conf%/*}/$inc"
    inc="${inc/#\~/$HOME}"
    # shellcheck disable=SC2086  # Include takes globs
    for f in $inc; do [[ -f "$f" ]] && printf '%s\n' "$f"; done
  done < <(awk 'tolower($1) == "include" { for (i = 2; i <= NF; i++) print $i }' "$conf")
}

# ssh::from_config: "host<TAB>config<TAB><TAB>" a Host name (no * ? or !)
ssh::from_config() {
  local files=()
  mapfile -t files < <(ssh::_config_files)
  ((${#files[@]})) || return 0
  awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/) print $i "\tconfig\t\t" }' "${files[@]}"
}

# ssh::from_known_hosts: "host<TAB>known<TAB><TAB>" an unhashed known_hosts name ([host]:port as host)
ssh::from_known_hosts() {
  local f="${FZX_SSH_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
  [[ -f "$f" ]] || return 0
  awk '$1 !~ /^(\||#|@)/ && NF >= 3 {
      n = split($1, names, ",")
      for (i = 1; i <= n; i++) { h = names[i]; sub(/^\[/, "", h); sub(/\]:[0-9]+$/, "", h); if (h !~ /^[0-9.:]+$/) print h "\tknown\t\t" }
    }' "$f"
}

# ssh::from_history: "target<TAB>history<TAB>last<TAB>count" from histdb (FZX_SSH_HISTDB): the host of each ssh,
# mosh and sftp command (its first word that is not an option or an option's value) and of scp and rsync's
# HOST:PATH words, with the user given (user@host, -l user); a command's newlines and tabs read as blanks
ssh::from_history() {
  local db="${FZX_SSH_HISTDB:-${HISTDB_FILE:-$HOME/.histdb/zsh-history.db}}"
  [[ -f "$db" ]] && command -v sqlite3 > /dev/null || return 0
  command sqlite3 -readonly -separator $'\t' "$db" "
    select replace(replace(c.argv, char(10), ' '), char(9), ' '), max(h.start_time), count(*)
    from history h join commands c on c.id = h.command_id
    where c.argv glob 'ssh *' or c.argv glob 'scp *' or c.argv glob 'rsync *' or c.argv glob 'mosh *'
      or c.argv glob 'sftp *'
    group by c.argv" 2> /dev/null | awk -F'\t' '
    function add(t, last, n) { if (t == "" || t ~ /^[-.\/~]/ || t ~ /[$`'"'"'"*]/) return; if (last > when[t]) when[t] = last; count[t] += n }
    {
      cmd = $1; last = $2; n = $3
      sub(/[;&|].*/, "", cmd)
      w = split(cmd, a, /[ \t]+/)
      if (a[1] == "scp" || a[1] == "rsync") {
        for (i = 2; i <= w; i++) if (a[i] !~ /^-/ && a[i] ~ /^[^\/:]+:/) { t = a[i]; sub(/:.*/, "", t); add(t, last, n) }
        next
      }
      user = ""
      for (i = 2; i <= w; i++) {
        if (a[i] ~ /^-[bcDEeFIiJLlmOopQRSWw]$/) { if (a[i] == "-l") user = a[i + 1]; i++; continue }
        if (a[i] ~ /^-/) continue
        t = a[i]; if (user != "" && t !~ /@/) t = user "@" t
        add(t, last, n); break
      }
    }
    END { for (t in when) print t "\thistory\t" when[t] "\t" count[t] }'
}

# ssh::hosts: every source's rows merged by target: "target<TAB>host<TAB>sources<TAB>last<TAB>count"
ssh::hosts() {
  { ssh::from_config; ssh::from_known_hosts; ssh::from_history; } | awk -F'\t' '
    {
      t = $1
      if (!(t in src)) order[++n] = t
      if (index("," src[t] ",", "," $2 ",") == 0) src[t] = src[t] (src[t] != "" ? "," : "") $2
      if ($3 > last[t]) last[t] = $3
      count[t] += $4
    }
    END {
      for (i = 1; i <= n; i++) {
        t = order[i]; h = t; sub(/^[^@]*@/, "", h)
        print t "\t" h "\t" src[t] "\t" last[t] + 0 "\t" count[t] + 0
      }
    }'
}

# ssh::_age <epoch> <now> <var>: "3m", "5h", "2d", "7w", "4mo", "2y" ago, "-" for never
ssh::_age() {
  local _d=$(($2 - $1))
  if (($1 == 0)); then printf -v "$3" '%s' "-"
  elif ((_d < 3600)); then printf -v "$3" '%sm' $((_d / 60))
  elif ((_d < 86400)); then printf -v "$3" '%sh' $((_d / 3600))
  elif ((_d < 86400 * 14)); then printf -v "$3" '%sd' $((_d / 86400))
  elif ((_d < 86400 * 60)); then printf -v "$3" '%sw' $((_d / 604800))
  elif ((_d < 86400 * 365)); then printf -v "$3" '%smo' $((_d / 2592000))
  else printf -v "$3" '%sy' $((_d / 31536000)); fi
}

# ssh::source (FZX_SSH_NOW: the time the ages count from, for tests)
ssh::source() {
  local t h src last n age now="${FZX_SSH_NOW:-${EPOCHSECONDS:-$(date +%s)}}" c dim=$'\e['"${FZX_COLORS[ssh_dim]:-38;5;244}m" r=$'\e[0m'
  local hc=$'\e['"${FZX_COLORS[ssh_host]:-38;5;117}m"
  [[ -n "${NO_COLOR:+x}" ]] && dim="" r="" hc=""
  # the header row, when the view has one (lib/header.sh): the columns named, the sorted one marked
  fzx::require header
  fzx::header_print 2 "$([[ "${FZX_SORT:-recent}" == name ]] && echo HOST || echo LAST)" HOST 40 0 LAST 5 1 USES 4 1 "" 0 0 FROM 0 0
  ssh::hosts | if [[ "${FZX_SORT:-recent}" == name ]]; then
    LC_ALL=C sort -t$'\t' -k2,2 -k1,1
  else
    LC_ALL=C sort -t$'\t' -k4,4nr -k2,2 -k1,1
  fi | while IFS=$'\t' read -r t h src last n; do
    ssh::_age "$last" "$now" age
    c=""
    ((last)) || c="$dim"
    printf '%s\t%s\t%s%-40s%s %s%5s %4s  %s%s\n' "$t" "$h" "$c$hc" "$t" "$r" "$dim" "$age" "$( ((n)) && printf '%sx' "$n")" "$src" "$r"
  done
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" ssh
  ssh::source "$@"
}
