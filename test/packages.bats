#!/usr/bin/env bats
# the packages module: apt (installed, available, upgradable), snap, flatpak, pipx, cargo, pnpm and gem,
# every manager stubbed

load test_helper

bats_require_minimum_version 1.5.0

MODS="$(readlink -f "$BATS_TEST_DIRNAME/../modules")"

setup() {
  setup_fzx
  export FZX_PACKAGES_APT_LISTS="$BATS_TEST_TMPDIR/lists" FZX_PACKAGES_DPKG_STATUS="$BATS_TEST_TMPDIR/status"
  export FZX_PACKAGES_EXTENDED_STATES="$BATS_TEST_TMPDIR/extended_states"
  export PIPX_HOME="$BATS_TEST_TMPDIR/pipx" CARGO_HOME="$BATS_TEST_TMPDIR/cargo"
  export FZX_PACKAGES_SNAP_NAMES="$BATS_TEST_TMPDIR/snap-names" FZX_PACKAGES_FLATPAK_SYSTEM="$BATS_TEST_TMPDIR/flatpak-system"
  export FZX_PACKAGES_FLATPAK_USER="$BATS_TEST_TMPDIR/flatpak-user"
  mkdir -p "$FZX_PACKAGES_APT_LISTS"
  : > "$FZX_PACKAGES_DPKG_STATUS"
}

# stub_cmd <name> <body>: an executable on PATH that logs "name args" to calls and runs <body>
stub_cmd() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${0##*/} $*" >> "$BATS_TEST_TMPDIR/calls"\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# only_stubs: PATH is the stubs and the core tools, so no real package manager is found
only_stubs() {
  local t dir="$BATS_TEST_TMPDIR/core"
  mkdir -p "$dir" "$BATS_TEST_TMPDIR/bin"
  for t in bash env awk gawk mawk sort cut mktemp stat cat readlink dirname grep sed mkdir mv rm tr head tail wc date jq chmod ln touch fold; do
    command -v "$t" > /dev/null && ln -sf "$(command -v "$t")" "$dir/$t"
  done
  export PATH="$BATS_TEST_TMPDIR/bin:$dir"
}

plain() { sed 's/\x1b\[[0-9;:]*m//g'; }
ids() { printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' '; }

stub_apt() {
  stub_cmd dpkg-query 'case "$*" in
    "-W -f \${db:Status-Abbrev}\t\${binary:Package}\t"*) printf "ii \tzsh\t5.9-8\t2500\tshell with lots of features\nii \tlibfoo1\t1.2-1\t120\tfoo library\nrc \tgone\t1.0\t10\tremoved, config left\nhi \tpinned\t2.0\t4096\theld one\n" ;;
    "-W -f \${db:Status-Abbrev}\t\${Package}"*) printf "ii \tzsh\nii \tlibfoo1\nrc \tgone\nhi \tpinned\n" ;;
    "-s -- zsh") printf "Package: zsh\nStatus: install ok installed\nSection: shells\nInstalled-Size: 2500\nVersion: 5.9-8\nHomepage: https://zsh.org\nDescription: shell with lots of features\n Zsh is a UNIX command interpreter.\n .\n It has many features.\n" ;;
    "-s -- "*) exit 1 ;;
    "-L -- zsh") printf "/bin\n/bin/zsh\n/usr/bin/zsh5\n/usr/share/doc/zsh\n" ;;
  esac'
  stub_cmd apt-cache 'printf "zsh - shell with lots of features\nfish - friendly interactive shell\nlibfoo1 - foo library\n"'
  stub_cmd apt 'printf "Listing...\nzsh/noble-updates 5.9-9 amd64 [upgradable from: 5.9-8]\n"'
  stub_cmd dpkg 'case "$1" in
    --print-architecture) echo amd64 ;;
    --compare-versions) [[ "$(printf "%s\n%s\n" "$2" "$4" | sort -V | tail -1)" == "$2" && "$2" != "$4" ]] ;;
  esac'
  printf 'Package: libfoo1\nArchitecture: amd64\nAuto-Installed: 1\n\nPackage: zsh\nArchitecture: amd64\nAuto-Installed: 0\n' > "$FZX_PACKAGES_EXTENDED_STATES"
}

@test "packages: a mode per manager on PATH, apt's three first; apt's toggle, sort and actions only with apt" {
  only_stubs
  run "$MODS/packages/components.tsv"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | awk -F '\t' '$1 == "mode"' | wc -l)" -eq 0 ]
  [[ "$output" != *manual* && "$output" != *install* && "$output" != *purge* ]]
  [[ "$output" == *$'action\tremove\talt-x'* ]]
  stub_cmd snap :
  stub_cmd gem :
  run "$MODS/packages/components.tsv"
  [ "$(printf '%s\n' "${lines[@]}" | awk -F '\t' '$1 == "mode" { printf "%s:%s ", $2, $5 }')" = "snap:default gem:- " ]
  stub_apt
  run "$MODS/packages/components.tsv"
  [ "$(printf '%s\n' "${lines[@]}" | awk -F '\t' '$1 == "mode" { printf "%s:%s ", $2, $5 }')" = "apt:default available:- upgradable:- snap:- gem:- " ]
  [[ "$output" == *$'toggle\tmanual\talt-m'* && "$output" == *$'sort\tsize'* && "$output" == *$'action\tinstall\talt-i\tavailable: install'* ]]
  # cargo needs its install record, pipx and pnpm jq
  stub_cmd cargo :
  run "$MODS/packages/components.tsv"
  [[ "$output" != *$'mode\tcargo'* ]]
  mkdir -p "$CARGO_HOME" && echo '{"installs":{}}' > "$CARGO_HOME/.crates2.json"
  run "$MODS/packages/components.tsv"
  [[ "$output" == *$'mode\tcargo'* ]]
  # cargo can search crates.io: the search mode, its toggle, and install there; the name sort leaves it out
  [[ "$output" == *$'mode\tsearch\t-\t'*$'\tnopersist'* && "$output" == *$'toggle\tcrates\t-\tsearch: crates.io (cargo)\ton'* ]]
  [[ "$output" == *$'action\tinstall\talt-i\tavailable, search: install'* ]]
  [[ "$output" == *$'sort\tname\t-\tapt, available, upgradable, snap, cargo, gem: by name'* ]]
  # the catalogs when there is something to list
  echo yq > "$FZX_PACKAGES_SNAP_NAMES"
  run "$MODS/packages/components.tsv"
  [[ "$output" == *$'mode\tsnap-available'* && "$output" == *"available, snap-available, search: install"* ]]
}

