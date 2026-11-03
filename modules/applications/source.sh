#!/usr/bin/env bash
# applications source: desktop entries (Type=Application) as rows "file  id  display  name  icon", by name.
# An entry's ID is its path under the applications directory with / as -; the first directory holding an ID
# wins (yours over the system's). $FZX_TOGGLES: hidden also lists NoDisplay and Hidden entries (dim).

# applications::dirs: the applications directories, highest precedence first
applications::dirs() {
  local d dirs=()
  if ((${#FZX_APPLICATIONS_DIRS[@]})); then
    dirs=("${FZX_APPLICATIONS_DIRS[@]}")
  else
    dirs=("${XDG_DATA_HOME:-$HOME/.local/share}/applications")
    local IFS=:
    for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs+=("$d/applications"); done
  fi
  for d in "${dirs[@]}"; do [[ -d "$d" ]] && printf '%s\n' "$d"; done
  return 0
}

# applications::_files: "path<TAB>id" per desktop file, directories in precedence order
applications::_files() {
  local d
  while IFS= read -r d; do
    command find -L "$d" -name '*.desktop' -type f -printf '%p\t%P\n' 2> /dev/null | sort |
      awk -F'\t' -v OFS='\t' '{ id = $2; gsub("/", "-", id); print $1, id }'
  done < <(applications::dirs)
}

# applications::entries: "file id name generic comment categories icon exec terminal hidden" per entry,
# the [Desktop Entry] group only, the first file of each ID
applications::entries() {
  applications::_files | awk -F'\t' -v OFS='\t' '
    function clean(s) { gsub(/\t/, " ", s); return s }
    {
      file = $1; id = $2
      if (id in seen) next
      seen[id] = 1
      grp = ""; type = ""; name = ""; gen = ""; com = ""; cat = ""; icon = ""; ex = ""; term = ""; hid = 0
      while ((getline line < file) > 0) {
        sub(/\r$/, "", line)
        if (line ~ /^\[/) { grp = line; continue }
        if (grp != "[Desktop Entry]") continue
        if (match(line, /^[A-Za-z0-9-]+[ ]*=/) == 0) continue
        k = substr(line, 1, RLENGTH); sub(/[ ]*=$/, "", k); v = substr(line, RLENGTH + 1); sub(/^[ ]+/, "", v)
        if (k == "Type") type = v
        else if (k == "Name") name = v
        else if (k == "GenericName") gen = v
        else if (k == "Comment") com = v
        else if (k == "Categories") cat = v
        else if (k == "Icon") icon = v
        else if (k == "Exec") ex = v
        else if (k == "Terminal") term = v
        else if ((k == "NoDisplay" || k == "Hidden") && v == "true") hid = 1
      }
      close(file)
      if (type != "Application" || name == "") next
      print file, id, clean(name), clean(gen), clean(com), clean(cat), clean(icon), clean(ex), term, hid
    }'
}

applications::source() {
  local show=0 c=$'\e['"${FZX_COLORS[applications_category]:-38;5;110}m" d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ " ${FZX_TOGGLES:-} " == *" hidden "* ]] && show=1
  [[ -n "${NO_COLOR+x}" ]] && c="" d="" r=""
  applications::entries | awk -F'\t' -v OFS='\t' -v show="$show" -v c="$c" -v d="$d" -v r="$r" '
    # the first registered main category in Categories
    function main_cat(c,   n, p, i) {
      n = split(c, p, ";")
      for (i = 1; i <= n; i++) if (p[i] ~ /^(AudioVideo|Audio|Video|Development|Education|Game|Graphics|Network|Office|Science|Settings|System|Utility)$/) return p[i]
      return n ? p[1] : ""
    }
    function pad(t, w) { return length(t) > w ? substr(t, 1, w - 1) "…" : sprintf("%-" w "s", t) }
    $10 == 1 && !show { next }
    {
      text = $5 != "" ? $5 : $4
      nm = $10 == 1 ? d pad($3, 32) r : pad($3, 32)
      print $1, $2, nm "  " c pad(main_cat($6), 12) r "  " d text r, $3, $7
    }' | sort -t$'\t' -k4,4f
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" applications
  applications::source "$@"
}
