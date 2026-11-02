#!/usr/bin/env bash
# packages beyond what is installed: the snap and flatpak catalogs (local: snapd's list of names, the
# remotes' appstream data), the search mode (crates.io, npm, rubygems.org, and PyPI by exact name, over the
# network as you type), and package details from the network for previews, cached per package for
# FZX_PACKAGES_INFO_TTL seconds.
#
# Info cache files ($FZX_CACHE_DIR/packages/info/<manager>/<name>): "name<TAB>version", then "key<TAB>value"
# lines, then a line "--" and the description; packages::render_info draws them.

# packages::_curl <url>: the body, failing on HTTP errors and after FZX_PACKAGES_NET_TIMEOUT seconds
packages::_curl() {
  command curl -fsSL --max-time "${FZX_PACKAGES_NET_TIMEOUT:-10}" -- "$1"
}

# packages::_uri <text>: percent-encoded
packages::_uri() { command jq -rn --arg q "$1" '$q | @uri'; }

# packages::snap_names: the file snapd keeps every snap's name in (for completion), when there is one
packages::snap_names() { printf '%s' "${FZX_PACKAGES_SNAP_NAMES:-/var/cache/snapd/names}"; }

# packages::snap_available: every snap name snapd knows, installed ones marked (summaries need the store:
# the preview fetches them)
packages::snap_available() {
  local names
  names="$(packages::snap_names)"
  [[ -r "$names" ]] || {
    printf 'packages: no snap catalog at %s\n' "$names" >&2
    return 1
  }
  command snap list --color=never --unicode=never 2> /dev/null | packages::_awk '
    FILENAME != names { if (FNR > 1) inst[$1] = 1; next }
    $0 != "" { row("", "snap:" $0, $0, ($0 in inst) ? on "●\033[0m" : off "○\033[0m", "") }' FS=' ' names="$names" - "$names" |
    cut -f2-
}

# packages::flatpak_remotes: "installation<TAB>remote<TAB>appstream file" for each remote with appstream data
packages::flatpak_remotes() {
  local arch remote options inst base f
  arch="$(command flatpak --default-arch 2> /dev/null)"
  while IFS=$'\t' read -r remote options; do
    inst=system
    base="${FZX_PACKAGES_FLATPAK_SYSTEM:-/var/lib/flatpak}"
    if [[ ",$options," == *,user,* ]]; then
      inst=user
      base="${FZX_PACKAGES_FLATPAK_USER:-$HOME/.local/share/flatpak}"
    fi
    f="$base/appstream/$remote/$arch/active/appstream.xml"
    [[ -f "$f" ]] || f+=.gz
    [[ -f "$f" ]] && printf '%s\t%s\t%s\n' "$inst" "$remote" "$f"
  done < <(command flatpak remotes --columns=name,options 2> /dev/null)
}