@test "packages: apt lists installed packages: dependencies dim, held ones marked, removed ones left out" {
  stub_apt
  run "$MODS/packages/source.sh"
  [ "$status" -eq 0 ]
  [ "$(ids)" = "apt:libfoo1 apt:pinned apt:zsh " ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -f2 | tr '\n' ' ')" = "libfoo1 pinned zsh " ]
  [[ "$(printf '%s\n' "${lines[2]}" | plain)" == *"● zsh"*"5.9-8"*"2M"*"shell with lots of features"* ]]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"○ libfoo1"*"120K"* ]]
  [[ "$(printf '%s\n' "${lines[1]}" | plain)" == *"⏸ pinned"*"4M"* ]]
  # the name column is the sorted one
  [[ "${lines[2]}" == *$'\e[4mzsh\e[0m'* ]]
  FZX_TOGGLES=manual run "$MODS/packages/source.sh"
  [ "$(ids)" = "apt:pinned apt:zsh " ]
  FZX_SORT=size run "$MODS/packages/source.sh"
  [ "$(ids)" = "apt:pinned apt:zsh apt:libfoo1 " ]
  [[ "${lines[0]}" == *$'\e[4m4M\e[0m'* ]]
}

@test "packages: a header row (FZX_SORTED_SHOW=header) over apt's columns, the sorted one marked" {
  stub_apt
  export FZX_SORTED_SHOW=header FZX_SORT_HEADER=1 FZX_SORTED_ARROWS='^ v'
  FZX_SORT=size FZX_SORT_DESC=1 run "$MODS/packages/source.sh"
  [[ "${lines[0]}" == $'\t\t  NAME '*'VERSION '*$'\e[1;38;2;0;215;255mSIZEv\e[0m  DESCRIPTION' && "${lines[1]}" != *$'\e[4m'* ]]
  header_aligned 2 "${lines[0]}" VERSION "${lines[2]}" 5.9
  header_aligned 2 "${lines[0]}" SIZEv "${lines[2]}" "2M "
  header_aligned 2 "${lines[0]}" DESCRIPTION "${lines[2]}" shell
  FZX_MODE=upgradable run "$MODS/packages/source.sh"
  [[ "${lines[0]}" == $'\t\t  \e[1;38;2;0;215;255mNAME^\e[0m'*INSTALLED*CANDIDATE*SUITE ]]
}

@test "packages: available is cached until apt's lists change; installed ones marked on every run" {
  stub_apt
  FZX_MODE=available run "$MODS/packages/source.sh"
  [ "$status" -eq 0 ]
  [ "$(ids)" = "apt:fish apt:libfoo1 apt:zsh " ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"○ fish"*"friendly interactive shell"* ]]
  [[ "$(printf '%s\n' "${lines[2]}" | plain)" == *"● zsh"* ]]
  [ "$(grep -c '^apt-cache ' "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
  FZX_MODE=available run "$MODS/packages/source.sh"
  [ "$(ids)" = "apt:fish apt:libfoo1 apt:zsh " ]
  [ "$(grep -c '^apt-cache ' "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
  touch -d '+1 minute' "$FZX_PACKAGES_APT_LISTS"
  FZX_MODE=available run "$MODS/packages/source.sh"
  [ "$(grep -c '^apt-cache ' "$BATS_TEST_TMPDIR/calls")" -eq 2 ]
  # a failing apt-cache leaves the cache alone
  stub_cmd apt-cache 'exit 3'
  touch -d '+2 minutes' "$FZX_PACKAGES_APT_LISTS"
  FZX_MODE=available run "$MODS/packages/source.sh"
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$FZX_CACHE_DIR/packages/available")" -eq 3 ]
}

@test "packages: upgradable shows installed and candidate versions, cached until the lists or dpkg change" {
  stub_apt
  FZX_MODE=upgradable run "$MODS/packages/source.sh"
  [ "$status" -eq 0 ]
  [ "$(ids)" = "apt:zsh " ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"↑ zsh"*"5.9-8"*"5.9-9"*"noble-updates"* ]]
  FZX_MODE=upgradable run "$MODS/packages/source.sh"
  [ "$(grep -c '^apt list' "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
  touch -d '+1 minute' "$FZX_PACKAGES_DPKG_STATUS"
  FZX_MODE=upgradable run "$MODS/packages/source.sh"
  [ "$(grep -c '^apt list' "$BATS_TEST_TMPDIR/calls")" -eq 2 ]
}

