#!/usr/bin/env bash
# packages preview by the row's id (see source.sh): apt's installed and candidate versions, the package's
# fields and description, and the commands an installed one provides; snap info; flatpak info (an
# application not installed: its appstream entry); a pipx venv's metadata and its package's summary; a
# crate's source, binaries and features (its description from cargo's registry sources when they are still
# there); a pnpm package's package.json; a gem's specification. A snap, crate, npm package, gem or PyPI
# package that is not installed is described from the network, once a day per package (remote.sh).

[[ -n "${_FZX_CORE_LOADED:-}" ]] || source "${FZX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/core.sh"
# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# packages::_c <color key> <fallback>: the SGR of FZX_COLORS[packages_<key>]
packages::_c() { printf '\e[%sm' "${FZX_COLORS[packages_$1]:-$2}"; }

# packages::_title <name> [version]
packages::_title() {
  printf '%s%s\e[0m  %s%s\e[0m\n\n' "$(packages::_c title '1;38;5;255')" "$1" "$(packages::_c version '38;5;110')" "${2:-}"
}

# packages::_kv <key> <value>: one field, the key dim and padded; nothing for an empty value
packages::_kv() {
  [[ -n "$2" ]] || return 0
  printf '%s%-12s\e[0m %s\n' "$(packages::_c key '38;5;244')" "$1" "$2"
}

# packages::_keys: "key: value" lines on stdin with the keys dim (other lines as they are)
packages::_keys() {
  awk -v k="$(packages::_c key '38;5;244')" '
    match($0, /^ *[A-Za-z][A-Za-z0-9 _-]*:( |$)/) { print k substr($0, 1, RLENGTH) "\033[0m" substr($0, RLENGTH + 1); next }
    { print }'
}

# packages::_kvs: "key<TAB>value" lines on stdin as fields
packages::_kvs() {
  local k v
  while IFS=$'\t' read -r k v; do packages::_kv "$k" "$v"; done
}

