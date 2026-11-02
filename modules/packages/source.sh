#!/usr/bin/env bash
# packages source. Lines are "id<TAB>name<TAB>display"; the id names the manager (and for flatpak and gem
# the installation), so preview and actions dispatch on it rather than on the mode:
#   apt:NAME  snap:NAME  flatpak:system|user:APP  pipx:NAME  cargo:NAME  pnpm:NAME  gem:user|system:NAME
# Mode from $FZX_MODE: apt (installed), available, upgradable, snap, flatpak, pipx, cargo, pnpm, gem.
# available and upgradable take ~2s from apt, so their raw lists are cached in $FZX_CACHE_DIR/packages,
# rebuilt when /var/lib/apt/lists (and for upgradable /var/lib/dpkg/status) changes; rows are formatted on
# every run, so the installed marks stay current.
# $FZX_TOGGLES: manual (apt: no dependencies), runtimes (flatpak). $FZX_SORT: name (default) or size (apt).
# snap-available, flatpak-available and search are in remote.sh.

declare -gA FZX_COLORS

packages::_apt_lists() { printf '%s' "${FZX_PACKAGES_APT_LISTS:-/var/lib/apt/lists}"; }
packages::_dpkg_status() { printf '%s' "${FZX_PACKAGES_DPKG_STATUS:-/var/lib/dpkg/status}"; }
packages::_extended_states() { printf '%s' "${FZX_PACKAGES_EXTENDED_STATES:-/var/lib/apt/extended_states}"; }
packages::_pipx_home() {
  local home="${PIPX_HOME:-$HOME/.local/share/pipx}"
  [[ -z "${PIPX_HOME:-}" && ! -d "$home/venvs" && -d "$HOME/.local/pipx/venvs" ]] && home="$HOME/.local/pipx"
  printf '%s' "$home"
}
packages::_crates() { printf '%s' "${CARGO_HOME:-$HOME/.cargo}/.crates2.json"; }

# packages::has <manager>: the manager's tools are on PATH (and what its list is read from exists)
packages::has() {
  case "$1" in
    apt) command -v dpkg-query > /dev/null && command -v apt-cache > /dev/null ;;
    snap | flatpak) command -v "$1" > /dev/null ;;
    pipx | pnpm) command -v "$1" > /dev/null && command -v jq > /dev/null ;;
    cargo) command -v cargo > /dev/null && command -v jq > /dev/null && [[ -f "$(packages::_crates)" ]] ;;
    gem) command -v gem > /dev/null ;;
    *) return 1 ;;
  esac
}

