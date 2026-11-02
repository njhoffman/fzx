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
  printf '[package]\nname = "ripgrep"\ndescription = "fast grep"\n[dependencies]\ndescription = "no"\n' > "$CARGO_HOME/registry/src/index-1/ripgrep-14.1.0/Cargo.toml"
  run "$MODS/packages/preview.sh" cargo:ripgrep
  local out
  out="$(printf '%s\n' "$output" | plain)"
  [[ "$out" == "ripgrep  14.1.0"*"binaries     rg"*"features     pcre2"*"description  fast grep" ]]

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
  run "$MODS/packages/actions.sh" remove snap:yq flatpak:user:org.b.App
  run "$MODS/packages/actions.sh" purge apt:zsh
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
    _ "$u" "$s" "$MODS/packages/actions.sh"
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