# packages::_appstream <installation> <remote> <file>: "app<TAB>name<TAB>version<TAB>summary<TAB>remote
# <TAB>installation<TAB>developer<TAB>license<TAB>homepage<TAB>description" for each application, the
# description's paragraphs and list items joined by \x1f
packages::_appstream() {
  local inst="$1" remote="$2" file="$3"
  { if [[ "$file" == *.gz ]]; then command gzip -dc -- "$file"; else cat -- "$file"; fi; } |
    LC_ALL=C awk -v inst="$inst" -v remote="$remote" '
      BEGIN { RS = "</component>" }
      function tag(rec, t,   s) {
        if (!match(rec, "<" t ">[^<]*</" t ">")) return ""
        s = substr(rec, RSTART + length(t) + 2, RLENGTH - 2 * length(t) - 5); return unent(s)
      }
      function unent(s) { gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;|&#39;/, "\047", s); gsub(/&amp;/, "\\&", s); return s }
      {
        if (!match($0, />app\/[^<]*</)) next
        split(substr($0, RSTART + 5, RLENGTH - 6), ref, "/"); app = ref[1]
        ver = ""; if (match($0, /<release [^>]*version="[^"]*"/)) { ver = substr($0, RSTART, RLENGTH); sub(/.*version="/, "", ver); sub(/"$/, "", ver) }
        home = ""; if (match($0, /<url type="homepage">[^<]*</)) { home = substr($0, RSTART + 21, RLENGTH - 22) }
        desc = ""
        if (match($0, /<description>([^<]|<[^\/]|<\/[^d])*<\/description>/)) {
          desc = substr($0, RSTART + 13, RLENGTH - 27)
          gsub(/[ \t\r\n]+/, " ", desc); gsub(/<li> */, "• ", desc); gsub(/ *<\/(p|li)> */, "\037", desc)
          gsub(/<[^>]*>/, "", desc); gsub(/\037 +/, "\037", desc); sub(/^ +/, "", desc); sub(/\037+$/, "", desc); desc = unent(desc)
        }
        gsub(/\t/, " ", desc)
        print app "\t" tag($0, "name") "\t" ver "\t" tag($0, "summary") "\t" remote "\t" inst "\t" tag($0, "developer_name") "\t" tag($0, "project_license") "\t" unent(home) "\t" desc
      }'
}

# packages::flatpak_available: the remotes' applications by name, installed ones marked
packages::flatpak_available() {
  local inst remote file stamp
  {
    command flatpak list --app --columns=application,installation 2> /dev/null | sed 's/^/I\t/'
    while IFS=$'\t' read -r inst remote file; do
      # ostree checks appstream data out with mtime 0: the active checkout's path (its commit) is the stamp
      stamp="$(readlink -f -- "$file")"
      packages::_cached "flatpak-$inst-$remote" "$stamp" packages::_appstream "$inst" "$remote" "$file"
    done < <(packages::flatpak_remotes)
  } | packages::_awk '
    $1 == "I" { inst[$2 "\t" $3] = 1; next }
    {
      label = $2 == "" ? $1 : $2
      icon = (($1 "\t" $6) in inst) ? on "●\033[0m" : off "○\033[0m"
      row(tolower(label), "flatpak:" $6 ":" $1 "@" $5, $1, icon, cell(v, $3, 16, 0) " " cell(d, $5, 10, 0) " " d $4 "\033[0m", label)
    }' | packages::_sorted
}

# packages::_search_<registry> <query> <limit>: "manager<TAB>name<TAB>version<TAB>summary" lines
packages::_search_crates() {
  local -
  set -o pipefail
  (cd / && command cargo search --color never --limit "$2" -- "$1" 2> /dev/null) | LC_ALL=C awk '
    /^[A-Za-z0-9_-]+ = "/ {
      name = $1; ver = $3; gsub(/"/, "", ver); desc = ""
      if ((i = index($0, "# ")) > 0) desc = substr($0, i + 2)
      print "cargo\t" name "\t" ver "\t" desc
    }'
}
packages::_search_npm() {
  local -
  set -o pipefail
  command pnpm search --json --search-limit "$2" -- "$1" 2> /dev/null |
    command jq -r '.[]? | ["pnpm", .name, (.version // ""), ((.description // "") | gsub("[\t\r\n]+"; " "))] | @tsv'
}
packages::_search_rubygems() {
  local -
  set -o pipefail
  packages::_curl "https://rubygems.org/api/v1/search.json?query=$(packages::_uri "$1")" |
    command jq -r --argjson n "$2" '.[:$n][] | ["gem", .name, (.version // ""), ((.info // "") | gsub("[\t\r\n]+"; " "))] | @tsv'
}
# PyPI has no search: the query as a package name, its details kept for the preview
packages::_search_pypi() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$ ]] || return 0
  local json name
  json="$(packages::_curl "https://pypi.org/pypi/$1/json")" || return 0
  name="$(command jq -r '.info.name // empty' <<< "$json")"
  [[ -n "$name" ]] && packages::_info_write pipx "$name" packages::_pypi_info <<< "$json"
  command jq -r '.info | ["pipx", .name, (.version // ""), ((.summary // "") | gsub("[\t\r\n]+"; " "))] | @tsv' <<< "$json"
}