# packages::apt_record <name>: the package's control record. An installed one from dpkg; another from
# apt's lists, the highest version for this architecture (or all), its long description from the
# Translation files. apt-cache is not used: it takes over a second per call on a full archive
packages::apt_record() {
  local name="$1" lists rec
  lists="$(packages::_apt_lists)"
  rec="$(command dpkg-query -s -- "$name" 2> /dev/null)"
  if [[ "$rec" == *$'\nStatus: install ok installed'* || "$rec" == *$'\nStatus: hold ok installed'* ]]; then
    printf '%s\n' "$rec"
    return 0
  fi
  local arch best="" bestver="" ver r
  arch="$(command dpkg --print-architecture 2> /dev/null)"
  local -a recs=()
  mapfile -d $'\x1e' -t recs < <(LC_ALL=C command grep -h -A200 -m1 -x -F "Package: $name" "$lists"/*_Packages 2> /dev/null |
    LC_ALL=C awk -v p="Package: $name" '$0 == p { if (on) printf "\036"; on = 1 } on && /^(--)?$/ { if (on == 1) on = 2; next } on == 1 { print }')
  for r in "${recs[@]}"; do
    [[ "$r" == *$'\nArchitecture: '"$arch"$'\n'* || "$r" == *$'\nArchitecture: all\n'* ]] || continue
    ver="${r#*$'\nVersion: '}"
    ver="${ver%%$'\n'*}"
    if [[ -z "$bestver" ]] || command dpkg --compare-versions "$ver" gt "$bestver"; then
      best="$r"
      bestver="$ver"
    fi
  done
  [[ -n "$best" ]] || return 1
  local desc
  desc="$(LC_ALL=C command grep -h -A200 -m1 -x -F "Package: $name" "$lists"/*_i18n_Translation-en 2> /dev/null |
    LC_ALL=C awk '/^Description-en: / { on = 1; print; next } on && /^ / { print; next } on { exit }')"
  if [[ -n "$desc" ]]; then
    printf '%s\n' "$best" | grep -v '^Description'
    printf '%s\n' "$desc"
  else
    # lists that carry the long description themselves (third-party archives)
    printf '%s\n' "$best"
  fi
  return 0
}

# packages::_apt <name>: installed version (and the candidate, from the upgradable cache), the record's
# fields, its description, and the commands an installed package puts on PATH
packages::_apt() {
  local name="$1" rec installed="" candidate="" k
  k="$(packages::_c key '38;5;244')"
  rec="$(packages::apt_record "$name")" || {
    printf 'apt: no package %s\n' "$name"
    return 0
  }
  if [[ "$rec" == *$'\nStatus: '*' installed'* ]]; then
    installed="${rec#*$'\nVersion: '}"
    installed="${installed%%$'\n'*}"
    [[ -f "$FZX_CACHE_DIR/packages/upgradable" ]] &&
      candidate="$(awk -F '\t' -v n="$name" '$1 == n { print $3; exit }' "$FZX_CACHE_DIR/packages/upgradable")"
  fi
  local ver="${rec#*$'\nVersion: '}"
  packages::_title "$name" "${ver%%$'\n'*}"
  packages::_kv installed "${installed:-not installed}"
  [[ -n "$candidate" ]] && packages::_kv upgrade "$(packages::_c upgrade '38;5;179')$candidate"$'\e[0m'
  printf '%s\n' "$rec" | awk -v k="$k" '
    function kv(key, val) { if (val != "") printf "%s%-12s\033[0m %s\n", k, key, val }
    function human(n) { n += 0; return n >= 1048576 ? sprintf("%.1fG", n / 1048576) : n >= 1024 ? sprintf("%dM", n / 1024) : n "K" }
    /^ / { if (indesc) body = body (substr($0, 2) == "." ? "" : substr($0, 2)) "\n"; next }
    { indesc = 0; key = $0; sub(/:.*/, "", key); val = $0; sub(/^[^:]*: */, "", val) }
    key == "Section" { section = val }
    key == "Installed-Size" { size = human(val) }
    key == "Maintainer" { maint = val }
    key == "Depends" { deps = val }
    key == "Recommends" { recs = val }
    key == "Homepage" { home = val }
    key == "Source" { src = val }
    key ~ /^Description(-[a-z_A-Z]+)?$/ && summary == "" { summary = val; indesc = 1 }
    END {
      kv("section", section); kv("size", size); kv("source", src); kv("homepage", home); kv("maintainer", maint)
      kv("depends", deps); kv("recommends", recs)
      if (summary != "") printf "\n\033[1m%s\033[0m\n%s", summary, body
    }'
  [[ -n "$installed" ]] || return 0
  local cmds
  cmds="$(command dpkg-query -L -- "$name" 2> /dev/null | awk -F/ '/^\/(usr\/)?(s?bin|games)\/[^\/]+$/ { printf "%s%s", sep, $NF; sep = " " }')"
  [[ -n "$cmds" ]] && printf '\n%scommands\e[0m\n%s\n' "$k" "$cmds" | fold -s -w "${FZF_PREVIEW_COLUMNS:-80}"
  return 0
}

# packages::_remote <manager> <name>: details of a package that is not installed, from the network
# (cached; remote.sh)
packages::_remote() {
  local info
  if info="$(packages::remote_info "$1" "$2")"; then
    packages::render_info <<< "$info"
  else
    packages::_title "$2"
    printf 'no details from %s (offline, or no such package)\n' "$1"
  fi
  return 0
}

# packages::_snap <name>: an installed snap's snap info as it is now; another one's, cached
packages::_snap() {
  if command snap list -- "$1" > /dev/null 2>&1; then
    command snap info --color=never --unicode=never -- "$1" 2>&1 | packages::_keys
  else
    packages::_remote snap "$1"
  fi
}

