#!/usr/bin/env bash
# shell source. Lines are "name<TAB>kind<TAB>display", by mode ($FZX_MODE):
#   commands   kind: command (on PATH, the first of each name), builtin or reserved (zsh's)
#   aliases    kind: alias, galias (global) or salias (suffix)
#   functions  kind: function; completion functions (_*) only with the completion toggle
#   params     kind: param; exported ones only with the exported toggle
# Aliases, functions, parameters, builtins and reserved words come from the zsh dump (dump.zsh) that
# shell/fzx.zsh writes at the first prompt and its shell widget before it opens the module, used while
# younger than FZX_SHELL_DUMP_TTL (else read again from an interactive zsh). The environment is the one
# fzx started with: $FZX_SESSION_DIR/data/env (module.sh saves it), else this process's. Values of
# parameters whose names match FZX_SHELL_SECRETS are masked; the reveal toggle shows exported ones.

SHELL_MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shell::dump_dir <var>
shell::dump_dir() { printf -v "$1" '%s/shell' "$FZX_STATE_DIR"; }

# shell::dump <var>: the dump's file, fresh enough, or read now from an interactive zsh; fails without one
shell::dump() {
  local _dir _age
  shell::dump_dir _dir
  printf -v "$1" '%s/dump.tsv' "$_dir"
  if [[ -s "$_dir/dump.tsv" ]]; then
    _age=$((EPOCHSECONDS - $(stat -c %Y -- "$_dir/dump.tsv")))
    ((_age < ${FZX_SHELL_DUMP_TTL:-86400})) && return 0
  fi
  command -v zsh > /dev/null || return 1
  # setsid: an interactive zsh takes the terminal (its foreground process group), which would stop fzf
  timeout 20 setsid -w zsh -ic "source ${SHELL_MOD_DIR@Q}/dump.zsh; fzx-shell-dump-file" < /dev/null > /dev/null 2>&1
  [[ -s "$_dir/dump.tsv" ]] || { printf 'shell: could not read the shell from zsh -ic\n' >&2; return 1; }
}