# packages::_installed_names <manager>: the names installed with it, one per line
packages::_installed_names() {
  case "$1" in
    cargo) [[ -f "$(packages::_crates)" ]] && packages::cargo_installs | cut -f1 ;;
    pnpm) command pnpm ls -g --depth=0 --json 2> /dev/null | command jq -r '.[] | .dependencies // {} | keys[]' ;;
    gem) FZX_SORT=name packages::gem 2> /dev/null | cut -f2 ;;
    pipx) FZX_SORT=name packages::pipx 2> /dev/null | cut -f2 ;;
  esac
}

# packages::search_registries: the registries the search mode can ask here: "toggle<TAB>manager" lines
packages::search_registries() {
  command -v cargo > /dev/null && printf 'crates\tcargo\n'
  command -v pnpm > /dev/null && command -v jq > /dev/null && printf 'npm\tpnpm\n'
  command -v gem > /dev/null && command -v curl > /dev/null && command -v jq > /dev/null && printf 'rubygems\tgem\n'
  command -v pipx > /dev/null && command -v curl > /dev/null && command -v jq > /dev/null && printf 'pypi\tpipx\n'
  return 0
}

# packages::search: $FZF_QUERY in each registry whose toggle is on, in parallel; registry order kept (their
# relevance), installed ones marked. A registry that fails or times out is logged and left out.
packages::search() {
  local q="${FZF_QUERY:-}" limit="${FZX_PACKAGES_SEARCH_LIMIT:-20}" tmp toggle manager i=0
  q="${q#"${q%%[![:space:]]*}"}"
  q="${q%"${q##*[![:space:]]}"}"
  [[ -n "$q" ]] || return 0
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064  # the path is fixed now
  trap "rm -rf -- '$tmp'" RETURN
  local -a order=()
  while IFS=$'\t' read -r toggle manager; do
    [[ " ${FZX_TOGGLES-crates npm rubygems pypi} " == *" $toggle "* ]] || continue
    i=$((i + 1))
    order+=("$i")
    {
      "packages::_search_$toggle" "$q" "$limit" > "$tmp/$i" || printf 'packages: %s search failed\n' "$toggle" >&2
      packages::_installed_names "$manager" > "$tmp/$i.installed"
    } &
  done < <(packages::search_registries)
  wait
  for i in "${order[@]}"; do
    packages::_awk '
      FILENAME ~ /\.installed$/ { inst[$0] = 1; next }
      {
        id = ($1 == "gem" ? "gem:user:" : $1 ":") $2
        row("", id, $2, ($2 in inst) ? on "●\033[0m" : off "○\033[0m", cell(v, $3, 16, 0) " " cell(up, $1, 6, 0) " " d $4 "\033[0m")
      }' "$tmp/$i.installed" "$tmp/$i" | cut -f2-
  done
}

# packages::_info_file <manager> <name>
packages::_info_file() {
  local name="${2//\//%2F}"
  printf '%s' "$FZX_CACHE_DIR/packages/info/$1/$name"
}

# packages::_info_write <manager> <name> <fn>: fn's output (stdin passed on) into the info cache; nothing
# is written when fn fails or prints nothing
packages::_info_write() {
  local file tmp
  file="$(packages::_info_file "$1" "$2")"
  mkdir -p -- "${file%/*}"
  tmp="$(mktemp "$file.XXXXXX")"
  if "$3" "$2" > "$tmp" && [[ -s "$tmp" ]]; then
    mv -f -- "$tmp" "$file"
  else
    rm -f -- "$tmp"
    return 1
  fi
}

# packages::remote_info <manager> <name>: the package's details from the network, cached for
# FZX_PACKAGES_INFO_TTL seconds (default a day)
packages::remote_info() {
  local file age
  file="$(packages::_info_file "$1" "$2")"
  if [[ -f "$file" ]]; then
    age=$(($(date +%s) - $(stat -c %Y -- "$file")))
    ((age < ${FZX_PACKAGES_INFO_TTL:-86400})) && {
      cat -- "$file"
      return 0
    }
  fi
  case "$1" in
    snap) packages::_info_write snap "$2" packages::_snap_info ;;
    cargo) packages::_info_write cargo "$2" packages::_crate_info ;;
    pnpm) packages::_info_write pnpm "$2" packages::_npm_info ;;
    gem) packages::_info_write gem "$2" packages::_gem_info ;;
    pipx) packages::_curl "https://pypi.org/pypi/$2/json" | packages::_info_write pipx "$2" packages::_pypi_info ;;
    *) return 2 ;;
  esac || return 1
  cat -- "$file"
}