# packages::_flatpak <installation> <app[@remote]>: flatpak info when installed; else the application's
# entry in the remote's appstream data (the flatpak-available cache)
packages::_flatpak() {
  local inst="$1" app="${2%@*}" remote="" line
  [[ "$2" == *@* ]] && remote="${2##*@}"
  if command flatpak info "--$inst" -- "$app" > /dev/null 2>&1 || [[ -z "$remote" ]]; then
    command flatpak info "--$inst" -- "$app" 2>&1 | packages::_keys
    return 0
  fi
  line="$(awk -F '\t' -v a="$app" '$1 == a { print; exit }' "$FZX_CACHE_DIR/packages/flatpak-$inst-$remote" 2> /dev/null)"
  [[ -n "$line" ]] || {
    printf 'flatpak: %s: not in the %s catalog\n' "$app" "$remote"
    return 0
  }
  local name ver summary developer license homepage desc
  # tab is IFS whitespace, so empty fields would collapse: split on \x1e instead
  IFS=$'\x1e' read -r _ name ver summary _ _ developer license homepage desc <<< "${line//$'\t'/$'\x1e'}"
  packages::_title "${name:-$app}" "$ver"
  packages::_kv installed "not installed"
  packages::_kv id "$app"
  packages::_kv remote "$remote ($inst)"
  packages::_kv developer "$developer"
  packages::_kv license "$license"
  packages::_kv homepage "$homepage"
  [[ -n "$summary" ]] && printf '\n\e[1m%s\e[0m\n' "$summary"
  [[ -n "$desc" ]] && printf '%s\n' "${desc//$'\x1f'/$'\n\n'}" | fold -s -w "${FZF_PREVIEW_COLUMNS:-80}"
  return 0
}

# packages::_pipx <name>: the venv's metadata (version, apps, python, injected packages) and its package's
# summary and links from the installed METADATA
packages::_pipx() {
  local name="$1" home venv meta md
  home="$(packages::_pipx_home)"
  venv="$home/venvs/$name"
  meta="$venv/pipx_metadata.json"
  [[ -f "$meta" ]] || {
    packages::_remote pipx "$name"
    return 0
  }
  packages::_title "$name" "$(command jq -r '.main_package.package_version // ""' "$meta")"
  packages::_kv apps "$(command jq -r '.main_package.apps // [] | join(" ")' "$meta")"
  packages::_kv python "$(command jq -r '.python_version // ""' "$meta")"
  packages::_kv injected "$(command jq -r '.injected_packages // {} | keys | join(" ")' "$meta")"
  packages::_kv venv "$venv"
  local norm="${name//-/_}"
  shopt -s nullglob nocaseglob
  for md in "$venv"/lib/python*/site-packages/"$norm"-*.dist-info/METADATA; do
    printf '\n'
    awk '/^$/ { exit } /^(Summary|Home-page|Project-URL|License|Author): / { k = tolower($1); sub(/:$/, "", k); v = $0; sub(/^[^:]*: /, "", v); print k "\t" v }' "$md" |
      packages::_kvs
    break
  done
  shopt -u nullglob nocaseglob
  return 0
}

