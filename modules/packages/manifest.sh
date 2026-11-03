#!/usr/bin/env bash
# packages menu entries, one per package manager on PATH

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

packages::manifest() {
  fzx::entry packages "Installed packages (apt)"
  fzx::entry packages:available "Packages to install (apt)"
  fzx::entry packages:upgradable "Packages with upgrades (apt)"
  fzx::entry packages:snap "Snaps"
  fzx::entry packages:flatpak "Flatpak applications"
  fzx::entry packages:pipx "pipx applications"
  fzx::entry packages:cargo "Crates installed with cargo"
  fzx::entry packages:pnpm "pnpm global packages"
  fzx::entry packages:gem "Gems"
}

packages::applicable() {
  case "$1" in
    packages | packages:available | packages:upgradable) packages::has apt ;;
    packages:*) packages::has "${1#packages:}" ;;
    *) return 1 ;;
  esac
}

# packages::summary <target>: counts from what is read fast (dpkg, the module's caches, the managers' files)
packages::summary() {
  local n
  case "$1" in
    packages)
      n="$(command dpkg-query -W -f '${db:Status-Abbrev}\t${Package}\n' 2> /dev/null | grep -c '^.i')"
      printf '%s installed\n' "$n"
      ;;
    # apt's lists: read once and kept until they change, so opening the mode is quicker for it too
    packages:available)
      n="$(packages::_cached available "$(packages::_stamp "$(packages::_apt_lists)")" packages::_available_raw | wc -l)"
      printf '%s packages\n' "$n"
      ;;
    packages:upgradable)
      n="$(packages::_cached upgradable "$(packages::_stamp "$(packages::_apt_lists)" "$(packages::_dpkg_status)")" packages::_upgradable_raw | wc -l)"
      printf '%s upgradable\n' "$n"
      ;;
    packages:snap | packages:flatpak | packages:pipx | packages:cargo | packages:pnpm | packages:gem)
      n="$(FZX_MODE="${1#packages:}" packages::source 2> /dev/null | wc -l)"
      printf '%s installed\n' "$n"
      ;;
  esac
  return 0
}