@test "packages: snap, flatpak (runtimes with the toggle), pipx, cargo, pnpm and gem" {
  stub_cmd snap 'printf "Name  Version  Rev  Tracking  Publisher  Notes\nyq  4.40  2  latest/stable  mikefarah*  -\ncore22  2024  1  latest/stable  canonical**  base\n"'
  FZX_MODE=snap run "$MODS/packages/source.sh"
  [ "$(ids)" = "snap:core22 snap:yq " ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"core22"*"2024"*"latest/stable"*"canonical "*"base"* ]]

  stub_cmd flatpak 'printf "org.a.App\tA App\t1.0\tsystem\tflathub\n"; [[ "$*" == *--app* ]] || printf "org.gtk.Gtk3theme\t\t\tuser\tflathub\n"'
  FZX_MODE=flatpak run "$MODS/packages/source.sh"
  [ "$(ids)" = "flatpak:system:org.a.App " ]
  [ "$(printf '%s\n' "${lines[0]}" | cut -f2)" = "org.a.App" ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"A App"*"1.0"*"system"*"org.a.App"* ]]
  FZX_MODE=flatpak FZX_TOGGLES=runtimes run "$MODS/packages/source.sh"
  [ "$(ids)" = "flatpak:system:org.a.App flatpak:user:org.gtk.Gtk3theme " ]

  stub_cmd pipx :
  mkdir -p "$PIPX_HOME/venvs/black"
  echo '{"main_package":{"package":"black","package_version":"24.1","apps":["black","blackd"]}}' > "$PIPX_HOME/venvs/black/pipx_metadata.json"
  FZX_MODE=pipx run "$MODS/packages/source.sh"
  [ "$(ids)" = "pipx:black " ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"black"*"24.1"*"black blackd"* ]]

  stub_cmd cargo :
  mkdir -p "$CARGO_HOME"
  cat > "$CARGO_HOME/.crates2.json" << 'EOF'
{"installs":{"ripgrep 14.1.0 (registry+https://github.com/rust-lang/crates.io-index)":{"bins":["rg"]},
"alacritty 0.18.1-dev (git+ssh://git@github.com/me/alacritty?branch=font#16ac586)":{"bins":["alacritty"]},
"mine 0.1.0 (path+file:///home/me/mine)":{"bins":["mine"]}}}
EOF
  FZX_MODE=cargo run "$MODS/packages/source.sh"
  [ "$(ids)" = "cargo:alacritty cargo:mine cargo:ripgrep " ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"0.18.1-dev"*"github.com/me/alacritty (branch=font)"*"alacritty"* ]]
  [[ "$(printf '%s\n' "${lines[1]}" | plain)" == *"/home/me/mine"* ]]
  [[ "$(printf '%s\n' "${lines[2]}" | plain)" == *"14.1.0"*"crates.io"*"rg"* ]]

  stub_cmd pnpm 'echo "[{\"dependencies\":{\"typescript\":{\"version\":\"5.4.0\",\"path\":\"/x\"},\"@scope/tool\":{\"version\":\"1.0.0\"}}}]"'
  FZX_MODE=pnpm run "$MODS/packages/source.sh"
  [ "$(ids)" = "pnpm:@scope/tool pnpm:typescript " ]

  stub_cmd gem :
  local u="$BATS_TEST_TMPDIR/gems/user/3.3.0" s="$BATS_TEST_TMPDIR/gems/system/3.3.0"
  mkdir -p "$u/specifications" "$s/specifications"
  printf '  s.summary = "Rack test helpers".freeze\n' > "$u/specifications/rack-test-2.1.0.gemspec"
  printf '  s.summary = "A web server interface".freeze\n' > "$u/specifications/rack-3.0.0.gemspec"
  : > "$u/specifications/rack-3.1.0.gemspec"
  : > "$s/specifications/nokogiri-1.16.0-x86_64-linux.gemspec"
  export FZX_GEMS="user:$BATS_TEST_TMPDIR/gems/user/* system:$BATS_TEST_TMPDIR/gems/system/*"
  FZX_MODE=gem run bash -c 'FZX_PACKAGES_GEM_DIRS=($FZX_GEMS); source "$1"; packages::source' _ "$MODS/packages/source.sh"
  [ "$status" -eq 0 ]
  [ "$(ids)" = "gem:system:nokogiri gem:user:rack gem:user:rack-test " ]
  [[ "$(printf '%s\n' "${lines[1]}" | plain)" == *"rack"*"3.0.0, 3.1.0"*"user"*"A web server interface"* ]]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"nokogiri"*"1.16.0 "*"system"* ]]
}

@test "packages: a manager that is not installed, and an unknown mode, fail" {
  only_stubs
  FZX_MODE=snap run --separate-stderr "$MODS/packages/source.sh"
  [ "$status" -eq 1 ]
  [ "$stderr" = "packages: snap is not installed" ]
  FZX_MODE=bogus run --separate-stderr "$MODS/packages/source.sh"
  [ "$status" -eq 2 ]
  [ "$stderr" = "packages: unknown mode: bogus" ]
}