# packages::_cargo <name>: the crate's install record and, from the registry's unpacked sources when they
# are still there, its description and links
packages::_cargo() {
  local name="$1" ver src bins toml
  IFS=$'\t' read -r _ ver src bins < <(packages::cargo_installs 2> /dev/null | awk -F '\t' -v n="$name" '$1 == n')
  [[ -n "$ver" ]] || {
    packages::_remote cargo "$name"
    return 0
  }
  packages::_title "$name" "$ver"
  packages::_kv source "$src"
  packages::_kv binaries "$bins"
  command jq -r --arg n "$name" '.installs | to_entries[] | select(.key | startswith($n + " ")) | .value
    | "features\t" + (.features | join(" ")) + (if .all_features then " (all)" else "" end),
      "profile\t" + (.profile // ""), "rustc\t" + ((.rustc // "") | split("\n")[0])' "$(packages::_crates)" 2> /dev/null |
    packages::_kvs
  for toml in "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/"$name-$ver"/Cargo.toml; do
    [[ -f "$toml" ]] || continue
    printf '\n'
    awk '/^\[/ { pkg = ($0 == "[package]"); next }
      multi { if ((i = index($0, "\"\"\"")) > 0) { v = v " " substr($0, 1, i - 1); multi = 0; gsub(/  +/, " ", v); sub(/^ /, "", v); sub(/ +$/, "", v); print k "\t" v } else v = v " " $0; next }
      pkg && /^(description|homepage|repository|license) *= *"/ {
        k = $1; v = $0; sub(/^[^"]*"/, "", v)
        # a """multi-line""" string runs to its closing quotes
        if (substr(v, 1, 2) == "\"\"") { v = substr(v, 3); if ((i = index(v, "\"\"\"")) > 0) v = substr(v, 1, i - 1); else { multi = 1; next } }
        sub(/" *$/, "", v); print k "\t" v
      }' "$toml" |
      packages::_kvs
    break
  done
  return 0
}

# packages::_pnpm <name>: the package's package.json fields
packages::_pnpm() {
  local name="$1" dir
  dir="$(command pnpm ls -g --depth=0 --json 2> /dev/null | command jq -r --arg n "$name" '.[] | .dependencies // {} | .[$n].path // empty' | head -1)"
  [[ -n "$dir" && -f "$dir/package.json" ]] || {
    packages::_remote pnpm "$name"
    return 0
  }
  packages::_title "$name" "$(command jq -r '.version // ""' "$dir/package.json")"
  command jq -r '"description\t" + (.description // ""),
    "homepage\t" + (.homepage // (.repository | if type == "object" then .url else . end) // ""),
    "license\t" + ((.license // "") | tostring),
    "binaries\t" + (.bin // {} | if type == "string" then "" else keys | join(" ") end)' "$dir/package.json" |
    packages::_kvs
  packages::_kv path "$dir"
  return 0
}

# packages::_gem <scope> <name>: each installed version's specification: summary, homepage, licenses,
# authors, executables
packages::_gem() {
  local scope="$1" name="$2" s dir spec
  local -a specs=()
  while IFS=$'\t' read -r s dir; do
    [[ "$s" == "$scope" ]] || continue
    for spec in "$dir/specifications/$name"-[0-9]*.gemspec; do
      [[ -f "$spec" ]] && specs+=("$spec")
    done
  done < <(packages::gem_dirs)
  ((${#specs[@]})) || {
    packages::_remote gem "$name"
    return 0
  }
  local versions="" base
  for spec in "${specs[@]}"; do
    base="${spec##*/}"
    base="${base#"$name"-}"
    versions+="${versions:+, }${base%.gemspec}"
  done
  packages::_title "$name" "$versions"
  packages::_kv scope "$scope"
  awk '/\.(summary|homepage|licenses|authors|executables|required_ruby_version) = / {
      k = $0; sub(/^[^.]*\./, "", k); sub(/ .*/, "", k); v = $0; sub(/^[^=]*= */, "", v)
      gsub(/\.freeze/, "", v); gsub(/^%q\{|\}$/, "", v); gsub(/"/, "", v); gsub(/^\[|\]$/, "", v)
      if (k == "required_ruby_version") { k = "ruby"; sub(/^Gem::Requirement\.new\(/, "", v); sub(/\)$/, "", v) }
      if (!(k in seen)) { seen[k] = 1; print k "\t" v } }' "${specs[-1]}" | packages::_kvs
  packages::_kv dir "${specs[-1]%/specifications/*}"
  return 0
}

# packages::preview <id>
packages::preview() {
  local id="${1:-}" manager rest
  manager="${id%%:*}"
  rest="${id#*:}"
  [[ -n "$id" && "$id" == *:* ]] || {
    printf 'not a package id: %s\n' "$id"
    return 1
  }
  case "$manager" in
    apt) packages::_apt "$rest" ;;
    snap) packages::_snap "$rest" ;;
    flatpak) packages::_flatpak "${rest%%:*}" "${rest#*:}" ;;
    pipx) packages::_pipx "$rest" ;;
    cargo) packages::_cargo "$rest" ;;
    pnpm) packages::_pnpm "$rest" ;;
    gem) packages::_gem "${rest%%:*}" "${rest#*:}" ;;
    *)
      printf 'unknown package manager: %s\n' "$manager"
      return 1
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && packages::preview "$@"