# packages::gem_dirs: "scope<TAB>dir" for each gem home that exists (FZX_PACKAGES_GEM_DIRS: "scope:glob"
# entries); the gems apt installs (/usr/lib/ruby, rubygems-integration) are apt's, not listed
packages::gem_dirs() {
  local entry d
  local -a dirs=("${FZX_PACKAGES_GEM_DIRS[@]}")
  ((${#dirs[@]})) || dirs=("user:$HOME/.local/share/gem/ruby/*" "system:/var/lib/gems/*" "system:/usr/local/lib/ruby/gems/*")
  for entry in "${dirs[@]}"; do
    for d in ${entry#*:}; do
      [[ -d "$d/specifications" ]] && printf '%s\t%s\n' "${entry%%:*}" "$d"
    done
  done
}

# packages::_awk_lib: awk functions shared by the lists; colors come in as -v n (name), v (version),
# d (dim), hl (the sorted column)
packages::_awk_lib() {
  printf '%s' '
    function cell(color, text, w, on) { return color (on ? hl : "") text "\033[0m" sprintf("%" (w - length(text) > 0 ? w - length(text) : 0) "s", "") }
    # KiB as 512K, 12M, 1.4G
    function human(k) { return k >= 1048576 ? sprintf("%.1fG", k / 1048576) : k >= 1024 ? sprintf("%dM", k / 1024) : sprintf("%dK", k) }
    # row(key, id, name, icon, rest[, label]): the label (else the name) in the name column
    function row(key, id, name, icon, rest, label) { printf "%s\t%s\t%s\t%s %s %s\n", key, id, name, icon, cell(n, label == "" ? name : label, 36, sort == "name"), rest }
  '
}

# packages::_awk <program> [files...]: awk with the shared functions and the colors. The C locale halves
# the time on apt's 75k packages; the padded columns are ASCII, so counting bytes is counting characters
packages::_awk() {
  local prog="$1"
  shift
  LC_ALL=C awk -F '\t' -v sort="${FZX_SORT:-name}" -v toggles=" ${FZX_TOGGLES:-} " \
    -v n=$'\e['"${FZX_COLORS[packages_name]:-38;5;252}m" -v v=$'\e['"${FZX_COLORS[packages_version]:-38;5;110}m" \
    -v d=$'\e['"${FZX_COLORS[packages_dim]:-38;5;244}m" -v hl=$'\e['"${FZX_COLORS[sorted]:-4}m" \
    -v on=$'\e['"${FZX_COLORS[packages_installed]:-38;5;114}m" -v off=$'\e['"${FZX_COLORS[packages_missing]:-38;5;240}m" \
    -v up=$'\e['"${FZX_COLORS[packages_upgrade]:-38;5;179}m" \
    "$(packages::_awk_lib)$prog" "$@"
}

# packages::_sorted: the lists' "key<TAB>row" lines in key order, the key dropped (size: numeric, largest first)
packages::_sorted() {
  if [[ "${FZX_SORT:-name}" == size ]]; then
    LC_ALL=C sort -s -t $'\t' -k1,1nr | cut -f2-
  else
    LC_ALL=C sort -s -t $'\t' -k1,1 | cut -f2-
  fi
}

# packages::_cached <name> <stamp> <cmd...>: the command's output, kept in $FZX_CACHE_DIR/packages/<name>
# while the stamp holds; a failing command leaves the cache alone
packages::_cached() {
  local file="$FZX_CACHE_DIR/packages/$1" stamp="$2" tmp rc
  if [[ -f "$file" && -f "$file.stamp" && "$(< "$file.stamp")" == "$stamp" ]]; then
    cat -- "$file"
    return 0
  fi
  mkdir -p -- "${file%/*}"
  tmp="$(mktemp "$file.XXXXXX")"
  "${@:3}" > "$tmp"
  rc=$?
  if ((rc)); then
    rm -f -- "$tmp"
    return "$rc"
  fi
  mv -f -- "$tmp" "$file"
  printf '%s' "$stamp" > "$file.stamp"
  cat -- "$file"
}

# packages::_stamp <paths...>: their modification times, joined
packages::_stamp() {
  local p out=""
  for p in "$@"; do out+="$(stat -c %Y -- "$p" 2> /dev/null || echo 0) "; done
  printf '%s' "$out"
}

# packages::_installed: "status<TAB>package<TAB>version<TAB>KiB<TAB>summary" from dpkg
packages::_installed() {
  command dpkg-query -W -f '${db:Status-Abbrev}\t${binary:Package}\t${Version}\t${Installed-Size}\t${binary:Summary}\n'
}

# packages::apt: installed packages; dependencies (Auto-Installed in extended_states) dim, left out with the
# manual toggle; held ones marked
packages::apt() {
  local ext
  ext="$(packages::_extended_states)"
  [[ -r "$ext" ]] || ext=/dev/null
  packages::_installed | packages::_awk '
    FILENAME == ext {
      if ($0 ~ /^Package: /) { p = substr($0, 10) }
      else if ($0 ~ /^Architecture: /) { a = substr($0, 15) }
      else if ($0 == "Auto-Installed: 1") { auto[p] = 1; auto[p ":" a] = 1 }
      next
    }
    $1 !~ /^.i/ { next }
    {
      name = $2; isauto = (name in auto)
      if (isauto && index(toggles, " manual ")) next
      held = substr($1, 1, 1) == "h"
      icon = held ? up "⏸\033[0m" : isauto ? off "○\033[0m" : on "●\033[0m"
      key = sort == "size" ? $4 + 0 : tolower(name)
      row(key, "apt:" name, name, icon, cell(v, $3, 28, 0) " " cell(d, human($4 + 0), 6, sort == "size") " " (isauto ? off : d) $5 "\033[0m")
    }' ext="$ext" "$ext" - | packages::_sorted
}

# packages::_available_raw: "package<TAB>summary" for every package the archives offer, by name
packages::_available_raw() {
  local -
  set -o pipefail
  command apt-cache search --names-only . | awk '{ i = index($0, " - "); if (i) print substr($0, 1, i - 1) "\t" substr($0, i + 3) }' |
    sort -t $'\t' -k1,1
}

# packages::available: every package apt knows, installed ones marked
packages::available() {
  local raw
  raw="$(mktemp)"
  # shellcheck disable=SC2064  # the path is fixed now
  trap "rm -f -- '$raw'" RETURN
  packages::_cached available "$(packages::_stamp "$(packages::_apt_lists)")" packages::_available_raw > "$raw" || return
  command dpkg-query -W -f '${db:Status-Abbrev}\t${Package}\n' | packages::_awk '
    FILENAME != raw { if ($1 ~ /^.i/) inst[$2] = 1; next }
    {
      icon = ($1 in inst) ? on "●\033[0m" : off "○\033[0m"
      row("", "apt:" $1, $1, icon, d $2 "\033[0m")
    }' raw="$raw" - "$raw" | cut -f2-
}

# packages::_upgradable_raw: "package<TAB>suite<TAB>new<TAB>old" from apt list --upgradable
packages::_upgradable_raw() {
  local -
  set -o pipefail
  command apt list --upgradable 2> /dev/null | awk '
    / \[upgradable from: / {
      split($1, ps, "/"); old = $0; sub(/.*\[upgradable from: /, "", old); sub(/\].*/, "", old)
      print ps[1] "\t" ps[2] "\t" $2 "\t" old
    }' | sort -t $'\t' -k1,1
}

# packages::upgradable: installed packages with a newer candidate: installed -> candidate, the suite
packages::upgradable() {
  local stamp
  stamp="$(packages::_stamp "$(packages::_apt_lists)" "$(packages::_dpkg_status)")"
  packages::_cached upgradable "$stamp" packages::_upgradable_raw | packages::_awk '
    { row("", "apt:" $1, $1, up "↑\033[0m", cell(d, $4, 24, 0) " " cell(v, $3, 24, 0) " " d $2 "\033[0m") }' | cut -f2-
}

# packages::snap: snap list: version, tracking channel, publisher (its verified marks dropped), notes
packages::snap() {
  command snap list --color=never --unicode=never | packages::_awk '
    NR == 1 { next }
    {
      split($0, f, / +/); pub = f[5]; gsub(/[*]+$/, "", pub)
      notes = f[6] == "-" ? "" : f[6]
      row(tolower(f[1]), "snap:" f[1], f[1], on "●\033[0m", cell(v, f[2], 28, 0) " " cell(d, f[4], 16, 0) " " cell(d, pub, 18, 0) " " up notes "\033[0m")
    }' | packages::_sorted
}

# packages::flatpak: applications (runtimes too with the runtimes toggle): name, version, installation, id
packages::flatpak() {
  local -a kind=(--app)
  [[ " ${FZX_TOGGLES:-} " == *" runtimes "* ]] && kind=()
  command flatpak list "${kind[@]}" --columns=application,name,version,installation,origin | packages::_awk '
    $1 == "" { next }
    {
      label = $2 == "" ? $1 : $2
      row(tolower(label), "flatpak:" $4 ":" $1, $1, on "●\033[0m", cell(v, $3, 16, 0) " " cell(d, $4, 7, 0) " " d $1 "  " $5 "\033[0m", label)
    }' | packages::_sorted
}

# packages::pipx: pipx venvs from their metadata: version and the applications they expose
packages::pipx() {
  local home
  home="$(packages::_pipx_home)"
  local -a meta=("$home"/venvs/*/pipx_metadata.json)
  [[ -f "${meta[0]}" ]] || return 0
  command jq -r '[.main_package.package, .main_package.package_version, (.main_package.apps // [] | join(" "))] | @tsv' "${meta[@]}" |
    packages::_awk '{ row(tolower($1), "pipx:" $1, $1, on "●\033[0m", cell(v, $2, 20, 0) " " d $3 "\033[0m") }' | packages::_sorted
}

# packages::cargo_installs: "name<TAB>version<TAB>source<TAB>binaries" from cargo's .crates2.json
packages::cargo_installs() {
  command jq -r '.installs // {} | to_entries[] | (.key | capture("^(?<n>[^ ]+) (?<v>[^ ]+) \\((?<s>.*)\\)$")) as $k
    | [$k.n, $k.v, $k.s, (.value.bins // [] | join(" "))] | @tsv' "$(packages::_crates)"
}

# packages::cargo: crates from cargo install: version, source (crates.io, a git repository and its branch,
# a path), binaries
packages::cargo() {
  packages::cargo_installs | packages::_awk '
    {
      src = $3
      if (src ~ /^(registry|sparse)\+/) src = (src ~ /crates\.io/) ? "crates.io" : src
      else if (src ~ /^git\+/) {
        ref = ""; if (match(src, /[?&](branch|tag|rev)=[^#&]*/)) ref = " (" substr(src, RSTART + 1, RLENGTH - 1) ")"
        sub(/^git\+[a-z]+:\/\/(git@)?/, "", src); sub(/[?#].*/, "", src); sub(/\.git$/, "", src); src = src ref
      } else if (src ~ /^path\+file:\/\//) src = substr(src, 13)
      row(tolower($1), "cargo:" $1, $1, on "●\033[0m", cell(v, $2, 20, 0) " " cell(d, src, 44, 0) " " d $4 "\033[0m")
    }' | packages::_sorted
}

# packages::pnpm: pnpm's global packages and their versions
packages::pnpm() {
  command pnpm ls -g --depth=0 --json 2> /dev/null |
    command jq -r '.[] | .dependencies // {} | to_entries[] | [.key, .value.version // ""] | @tsv' |
    packages::_awk '{ row(tolower($1), "pnpm:" $1, $1, on "●\033[0m", v $2 "\033[0m") }' | packages::_sorted
}

# packages::gem: gems by their specifications in each gem home (user, system): versions, home, summary.
# Name and version come from the file name, the summary from the file
packages::gem() {
  local scope dir spec
  while IFS=$'\t' read -r scope dir; do
    for spec in "$dir"/specifications/*.gemspec; do
      [[ -f "$spec" ]] && printf '%s\t%s\n' "$scope" "$spec"
    done
  done < <(packages::gem_dirs) | packages::_awk '
    {
      scope = $1; file = $2; base = file; sub(/.*\//, "", base); sub(/\.gemspec$/, "", base)
      # name-version[-platform]: the version starts at the last "-" followed by a digit
      cut_ = 0; for (i = length(base); i > 1; i--) if (substr(base, i - 1, 1) == "-" && substr(base, i, 1) ~ /[0-9]/) { cut_ = i; break }
      name = cut_ ? substr(base, 1, cut_ - 2) : base; ver = cut_ ? substr(base, cut_) : ""; sub(/-.*/, "", ver)
      k = scope SUBSEP name
      if (!(k in vers)) { order[++cnt] = k; sc[k] = scope; nm[k] = name }
      vers[k] = (k in vers) ? vers[k] ", " ver : ver
      if (!(k in summ)) {
        while ((getline line < file) > 0) if (line ~ /\.summary = /) {
          sub(/^[^=]*= *(%q\{|")/, "", line); sub(/("|\})(\.freeze)?$/, "", line); summ[k] = line; break
        }
        close(file)
      }
    }
    END {
      for (i = 1; i <= cnt; i++) {
        k = order[i]
        row(tolower(nm[k]) "\t" sc[k], "gem:" sc[k] ":" nm[k], nm[k], on "●\033[0m", cell(v, vers[k], 20, 0) " " cell(d, sc[k], 7, 0) " " d summ[k] "\033[0m")
      }
    }' | LC_ALL=C sort -s -t $'\t' -k1,1 -k2,2 | cut -f3-
}

packages::source() {
  local mode="${FZX_MODE:-apt}"
  case "$mode" in
    apt | available | upgradable) packages::has apt || {
      printf 'packages: apt is not installed\n' >&2
      return 1
    } ;;
    snap | flatpak | pipx | cargo | pnpm | gem | snap-available | flatpak-available) packages::has "${mode%-available}" || {
      printf 'packages: %s is not installed\n' "${mode%-available}" >&2
      return 1
    } ;;
    search) ;;
    *)
      printf 'packages: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
  case "$mode" in
    snap-available) packages::snap_available ;;
    flatpak-available) packages::flatpak_available ;;
    *) "packages::$mode" ;;
  esac
}

# shellcheck source=./remote.sh
source "$(dirname "${BASH_SOURCE[0]}")/remote.sh"

[[ "${BASH_SOURCE[0]}" == "$0" ]] && packages::source "$@"