@test "packages: apt preview: an installed package from dpkg with its upgrade and commands" {
  stub_apt
  FZX_MODE=upgradable "$MODS/packages/source.sh" > /dev/null
  run "$MODS/packages/preview.sh" apt:zsh
  [ "$status" -eq 0 ]
  local out
  out="$(printf '%s\n' "$output" | plain)"
  [[ "$out" == "zsh  5.9-8"* ]]
  [[ "$out" == *"installed    5.9-8"*"upgrade      5.9-9"*"section      shells"*"size         2M"*"homepage     https://zsh.org"* ]]
  [[ "$out" == *"shell with lots of features"$'\n'"Zsh is a UNIX command interpreter."$'\n\n'"It has many features."* ]]
  [[ "$out" == *"commands"$'\n'"zsh zsh5" ]]
  [[ "$(cat "$BATS_TEST_TMPDIR/calls")" != *apt-cache* ]]
}

@test "packages: apt preview: another package from the lists, the highest version for this architecture" {
  stub_apt
  printf 'Package: fish\nArchitecture: amd64\nVersion: 3.7.0-1\nSection: shells\nDescription: friendly shell\nDescription-md5: x\n\nPackage: other\nVersion: 1\n' > "$FZX_PACKAGES_APT_LISTS/a_main_binary-amd64_Packages"
  printf 'Package: fish\nArchitecture: amd64\nVersion: 3.7.1-1\nSection: shells\nDescription: friendly shell\n' > "$FZX_PACKAGES_APT_LISTS/b_updates_binary-amd64_Packages"
  printf 'Package: fish\nArchitecture: i386\nVersion: 9.0\nDescription: friendly shell\n' > "$FZX_PACKAGES_APT_LISTS/c_binary-i386_Packages"
  printf 'Package: fish\nDescription-md5: x\nDescription-en: friendly shell\n fish is a shell.\n\nPackage: zzz\n' > "$FZX_PACKAGES_APT_LISTS/a_main_i18n_Translation-en"
  run "$MODS/packages/preview.sh" apt:fish
  [ "$status" -eq 0 ]
  local out
  out="$(printf '%s\n' "$output" | plain)"
  [[ "$out" == "fish  3.7.1-1"* ]]
  [[ "$out" == *"installed    not installed"* ]]
  [[ "$out" == *"friendly shell"$'\n'"fish is a shell." ]]
  [[ "$out" != *commands* ]]
  run "$MODS/packages/preview.sh" apt:nothere
  [ "$output" = "apt: no package nothere" ]
}

@test "packages: previews of the other managers, read locally" {
  stub_cmd snap 'echo "name: yq"'
  stub_cmd flatpak 'echo "ID: org.a.App"'
  run "$MODS/packages/preview.sh" snap:yq
  [ "$(printf '%s\n' "$output" | plain)" = "name: yq" ]
  run "$MODS/packages/preview.sh" flatpak:user:org.a.App
  [ "$(printf '%s\n' "$output" | plain)" = "ID: org.a.App" ]
  grep -qx 'snap info --color=never --unicode=never -- yq' "$BATS_TEST_TMPDIR/calls"
  grep -qx 'flatpak info --user -- org.a.App' "$BATS_TEST_TMPDIR/calls"

  mkdir -p "$PIPX_HOME/venvs/black/lib/python3.12/site-packages/Black-24.1.dist-info"
  echo '{"main_package":{"package":"black","package_version":"24.1","apps":["black"]},"python_version":"Python 3.12"}' > "$PIPX_HOME/venvs/black/pipx_metadata.json"
  printf 'Name: black\nSummary: The formatter\nHome-page: https://black\n\nlong text\n' > "$PIPX_HOME/venvs/black/lib/python3.12/site-packages/Black-24.1.dist-info/METADATA"
  run "$MODS/packages/preview.sh" pipx:black
  [[ "$(printf '%s\n' "$output" | plain)" == "black  24.1"*"apps         black"*"python       Python 3.12"*"summary      The formatter"*"home-page    https://black" ]]

  mkdir -p "$CARGO_HOME/registry/src/index-1/ripgrep-14.1.0"
  echo '{"installs":{"ripgrep 14.1.0 (registry+https://x)":{"bins":["rg"],"features":["pcre2"],"profile":"release"}}}' > "$CARGO_HOME/.crates2.json"
  printf '[package]\nname = "ripgrep"\ndescription = """\nfast\ngrep\n"""\nlicense = "MIT"\n[dependencies]\ndescription = "no"\n' > "$CARGO_HOME/registry/src/index-1/ripgrep-14.1.0/Cargo.toml"
  run "$MODS/packages/preview.sh" cargo:ripgrep
  local out
  out="$(printf '%s\n' "$output" | plain)"
  [[ "$out" == "ripgrep  14.1.0"*"binaries     rg"*"features     pcre2"*"description  fast grep"$'\n'"license      MIT" ]]

  mkdir -p "$BATS_TEST_TMPDIR/nm/typescript"
  echo '{"version":"5.4.0","description":"TS","bin":{"tsc":"x","tsserver":"y"}}' > "$BATS_TEST_TMPDIR/nm/typescript/package.json"
  stub_cmd pnpm "echo '[{\"dependencies\":{\"typescript\":{\"version\":\"5.4.0\",\"path\":\"$BATS_TEST_TMPDIR/nm/typescript\"}}}]'"
  run "$MODS/packages/preview.sh" pnpm:typescript
  [[ "$(printf '%s\n' "$output" | plain)" == "typescript  5.4.0"*"description  TS"*"binaries     tsc tsserver"* ]]

  run "$MODS/packages/preview.sh" nothing
  [ "$status" -eq 1 ]
  run "$MODS/packages/preview.sh" brew:x
  [ "$status" -eq 1 ]
}

