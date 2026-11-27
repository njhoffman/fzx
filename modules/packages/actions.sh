#!/usr/bin/env bash
# packages actions, bound with execute (in the foreground) so sudo, apt's own prompt and polkit can ask.
# The selection is grouped by manager (and installation), one command per group, so several apt packages
# install in one apt run. install takes rows of the catalogs and the search: snaps get --classic when the
# store says they need it, flatpaks come from the row's remote, gems go to your user gem home. apt and snap run through sudo; flatpak's system installation asks through
# polkit itself; gems through sudo when their gem home is not writable. The updates mode's upgrade is one
# audit packages update run, which asks itself. A failure waits for a key, since execute would wipe the
# output at once.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# packages::_root <cmd...>: run as root: through sudo unless fzx is root
packages::_root() {
  if ((EUID == 0)); then "$@"; else command sudo "$@"; fi
}

# packages::_report <rc>: show a failure until a key is pressed
packages::_report() {
  local rc="$1"
  ((rc == 0)) && return 0
  printf '\n\e[31mfailed (exit %s)\e[0m, press a key ' "$rc"
  IFS= read -rsn1 2> /dev/null < /dev/tty || :
  return "$rc"
}

# packages::_confirm <what> <names...>: ask y/N on the terminal (stdin when it is a pipe or a file); apt's
# remove and purge skip this, apt asks itself and lists what else goes with them
packages::_confirm() {
  local what="$1" ans="" fd
  shift
  printf '\n\e[1m%s\e[0m %s\n[y/N] ' "$what" "$*"
  if [[ -p /dev/stdin || -f /dev/stdin ]]; then
    IFS= read -rsn1 ans || :
  elif { exec {fd}< /dev/tty; } 2> /dev/null; then
    IFS= read -rsn1 -u "$fd" ans || :
    exec {fd}<&-
  fi
  printf '\n'
  [[ "$ans" == [yY] ]]
}

# packages::_gem_dir <scope> <name>: the gem home of that scope holding the gem
packages::_gem_dir() {
  local scope dir spec
  while IFS=$'\t' read -r scope dir; do
    [[ "$scope" == "$1" ]] || continue
    for spec in "$dir/specifications/$2"-[0-9]*.gemspec; do
      [[ -f "$spec" ]] && {
        printf '%s' "$dir"
        return 0
      }
    done
  done < <(packages::gem_dirs)
  return 1
}

# packages::cargo_install_args <name>: cargo install's arguments to install the crate again from where it
# came from (crates.io, its git repository and branch or tag, its path), one per line; a git install
# pinned to a revision is reinstalled at that revision
packages::cargo_install_args() {
  local name="$1" src ref
  src="$(packages::cargo_installs | awk -F '\t' -v n="$name" '$1 == n { print $3; exit }')"
  [[ -n "$src" ]] || return 1
  case "$src" in
    git+*)
      ref="${src#*\?}"
      [[ "$ref" == "$src" ]] && ref=""
      ref="${ref%%#*}"
      src="${src#git+}"
      src="${src%%[?#]*}"
      printf '%s\n' --git "$src"
      [[ "$ref" =~ ^(branch|tag|rev)=(.+)$ ]] && printf '%s\n' "--${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      ;;
    path+file://*) printf '%s\n' --path "${src#path+file://}" ;;
    *) ;;
  esac
  printf '%s\n' "$name"
}