# info fetchers: <name> -> the info format (see the top of this file)
packages::_snap_info() {
  command snap info --color=never --unicode=never -- "$1" 2> /dev/null | LC_ALL=C awk -F ': *' '
    /^description: / { indesc = 1; next }
    indesc && /^  / { body = body substr($0, 3) "\n"; next }
    { indesc = 0 }
    /^channels:/ { inch = 1; next }
    inch && /^  latest\/stable:/ { n = split($0, f, / +/); ver = f[3]; if (f[n] == "classic") classic = 1; inch = 0 }
    /^[a-z-]+: / && !inch { k = $1; v = substr($0, length($1) + 3); sub(/^ +/, "", v); val[k] = v }
    END {
      if (!("name" in val)) exit 1
      print val["name"] "\t" ver
      split("summary publisher license store-url contact", keys, " ")
      for (i = 1; i in keys; i++) if (val[keys[i]] != "") print keys[i] "\t" val[keys[i]]
      if (classic) print "confinement\tclassic"
      printf "--\n%s", body
    }'
}
packages::_crate_info() {
  (cd / && command cargo info --color never -- "$1" 2> /dev/null) | LC_ALL=C awk '
    NR == 1 { name = $1; next }
    /^[a-z-]+: / && !kv { kv = 1 }
    !kv { body = body $0 "\n"; next }
    /^[a-z-]+: / { k = $0; sub(/:.*/, "", k); v = $0; sub(/^[^:]*: */, "", v); if (k == "version") ver = v; else if (k != "features") rows = rows k "\t" v "\n"; next }
    END { if (name == "") exit 1; printf "%s\t%s\n%s--\n%s", name, ver, rows, body }'
}
packages::_npm_info() {
  command pnpm view --json -- "$1" 2> /dev/null | command jq -r '
    ([.name, .version] | @tsv),
    (["license", (.license // "" | tostring)] | @tsv),
    (["homepage", (.homepage // "")] | @tsv),
    (["repository", (.repository | if type == "object" then .url else . end // "")] | @tsv),
    (["binaries", (.bin // {} | if type == "object" then keys | join(" ") else "" end)] | @tsv),
    (["dependencies", (.dependencies // {} | length | tostring)] | @tsv),
    "--", (.description // "")' 2> /dev/null | awk -F '\t' 'NR == 1 && $1 == "" { exit 1 } { print }'
}
packages::_gem_info() {
  packages::_curl "https://rubygems.org/api/v1/gems/$1.json" | command jq -r '
    ([.name, .version] | @tsv),
    (["licenses", (.licenses // [] | join(", "))] | @tsv),
    (["authors", (.authors // "")] | @tsv),
    (["homepage", (.homepage_uri // "")] | @tsv),
    (["source", (.source_code_uri // "")] | @tsv),
    (["downloads", (.downloads // "" | tostring)] | @tsv),
    "--", (.info // "")'
}
# PyPI's JSON on stdin
packages::_pypi_info() {
  command jq -r '.info |
    ([.name, .version] | @tsv),
    (["python", (.requires_python // "")] | @tsv),
    (["license", ((.license_expression // .license // "") | split("\n")[0])] | @tsv),
    (["homepage", (.home_page // .project_urls.Homepage // .project_url // "")] | @tsv),
    (["author", (.author // .author_email // "")] | @tsv),
    "--", (.summary // "")'
}

# packages::render_info: an info cache file on stdin as a preview: title, fields, description
packages::render_info() {
  local line name ver k v body=0
  IFS=$'\t' read -r name ver || return 1
  packages::_title "$name" "$ver"
  while IFS= read -r line; do
    if ((body)); then
      printf '%s\n' "$line"
    elif [[ "$line" == -- ]]; then
      body=1
      printf '\n'
    else
      IFS=$'\t' read -r k v <<< "$line"
      packages::_kv "$k" "$v"
    fi
  done
}