@test "packages: actions group the selection by manager; apt and snap through sudo, flatpak by installation" {
  [[ "$EUID" -ne 0 ]] || skip "root needs no sudo"
  stub_cmd sudo '"$@"'
  stub_cmd apt :
  stub_cmd snap :
  stub_cmd flatpak :
  stub_cmd pnpm :
  run "$MODS/packages/actions.sh" install apt:fish apt:zsh
  [ "$status" -eq 0 ]
  run "$MODS/packages/actions.sh" upgrade apt:zsh snap:yq flatpak:system:org.a.App flatpak:user:org.b.App apt:fish pnpm:typescript
  [ "$status" -eq 0 ]
  run "$MODS/packages/actions.sh" remove snap:yq flatpak:user:org.b.App <<< yy
  run "$MODS/packages/actions.sh" purge apt:zsh < /dev/null
  run cat "$BATS_TEST_TMPDIR/calls"
  [ "${lines[0]}" = "sudo apt install fish zsh" ]
  [ "${lines[1]}" = "apt install fish zsh" ]
  [ "${lines[2]}" = "sudo apt install --only-upgrade zsh fish" ]
  [ "${lines[4]}" = "sudo snap refresh yq" ]
  [ "${lines[6]}" = "flatpak update --system org.a.App" ]
  [ "${lines[7]}" = "flatpak update --user org.b.App" ]
  [ "${lines[8]}" = "pnpm update -g --latest typescript" ]
  [ "${lines[9]}" = "sudo snap remove yq" ]
  [ "${lines[11]}" = "flatpak uninstall --user org.b.App" ]
  [ "${lines[12]}" = "sudo apt purge zsh" ]
}

@test "packages: remove asks first, except apt's (apt asks itself); no keeps the packages" {
  stub_cmd sudo '"$@"'
  stub_cmd apt :
  stub_cmd pipx :
  stub_cmd cargo :
  run "$MODS/packages/actions.sh" remove pipx:black cargo:rg <<< ny
  [ "$status" -eq 0 ]
  [[ "$(printf "%s\n" "$output" | plain)" == *"remove (pipx): black"*"[y/N]"*"remove (cargo): rg"* ]]
  run "$MODS/packages/actions.sh" remove apt:zsh < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" != *"[y/N]"* ]]
  run grep -v '^sudo ' "$BATS_TEST_TMPDIR/calls"
  [ "$output" = $'cargo uninstall rg\napt remove zsh' ]
}

@test "packages: cargo reinstalls from where a crate came from; gems through sudo only when their home is not writable" {
  stub_cmd cargo :
  mkdir -p "$CARGO_HOME"
  echo '{"installs":{"rg 14 (registry+https://x)":{},"ala 0.1 (git+ssh://git@github.com/me/ala?branch=font#abc)":{},"pin 1 (git+https://h/p?rev=abc#abc)":{},"mine 0.1 (path+file:///src/mine)":{}}}' > "$CARGO_HOME/.crates2.json"
  run "$MODS/packages/actions.sh" upgrade cargo:rg cargo:ala cargo:pin cargo:mine
  [ "$status" -eq 0 ]
  run cat "$BATS_TEST_TMPDIR/calls"
  [ "${lines[0]}" = "cargo install rg" ]
  [ "${lines[1]}" = "cargo install --git ssh://git@github.com/me/ala --branch font ala" ]
  [ "${lines[2]}" = "cargo install --git https://h/p --rev abc pin" ]
  [ "${lines[3]}" = "cargo install --path /src/mine mine" ]
  run "$MODS/packages/actions.sh" upgrade cargo:unknown
  [ "$status" -eq 1 ]

  [[ "$EUID" -ne 0 ]] || skip "root writes everywhere"
  : > "$BATS_TEST_TMPDIR/calls"
  stub_cmd sudo '"$@"'
  stub_cmd gem :
  local u="$BATS_TEST_TMPDIR/gems/user" s="$BATS_TEST_TMPDIR/gems/system"
  mkdir -p "$u/specifications" "$s/specifications"
  : > "$u/specifications/rake-13.0.gemspec"
  : > "$s/specifications/rake-12.0.gemspec"
  chmod a-w "$s"
  run bash -c 'FZX_PACKAGES_GEM_DIRS=("user:$1" "system:$2"); source "$3"; packages::action upgrade gem:user:rake gem:system:rake; packages::action remove gem:user:rake' \
    _ "$u" "$s" "$MODS/packages/actions.sh" <<< y
  chmod u+w "$s"
  [ "$status" -eq 0 ]
  run cat "$BATS_TEST_TMPDIR/calls"
  [ "${lines[0]}" = "gem update -i $u rake" ]
  [ "${lines[1]}" = "sudo gem update -i $s rake" ]
  [ "${lines[3]}" = "gem uninstall -a -x -i $u rake" ]
}

@test "packages: an action that does not apply, bad ids and unknown actions fail" {
  run --separate-stderr "$MODS/packages/actions.sh" purge snap:yq < /dev/null
  [ "$status" -eq 2 ]
  [ "$stderr" = "snap: purge does not apply" ]
  run "$MODS/packages/actions.sh" remove < /dev/null
  [ "$status" -eq 2 ]
  run "$MODS/packages/actions.sh" remove yq < /dev/null
  [ "$status" -eq 2 ]
  run "$MODS/packages/actions.sh" explode apt:zsh < /dev/null
  [ "$status" -eq 2 ]
}