# packages::_group <action> <manager> <scope> <names...>: the action on one manager's packages
packages::_group() {
  local action="$1" manager="$2" scope="$3" name rc=0
  shift 3
  if [[ "$action" == remove && "$manager" != apt ]]; then
    local label="$manager"
    [[ "$scope" == - ]] || label+=" $scope"
    packages::_confirm "remove ($label):" "$@" || return 0
  fi
  case "$manager:$action" in
    apt:install) packages::_root apt install "$@" ;;
    apt:upgrade) packages::_root apt install --only-upgrade "$@" ;;
    apt:remove) packages::_root apt remove "$@" ;;
    apt:purge) packages::_root apt purge "$@" ;;
    snap:install)
      # classic snaps refuse to install without --classic: the store's details say which (cached)
      for name in "$@"; do
        if packages::remote_info snap "$name" 2> /dev/null | grep -qx $'confinement\tclassic'; then
          printf '%s uses classic confinement (full access to the system): installing with --classic\n' "$name"
          packages::_root snap install --classic "$name" || rc=$?
        else
          packages::_root snap install "$name" || rc=$?
        fi
      done
      return "$rc"
      ;;
    snap:upgrade) packages::_root snap refresh "$@" ;;
    snap:remove) packages::_root snap remove "$@" ;;
    flatpak:install)
      # catalog rows carry their remote (APP@REMOTE); flatpak install takes one remote per run
      for name in "$@"; do
        [[ "$name" == *@* ]] || {
          printf 'flatpak: %s: no remote to install it from\n' "$name" >&2
          rc=2
          continue
        }
        command flatpak install "--$scope" "${name##*@}" "${name%@*}" || rc=$?
      done
      return "$rc"
      ;;
    flatpak:upgrade) command flatpak update "--$scope" "${@%@*}" ;;
    flatpak:remove) command flatpak uninstall "--$scope" "${@%@*}" ;;
    uv:install | uv:upgrade | uv:remove)
      for name in "$@"; do
        case "$action" in
          install) command uv tool install "$name" ;;
          upgrade) command uv tool upgrade "$name" ;;
          remove) command uv tool uninstall "$name" ;;
        esac || rc=$?
      done
      return "$rc"
      ;;
    cargo:upgrade)
      local -a args
      for name in "$@"; do
        mapfile -t args < <(packages::cargo_install_args "$name")
        ((${#args[@]})) || {
          printf 'cargo: %s: not in .crates2.json\n' "$name" >&2
          rc=1
          continue
        }
        command cargo install "${args[@]}" || rc=$?
      done
      return "$rc"
      ;;
    cargo:install) command cargo install "$@" ;;
    cargo:remove) command cargo uninstall "$@" ;;
    pnpm:install) command pnpm add -g "$@" ;;
    pnpm:upgrade) command pnpm update -g --latest "$@" ;;
    pnpm:remove) command pnpm remove -g "$@" ;;
    gem:install)
      if [[ "$scope" == user ]]; then
        command gem install --user-install "$@"
      else
        packages::_root gem install "$@"
      fi
      ;;
    gem:upgrade | gem:remove)
      local dir
      local -a run=()
      for name in "$@"; do
        dir="$(packages::_gem_dir "$scope" "$name")" || {
          printf 'gem: %s: not found in the %s gem homes\n' "$name" "$scope" >&2
          rc=1
          continue
        }
        [[ -w "$dir" ]] && run=() || run=(packages::_root)
        if [[ "$action" == upgrade ]]; then
          "${run[@]}" gem update -i "$dir" "$name" || rc=$?
        else
          "${run[@]}" gem uninstall -a -x -i "$dir" "$name" || rc=$?
        fi
      done
      return "$rc"
      ;;
    *)
      printf '%s: %s does not apply\n' "$manager" "$action" >&2
      return 2
      ;;
  esac
}

# packages::_update_id <var> <manager:name>: the id the manager's own mode gives an outdated package of the
# updates mode (audit's ref), so the other actions reach it as they would there: gems and flatpaks by the
# installation that has them (user first). Fails for a manager fzx has no mode for (go, gh, bins)
packages::_update_id() {
  local _manager="${2%%:*}" _name="${2#*:}" _id
  case "$_manager" in
    uv | cargo | pnpm | apt | snap) _id="$_manager:$_name" ;;
    gem) if packages::_gem_dir user "$_name" > /dev/null; then _id="gem:user:$_name"; else _id="gem:system:$_name"; fi ;;
    flatpak)
      if command flatpak info --user -- "$_name" > /dev/null 2>&1; then _id="flatpak:user:$_name"; else _id="flatpak:system:$_name"; fi
      ;;
    *) return 1 ;;
  esac
  printf -v "$1" '%s' "$_id"
}

# packages::action <install|upgrade|remove|purge> <id...>. The updates mode's ids (update:MANAGER:NAME):
# upgrade hands them all to one audit packages update run (it prints its plan, asks, and rescans); the
# other actions take them as the manager's own ids
packages::action() {
  local action="${1:-}" id manager scope name key rc=0
  shift
  case "$action" in
    install | upgrade | remove | purge) ;;
    *)
      printf 'packages: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  (($#)) || {
    printf 'packages: %s: no packages given\n' "$action" >&2
    return 2
  }
  local -a refs=() ids=()
  for id in "$@"; do
    if [[ "$id" == update:* ]]; then
      if [[ "$action" == upgrade ]]; then
        refs+=("${id#update:}")
        continue
      fi
      packages::_update_id id "${id#update:}" || {
        # on stdout: the terminal shows it until packages::_report's key (stderr goes to the log)
        name="${id#update:}"
        printf 'packages: %s: no %s here for %s packages\n' "${name#*:}" "$action" "${name%%:*}"
        rc=1
        continue
      }
    fi
    ids+=("$id")
  done
  if ((${#refs[@]})); then
    command audit packages update "${refs[@]}" || rc=$?
  fi
  # group by manager and scope, keeping the order they came in
  local -a order=()
  local -A names=()
  for id in "${ids[@]}"; do
    manager="${id%%:*}"
    name="${id#*:}"
    scope=-
    if [[ "$manager" == flatpak || "$manager" == gem ]]; then
      scope="${name%%:*}"
      name="${name#*:}"
    fi
    [[ "$id" == *:* && -n "$name" ]] || {
      printf 'packages: not a package id: %s\n' "$id" >&2
      return 2
    }
    key="$manager"$'\t'"$scope"
    [[ -n "${names[$key]+x}" ]] || order+=("$key")
    names[$key]+="$name"$'\n'
  done
  local -a group
  for key in "${order[@]}"; do
    mapfile -t group <<< "${names[$key]%$'\n'}"
    packages::_group "$action" "${key%%$'\t'*}" "${key#*$'\t'}" "${group[@]}" || rc=$?
  done
  packages::_report "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && packages::action "$@"