# shell::split <line> <var...>: the line's tab-separated fields into the variables, the last one taking the
# rest; unlike `IFS=$'\t' read`, which merges a run of tabs (tab is IFS whitespace), empty fields are kept
shell::split() {
  local _l="$1" _v
  shift
  for _v; do
    if (($# > 1)) && [[ "$_l" == *$'\t'* ]]; then
      printf -v "$_v" '%s' "${_l%%$'\t'*}"
      _l="${_l#*$'\t'}"
    else
      printf -v "$_v" '%s' "$_l"
      _l=""
    fi
    shift
  done
}

# shell::secret <name>: the name matches FZX_SHELL_SECRETS
shell::secret() {
  local re="${FZX_SHELL_SECRETS:-TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|APIKEY|_KEY\$|PASS\$}"
  [[ "${1^^}" =~ $re ]]
}

# shell::env: the environment fzx started with, "name<TAB>value" (tabs, newlines and backslashes in values
# escaped as \t, \n and \\)
shell::env() {
  local file="${FZX_SESSION_DIR:+$FZX_SESSION_DIR/data/env}" n v
  if [[ -n "$file" && -f "$file" ]]; then
    while IFS= read -r -d '' v; do
      n="${v%%=*}" v="${v#*=}"
      v="${v//\\/\\\\}" v="${v//$'\t'/\\t}" v="${v//$'\n'/\\n}"
      printf '%s\t%s\n' "$n" "$v"
    done < "$file"
  else
    for n in $(compgen -e); do
      v="${!n}"
      v="${v//\\/\\\\}" v="${v//$'\t'/\\t}" v="${v//$'\n'/\\n}"
      printf '%s\t%s\n' "$n" "$v"
    done
  fi
}

# shell::save_env <file>: this process's environment (fzx's, before fzf adds its own), NUL-separated and
# owner-only, without the variables fzx itself exports
shell::save_env() {
  local n
  (
    umask 077
    for n in $(compgen -e); do
      [[ "$n" =~ ^FZX_(ROOT|RUNTIME_DIR|STATE_DIR|CONFIG_DIR|CACHE_DIR|MODULE_PATH|LOG_LEVEL|LOG_FILE|SESSION|SESSION_DIR|MODE|MODULE|MODULE_DIR|TOGGLES|SORT|STATS|STATS_FILE|SPLIT_PANE)$ ]] && continue
      printf '%s=%s\0' "$n" "${!n}"
    done > "$1.$BASHPID" && mv -f -- "$1.$BASHPID" "$1"
  )
}

# shell::path_commands: "name<TAB>path" for the first executable of each name on PATH
shell::path_commands() {
  local d dirs=()
  IFS=: read -ra dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    [[ -n "$d" && -d "$d" ]] && find -L "$d" -maxdepth 1 -type f -executable -printf '%f\t%p\n' 2> /dev/null
  done | awk -F'\t' '!seen[$1]++'
}

# the colors, as awk -v options (empty under NO_COLOR)
shell::colors() {
  local -A c=(
    [name]="${FZX_COLORS[shell_name]:-1;38;5;117}" [kind]="${FZX_COLORS[shell_kind]:-38;5;180}"
    [picon]="${FZX_COLORS[shell_param_icon]:-38;5;66}"
    [value]="${FZX_COLORS[shell_value]:-38;5;250}" [dim]="${FZX_COLORS[dim]:-38;5;244}"
    [export]="${FZX_COLORS[shell_export]:-38;5;75}" [masked]="${FZX_COLORS[shell_masked]:-38;5;203}"
  )
  local k
  for k in "${!c[@]}"; do
    if [[ -n "${NO_COLOR+x}" ]]; then printf -- '-v\nc_%s=\n' "$k"; else printf -- '-v\nc_%s=\e[%sm\n' "$k" "${c[$k]}"; fi
  done
  if [[ -n "${NO_COLOR+x}" ]]; then printf -- '-v\nr=\n'; else printf -- '-v\nr=\e[0m\n'; fi
}

# awk helpers shared by the modes: unq (the value without the single quotes zsh's (q+) put around a plain
# one), cut (one line, at most 160 characters)
SHELL_AWK_LIB='
  function unq(v) { if (v ~ /^'"'"'[^'"'"']*'"'"'$/) return substr(v, 2, length(v) - 2); return v }
  function cut(v) { gsub(/\t/, " ", v); return length(v) > 160 ? substr(v, 1, 159) "…" : v }
  function pad(s, w) { return length(s) >= w ? s " " : s sprintf("%" (w - length(s) + 1) "s", "") }'

shell::commands() {
  local dump="" opts=()
  mapfile -t opts < <(shell::colors)
  shell::dump dump 2> /dev/null || dump=""
  {
    shell::path_commands | LC_ALL=C sort -t $'\t' -k1,1 | awk -F'\t' '{ print "command\t" $1 "\t" $2 }'
    [[ -n "$dump" ]] && awk -F'\t' '$1 == "builtin" || $1 == "reserved" { print $1 "\t" $2 "\t" }' "$dump"
  } | awk -F'\t' "${opts[@]}" -v home="$HOME" "$SHELL_AWK_LIB"'
    { p = $3; if (index(p, home "/") == 1) p = "~" substr(p, length(home) + 1)
      kind = $1 == "command" ? "" : $1
      printf "%s\t%s\t%s%s%s %s%s%s%s\n", $2, $1, c_name, pad($2, 28), r, c_kind, (kind != "" ? pad(kind, 9) : ""), r, c_dim p r }'
}

shell::aliases() {
  local dump opts=()
  shell::dump dump || return
  mapfile -t opts < <(shell::colors)
  awk -F'\t' "${opts[@]}" "$SHELL_AWK_LIB"'
    $1 == "alias" { kind = $2 == "global" ? "galias" : $2 == "suffix" ? "salias" : "alias"
      printf "%s\t%s\t%s%s%s %s%s%s%s\n", $3, kind, c_name, pad($3, 20), r,
        (kind != "alias" ? c_kind $2 " " r : ""), c_value, cut(unq($4)), r }' "$dump"
}

shell::functions() {
  local dump opts=() all=0
  shell::dump dump || return
  [[ " ${FZX_TOGGLES:-} " == *" completion "* ]] && all=1
  mapfile -t opts < <(shell::colors)
  awk -F'\t' "${opts[@]}" -v all="$all" -v home="$HOME" "$SHELL_AWK_LIB"'
    $1 == "function" && (all || substr($2, 1, 1) != "_") {
      f = $3; if (index(f, home "/") == 1) f = "~" substr(f, length(home) + 1)
      printf "%s\tfunction\t%s%s%s %s%s%s%s\n", $2, c_name, pad($2, 32), r, ($4 == 1 ? c_kind "autoload " r : ""), c_dim, f, r }' "$dump"
}

# shell::param_rows: "name<TAB>type<TAB>value<TAB>masked" for every parameter: the dump's, with the
# exported ones' values (and any the dump lacks) from the environment fzx started with; values of secret
# names masked ("1") unless reveal is on and the value is exported
shell::param_rows() {
  local dump="" reveal=0 n v masked
  shell::dump dump 2> /dev/null || dump=""
  [[ " ${FZX_TOGGLES:-} " == *" reveal "* ]] && reveal=1
  {
    while IFS=$'\t' read -r n v; do
      masked=0
      shell::secret "$n" && masked=1
      ((masked && !reveal)) && v=""
      ((masked && reveal)) && masked=0
      printf 'E\t%s\t%s\t%s\n' "$n" "$v" "$masked"
    done < <(shell::env)
    [[ -n "$dump" ]] && awk -F'\t' '$1 == "param" { print "D\t" $2 "\t" $3 "\t" $4 "\t" $5 }' "$dump"
  } | awk -F'\t' 'BEGIN { OFS = "\t" }
      $1 == "E" { env[$2] = 1; ev[$2] = $3; em[$2] = $4; order[++n] = $2; next }
      { if ($2 in env) { if ($3 !~ /export/) $3 = $3 "-export"; seen[$2] = 1; type[$2] = $3; next }
        print $2, $3, $4, $5 }
      END { for (i = 1; i <= n; i++) { k = order[i]; print k, (k in type ? type[k] : "scalar-export"), "\001" ev[k], em[k] } }' |
    LC_ALL=C sort -t $'\t' -k1,1
}

shell::params() {
  local opts=() only=0
  [[ " ${FZX_TOGGLES:-} " == *" exported "* ]] && only=1
  mapfile -t opts < <(shell::colors)
  fzx::require icons
  fzx::icon_vars param_array param_assoc param_int param_float param_scalar
  # environment values are raw (marked by \001), the dump's quoted as zsh reads them back
  # the type as an icon before the name (no icons: the word, after it)
  shell::param_rows | awk -F'\t' "${opts[@]}" "${FZX_ICON_VARS[@]}" -v only="$only" "$SHELL_AWK_LIB"'
    only && $2 !~ /export/ { next }
    { t = $2; ex = t ~ /export/; sub(/-.*/, "", t); if (t == "association") t = "assoc"; if (t == "integer") t = "int"
      i = t == "array" ? icon_param_array : t == "assoc" ? icon_param_assoc : t == "int" ? icon_param_int : t == "float" ? icon_param_float : icon_param_scalar
      v = $3; if (substr(v, 1, 1) == "\001") v = substr(v, 2); else v = unq(v)
      shown = $4 == 1 ? c_masked "(masked)" r : c_value cut(v) r
      printf "%s\tparam\t%s%s%s%s%s%s\n", $1, (i != "" ? c_picon i r " " : ""), (ex ? c_export : c_name), pad($1, 28), r,
        (i != "" ? "" : " " c_kind pad(t, 6) r " "), shown }'
}

# shell::zsh_complete <var>: the zsh-complete command (FZX_SHELL_ZSH_COMPLETE, on PATH, ~/.shell's); fails
# when there is none
shell::zsh_complete() {
  local _z="${FZX_SHELL_ZSH_COMPLETE:-}"
  [[ -n "$_z" ]] || _z="$(command -v zsh-complete 2> /dev/null)" || _z="${SHELL_ROOT:-$HOME/.shell}/scripts/zsh-complete"
  printf -v "$1" '%s' "$_z"
  [[ -x "$_z" ]]
}

# shell::completions_file <var>: where zsh-complete's list is kept
shell::completions_file() { printf -v "$1" '%s/shell/completions.tsv' "${FZX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fzx}"; }

# shell::completions_refresh: ask zsh-complete for every binding (`list --tsv`: kind, command, source,
# function, path, upstream, revision) into the cache; the old list stays when it fails
shell::completions_refresh() {
  local z file tmp
  shell::zsh_complete z || { printf 'shell: zsh-complete not found (FZX_SHELL_ZSH_COMPLETE)\n' >&2; return 1; }
  shell::completions_file file
  mkdir -p -- "${file%/*}" || return 1
  tmp="$file.$BASHPID"
  if (cd ~ && NO_COLOR=1 "$z" list --tsv) > "$tmp" 2> /dev/null && head -1 "$tmp" | grep -q $'^kind\tcommand\t'; then
    mv -f -- "$tmp" "$file"
  else
    rm -f -- "$tmp"
    printf 'shell: zsh-complete list --tsv failed\n' >&2
    return 1
  fi
}

# shell::completions_rows: the cached list (read again once older than FZX_SHELL_COMPLETIONS_TTL), one row
# per command: "name<TAB>provider<TAB>function<TAB>path<TAB>upstream<TAB>revision<TAB>bindings", the main
# function the command's own (_name) when it has several
shell::completions_rows() {
  local file mtime
  shell::completions_file file
  mtime="$(stat -c %Y -- "$file" 2> /dev/null)" || mtime=0
  if ((EPOCHSECONDS - mtime >= ${FZX_SHELL_COMPLETIONS_TTL:-86400})); then
    shell::completions_refresh || [[ -s "$file" ]] || return 1
  fi
  awk -F'\t' -v OFS='\t' '
    $1 != "active" { next }
    {
      if (!($2 in n)) order[++k] = $2
      n[$2]++
      if (!($2 in main) || $4 == "_" $2) { main[$2] = $4; prov[$2] = $3; path[$2] = $5; up[$2] = $6; rev[$2] = $7 }
    }
    END { for (i = 1; i <= k; i++) { c = order[i]; print c, prov[c], main[c], path[c], up[c], rev[c], n[c] } }' "$file"
}

# shell::completions: the rows, the commands you have (on PATH, aliases, functions) unless the all toggle
# is on: name, provider (curated ones and the system's in their colors), function, file
shell::completions() {
  local dump="" opts=() all=0 own="${FZX_COLORS[shell_provider_own]:-38;5;114}" sys="${FZX_COLORS[shell_provider_system]:-38;5;244}"
  local other="${FZX_COLORS[shell_provider]:-38;5;180}"
  [[ " ${FZX_TOGGLES:-} " == *" all "* ]] && all=1
  [[ -n "${NO_COLOR+x}" ]] && own="" sys="" other=""
  mapfile -t opts < <(shell::colors)
  ((all)) || shell::dump dump 2> /dev/null || dump=""
  {
    if ((!all)); then
      shell::path_commands | cut -f1 | sed 's/^/H\t/'
      [[ -n "$dump" ]] && awk -F'\t' '$1 == "alias" { print "H\t" $3 } $1 == "function" && substr($2, 1, 1) != "_" { print "H\t" $2 }' "$dump"
    fi
    shell::completions_rows | sed 's/^/R\t/'
  } | awk -F'\t' "${opts[@]}" -v all="$all" -v home="$HOME" -v own="$own" -v sys="$sys" -v other="$other" "$SHELL_AWK_LIB"'
    $1 == "H" { have[$2] = 1; next }
    all || ($2 in have) {
      p = $5; if (index(p, home "/") == 1) p = "~" substr(p, length(home) + 1)
      pc = $3 ~ /^(static|generated|local|source)$/ ? own : $3 == "system" ? sys : other
      pv = pc == "" ? pad($3, 20) : "\033[" pc "m" pad($3, 20) r
      printf "%s\tcompletion\t%s%s%s %s%s%s%s %s%s%s\n", $2, c_name, pad($2, 28), r, pv, c_kind, pad($4, 24), r, c_dim, p, r
    }' | LC_ALL=C sort -t $'\t' -k1,1
}

shell::source() {
  case "${FZX_MODE:-commands}" in
    commands) shell::commands ;;
    aliases) shell::aliases ;;
    functions) shell::functions ;;
    params) shell::params ;;
    completions) shell::completions ;;
    *)
      printf 'shell: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" shell
  shell::source "$@"
}