@test "packages: action keys bound and in the header; enter prints names; copy copies names" {
  stub_apt
  stub_fzf
  run "$FZX" -m packages
  [ "$status" -eq 0 ]
  [[ "$(fzf_bind alt-i)" == "alt-i:execute($FZX _cb action install {+1})"*"reload($FZX _cb source)" ]]
  [[ "$(fzf_bind alt-x)" == *"_cb action remove {+1}"* ]]
  [[ "$(fzf_bind alt-m)" == *'_cb toggle manual'* ]]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --header=alt-i install  alt-u upgrade  alt-x remove "* ]]
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=2 "* && " ${FZF_ARGS[*]} " == *" --with-nth=3 "* ]]
}

@test "packages: menu entries follow the managers on PATH; summaries count installed packages" {
  load_libs log config menu
  only_stubs
  stub_apt
  stub_cmd snap 'printf "Name  Version\nyq  4\n"'
  fzx::menu_entries packages "$FZX_REPO/modules/packages"
  packages::applicable packages
  packages::applicable packages:available
  packages::applicable packages:snap
  run packages::applicable packages:flatpak
  [ "$status" -ne 0 ]
  [ "$(packages::summary packages)" = "3 installed" ]
  [ "$(packages::summary packages:snap)" = "1 installed" ]
  [ -z "$(packages::summary packages:available)" ]
  FZX_MODE=available "$MODS/packages/source.sh" > /dev/null
  [ "$(packages::summary packages:available)" = "3 packages" ]
}

# stub_flatpak: a system remote "hub" with appstream data for two applications, one of them installed
stub_flatpak() {
  stub_cmd flatpak 'case "$1" in
    --default-arch) echo x86_64 ;;
    remotes) printf "hub\tsystem\nempty\tsystem\n" ;;
    list) printf "org.a.App\tsystem\n" ;;
    info) [[ "$*" == *org.a.App* ]] && echo "ID: org.a.App" || exit 1 ;;
  esac'
  local d="$FZX_PACKAGES_FLATPAK_SYSTEM/appstream/hub/x86_64/active"
  mkdir -p "$d"
  cat > "$d/appstream.xml" << 'XML'
<components>
  <component type="desktop-application">
    <id>org.a.App</id>
    <name>A App</name>
    <name xml:lang="de">Eine App</name>
    <summary>Does a</summary>
    <bundle type="flatpak" runtime="r">app/org.a.App/x86_64/stable</bundle>
    <releases><release version="1.2" timestamp="1"/></releases>
  </component><component type="desktop-application">
    <id>org.b.Bee</id>
    <name>Bee &amp; Co</name>
    <summary>Buzzes</summary>
    <developer_name>Hive</developer_name>
    <project_license>MIT</project_license>
    <url type="homepage">https://bee</url>
    <description xml:lang="de"><p>Summt</p></description>
    <description>
      <p>Bee buzzes.</p>
      <ul><li>One</li><li>Two</li></ul>
    </description>
    <bundle type="flatpak">app/org.b.Bee/x86_64/stable</bundle>
  </component><component type="runtime">
    <id>org.r.Runtime</id>
    <bundle type="flatpak">runtime/org.r.Runtime/x86_64/1</bundle>
  </component>
</components>
XML
}

@test "packages: snap-available lists snapd's names, installed ones marked" {
  printf 'yq\nzz\naa\n' > "$FZX_PACKAGES_SNAP_NAMES"
  stub_cmd snap 'printf "Name  Version\nyq  4\n"'
  FZX_MODE=snap-available run "$MODS/packages/source.sh"
  [ "$status" -eq 0 ]
  [ "$(ids)" = "snap:yq snap:zz snap:aa " ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == "snap:yq"*"● yq"* && "$(printf '%s\n' "${lines[1]}" | plain)" == *"○ zz"* ]]
  rm "$FZX_PACKAGES_SNAP_NAMES"
  FZX_MODE=snap-available run --separate-stderr "$MODS/packages/source.sh"
  [ "$status" -eq 1 ]
}

@test "packages: flatpak-available reads the remotes' appstream applications, cached by the checkout" {
  stub_flatpak
  FZX_MODE=flatpak-available run "$MODS/packages/source.sh"
  [ "$status" -eq 0 ]
  [ "$(ids)" = "flatpak:system:org.a.App@hub flatpak:system:org.b.Bee@hub " ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"● A App"*"1.2"*"hub"*"Does a"* ]]
  [[ "$(printf '%s\n' "${lines[1]}" | plain)" == *"○ Bee & Co"*"Buzzes"* ]]
  # the cache holds the details the preview shows
  [ "$(cut -f7-10 "$FZX_CACHE_DIR/packages/flatpak-system-hub" | sed -n 2p)" = $'Hive\tMIT\thttps://bee\tBee buzzes.\x1f• One\x1f• Two' ]
  # a new checkout (the active link moves) rebuilds it
  printf 'stale\tStale\t\t\thub\tsystem\n' > "$FZX_CACHE_DIR/packages/flatpak-system-hub"
  FZX_MODE=flatpak-available run "$MODS/packages/source.sh"
  [ "$(ids)" = "flatpak:system:stale@hub " ]
  local base="$FZX_PACKAGES_FLATPAK_SYSTEM/appstream/hub/x86_64"
  mv "$base/active" "$base/abc123"
  ln -s abc123 "$base/active"
  FZX_MODE=flatpak-available run "$MODS/packages/source.sh"
  [ "$(ids)" = "flatpak:system:org.a.App@hub flatpak:system:org.b.Bee@hub " ]
}

@test "packages: a flatpak not installed is previewed from its appstream entry; an installed one by flatpak info" {
  stub_flatpak
  FZX_MODE=flatpak-available "$MODS/packages/source.sh" > /dev/null
  run "$MODS/packages/preview.sh" flatpak:system:org.b.Bee@hub
  local out
  out="$(printf '%s\n' "$output" | plain)"
  [[ "$out" == "Bee & Co"*"installed    not installed"*"remote       hub (system)"*"developer    Hive"*"license      MIT"* ]]
  [[ "$out" == *"Buzzes"$'\n'"Bee buzzes."$'\n\n'"• One"$'\n\n'"• Two" ]]
  run "$MODS/packages/preview.sh" flatpak:system:org.a.App@hub
  [ "$(printf '%s\n' "$output" | plain)" = "ID: org.a.App" ]
}

# stub_registries: cargo, pnpm and curl (rubygems.org, PyPI) answering a search for "fmt"
stub_registries() {
  stub_cmd cargo 'case "$1" in
    search) printf "fmtlib = \"1.0.0\"    # formats things\nfmt2 = \"0.2.0\"\n... and 40 crates more (use --limit N to see more)\n" ;;
    info) printf "fmtlib #fmt\nformats things\nwell\nversion: 1.0.0\nlicense: MIT\nfeatures:\n  default\n" ;;
  esac'
  stub_cmd pnpm 'case "$1" in
    search) echo "[{\"name\":\"fmt-js\",\"version\":\"2.0.0\",\"description\":\"js\\tformat\"}]" ;;
    ls) echo "[{\"dependencies\":{\"fmt-js\":{\"version\":\"2.0.0\"}}}]" ;;
    view) echo "{\"name\":\"fmt-js\",\"version\":\"2.0.0\",\"license\":\"MIT\",\"description\":\"js format\"}" ;;
  esac'
  stub_cmd gem :
  stub_cmd pipx :
  stub_cmd curl 'url="${@: -1}"; case "$url" in
    *rubygems.org/api/v1/search.json?query=fmt) echo "[{\"name\":\"fmt-rb\",\"version\":\"3.0\",\"info\":\"ruby\\nformat\"}]" ;;
    *rubygems.org/api/v1/gems/fmt-rb.json) echo "{\"name\":\"fmt-rb\",\"version\":\"3.0\",\"info\":\"ruby format\",\"licenses\":[\"MIT\"]}" ;;
    *pypi.org/pypi/fmt/json) echo "{\"info\":{\"name\":\"fmt\",\"version\":\"0.9\",\"summary\":\"py format\",\"requires_python\":\">=3.9\"}}" ;;
    *) exit 22 ;;
  esac'
}

@test "packages: search asks each registry whose toggle is on, in registry order; installed ones marked" {
  stub_registries
  FZX_MODE=search FZF_QUERY='  fmt ' run --separate-stderr "$MODS/packages/source.sh"
  [ "$status" -eq 0 ]
  [ "$(ids)" = "cargo:fmtlib cargo:fmt2 pnpm:fmt-js gem:user:fmt-rb pipx:fmt " ]
  [[ "$(printf '%s\n' "${lines[0]}" | plain)" == *"○ fmtlib"*"1.0.0"*"cargo"*"formats things"* ]]
  [[ "$(printf '%s\n' "${lines[2]}" | plain)" == *"● fmt-js"*"pnpm"*"js format"* ]]
  [[ "$(printf '%s\n' "${lines[3]}" | plain)" == *"fmt-rb"*"3.0"*"gem"*"ruby format"* ]]
  grep -q 'search --color never --limit 20 -- fmt' "$BATS_TEST_TMPDIR/calls"
  # PyPI's answer is kept for the preview
  [ "$(head -1 "$FZX_CACHE_DIR/packages/info/pipx/fmt")" = $'fmt\t0.9' ]
  FZX_MODE=search FZF_QUERY=fmt FZX_TOGGLES="npm pypi" run "$MODS/packages/source.sh"
  [ "$(ids)" = "pnpm:fmt-js pipx:fmt " ]
  # nothing to search for, and a query that is no package name skips PyPI
  FZX_MODE=search FZF_QUERY='  ' run "$MODS/packages/source.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  FZX_MODE=search FZF_QUERY='fmt tool' FZX_TOGGLES=pypi run "$MODS/packages/source.sh"
  [ -z "$output" ]
}

@test "packages: a registry that fails is logged and left out" {
  stub_registries
  stub_cmd curl 'exit 28'
  FZX_MODE=search FZF_QUERY=fmt FZX_TOGGLES="crates rubygems" run --separate-stderr "$MODS/packages/source.sh"
  [ "$status" -eq 0 ]
  [ "$(ids)" = "cargo:fmtlib cargo:fmt2 " ]
  [[ "$stderr" == *"packages: rubygems search failed"* ]]
}

@test "packages: packages that are not installed are previewed from the network, once a day each" {
  stub_registries
  run "$MODS/packages/preview.sh" cargo:fmtlib
  local out
  out="$(printf '%s\n' "$output" | plain)"
  [[ "$out" == "fmtlib  1.0.0"*"license      MIT"*$'\n\n'"formats things"$'\n'"well" ]]
  [[ "$out" != *default* ]]
  run "$MODS/packages/preview.sh" gem:user:fmt-rb
  [[ "$(printf '%s\n' "$output" | plain)" == "fmt-rb  3.0"*"licenses     MIT"*"ruby format" ]]
  run "$MODS/packages/preview.sh" pipx:fmt
  [[ "$(printf '%s\n' "$output" | plain)" == "fmt  0.9"*"python       >=3.9"*"py format" ]]
  # the second look comes from the cache; an expired entry is fetched again
  run "$MODS/packages/preview.sh" cargo:fmtlib
  [ "$(grep -c '^cargo info' "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
  FZX_PACKAGES_INFO_TTL=0 run "$MODS/packages/preview.sh" cargo:fmtlib
  [ "$(grep -c '^cargo info' "$BATS_TEST_TMPDIR/calls")" -eq 2 ]
  # offline: said so, and nothing cached
  run "$MODS/packages/preview.sh" gem:user:nope
  [[ "$(printf '%s\n' "$output" | plain)" == *"no details from gem (offline, or no such package)"* ]]
  [ ! -e "$FZX_CACHE_DIR/packages/info/gem/nope" ]
}

@test "packages: a snap not installed is previewed from the store, its classic confinement noted" {
  stub_cmd snap 'case "$1" in
    list) exit 1 ;;
    info) printf "name:      yazi\nsummary:   files\npublisher: Ika\ndescription: |\n  A file manager.\n  Fast.\nchannels:\n  latest/stable:    26.1 2026-09-01 (1) 5MB classic\n  latest/edge:      27 2026-10-01 (2) 5MB classic\n" ;;
  esac'
  run "$MODS/packages/preview.sh" snap:yazi
  [[ "$(printf '%s\n' "$output" | plain)" == "yazi  26.1"*"summary      files"*"publisher    Ika"*"confinement  classic"*$'\n\n'"A file manager."$'\n'"Fast." ]]
}

@test "packages: install from the catalogs and the search, with each manager's own command" {
  [[ "$EUID" -ne 0 ]] || skip "root needs no sudo"
  stub_cmd sudo '"$@"'
  stub_cmd snap 'case "$1" in info) [[ "$*" == *yazi* ]] && printf "name: yazi\nchannels:\n  latest/stable: 1 2026-01-01 (1) 1MB classic\n" || printf "name: yq\nchannels:\n  latest/stable: 4 2026-01-01 (1) 1MB -\n" ;; esac'
  stub_cmd flatpak :
  stub_cmd cargo :
  stub_cmd pnpm :
  stub_cmd gem :
  stub_cmd pipx :
  run "$MODS/packages/actions.sh" install snap:yq snap:yazi flatpak:system:org.b.Bee@hub flatpak:user:org.c.Cee@other \
    cargo:fmtlib pnpm:fmt-js gem:user:fmt-rb pipx:fmt
  [ "$status" -eq 0 ]
  [[ "$output" == *"yazi uses classic confinement"* ]]
  run grep -v -e '^snap info' -e '^sudo ' "$BATS_TEST_TMPDIR/calls"
  [ "${lines[0]}" = "snap install yq" ]
  [ "${lines[1]}" = "snap install --classic yazi" ]
  [ "${lines[2]}" = "flatpak install --system hub org.b.Bee" ]
  [ "${lines[3]}" = "flatpak install --user other org.c.Cee" ]
  [ "${lines[4]}" = "cargo install fmtlib" ]
  [ "${lines[5]}" = "pnpm add -g fmt-js" ]
  [ "${lines[6]}" = "gem install --user-install fmt-rb" ]
  [ "${lines[7]}" = "pipx install fmt" ]
  # catalog ids carry the remote; upgrade and remove drop it
  : > "$BATS_TEST_TMPDIR/calls"
  run "$MODS/packages/actions.sh" upgrade flatpak:system:org.b.Bee@hub
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "flatpak update --system org.b.Bee" ]
  run "$MODS/packages/actions.sh" install flatpak:system:org.b.Bee < /dev/null
  [ "$status" -eq 2 ]
}

@test "packages: the search mode does not filter, it reloads on every query change" {
  stub_registries
  stub_fzf
  run "$FZX" -m packages:search
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --disabled "* ]]
  [[ " ${FZF_ARGS[*]} " == *" change:reload:sleep 0.3; $FZX _cb source "* ]]
  [[ " ${FZF_ARGS[*]} " == *" --header=type to search; "* ]]
}

@test "packages: search switches in place: search off and the change reload rebound going in, the other way out" {
  load_libs log session
  fzx::session_create packages "$FZX_REPO/modules/packages"
  printf 'apt\0search\0' > "$FZX_SESSION_DIR/meta/modes"
  fzx::state_set mode apt
  run "$FZX" _cb mode search
  [ "$status" -eq 0 ]
  [[ "$output" != become:* ]]
  [[ "$output" == *"+disable-search+rebind(change)+change-header(type to search; "* ]]
  run "$FZX" _cb mode apt
  [[ "$output" == *"+enable-search+unbind(change)+change-header("* && "$output" != *"type to search"* ]]
  # every mode under fzx binds the search's reload; outside search it starts unbound
  stub_fzf
  run "$FZX" -m packages:apt --dry-run
  [[ "$output" == *"change:reload:sleep 0.3; "*"_cb source"* && "$output" == *"start:+unbind(change)"* ]]
  [[ "$output" != *"--disabled"* ]]
}
