#!/usr/bin/env bash
# jump: `fzx jump [--pick] [--] [WORDS...]` prints the directory g / gg (shell/fzx.zsh) cd into;
# `fzx jump --files [--] [WORDS...]` the files v opens (fzx::jump_files, below).
#
#   a single word that is a directory   that directory
#   no words                            the picker over every frecent directory (recent module)
#   no frecent match                    the picker over every directory under ~ (dirs:all), WORDS as its query
#   g (no --pick)                       the best match; when $PWD is a match already, the one after it
#                                       (wrapping), so repeating `g foo` steps through the matches
#   gg (--pick)                         a single match as is; several open the picker over them
#
# Matches come from FZX_RECENT_DIRS_JUMP_MODE (recent's config): a directory mode of the recent module, or
# MODULE:MODE of another (dirs:bookmarks); by default recent's zlua, else dirs (zoxide), else fasd-dirs.
# Directories that no longer exist are skipped. Prints nothing and fails when nothing was chosen.

# fzx::jump_source <module var> <mode var>: the module and mode g matches with, its config and components
# loaded and its source.sh sourced
fzx::jump_source() {
  local _dir _spec _mod _mode _m
  _dir="$(fzx::module_find recent)" || fzx::die 2 "jump: the recent module is not in FZX_MODULE_PATH"
  fzx::require config components
  fzx::config_load "$_dir" recent
  _spec="${FZX_RECENT_DIRS_JUMP_MODE:-}"
  if [[ "$_spec" == *:* ]]; then
    _mod="${_spec%%:*}" _mode="${_spec#*:}"
    _dir="$(fzx::module_find "$_mod")" || fzx::die 2 "jump: no module $_mod (FZX_RECENT_DIRS_JUMP_MODE=$_spec)"
    fzx::config_load "$_dir" "$_mod"
  else
    _mod=recent _mode="$_spec"
  fi
  # shellcheck disable=SC2034  # the executable components.tsv reads them
  FZX_MODULE_DIR="$_dir" FZX_MODULE="$_mod"
  fzx::comp_load "$_dir" "$_mod"
  if [[ -z "$_mode" ]]; then
    for _m in zlua dirs fasd-dirs; do
      [[ " ${FZX_MODES[*]} " == *" $_m "* ]] && { _mode="$_m"; break; }
    done
    [[ -n "$_mode" ]] || fzx::die 1 "jump: no directory tracker installed (z.lua, zoxide or fasd)"
  fi
  # shellcheck source=../modules/recent/source.sh
  source "$_dir/source.sh"
  printf -v "$1" '%s' "$_mod"
  printf -v "$2" '%s' "$_mode"
}

fzx::jump() {
  local pick=0 mod mode matches=() n i idx=-1 here here_p
  while (($#)); do
    case "$1" in
      --files)
        shift
        fzx::jump_files "$@"
        return
        ;;
      --pick) pick=1 && shift ;;
      --) shift && break ;;
      -*) fzx::die 2 "jump: unknown option $1 (fzx jump [--files] [--pick] [--] [WORDS...])" ;;
      *) break ;;
    esac
  done

  # a path given as is
  if (($# == 1)) && [[ -d "${1/#\~/$HOME}" ]]; then
    (cd -- "${1/#\~/$HOME}" && pwd)
    return
  fi

  fzx::jump_source mod mode
  if ((!$#)); then
    fzx::log info "jump: no words, picker over $mod:$mode"
    exec "$FZX_BIN" -m "$mod:$mode"
  fi

  # ids only, so no icons are needed
  mapfile -t matches < <(FZX_PRETTY=0 FZX_MODE="$mode" "$mod::source" "$@" 2>> "${FZX_LOG_FILE:-/dev/null}" | cut -f1)
  n="${#matches[@]}"
  if ((n == 0)); then
    fzx::log info "jump: no $mode match for '$*', picker over every directory"
    exec "$FZX_BIN" -m dirs:all "$@"
  fi
  if ((pick)); then
    if ((n == 1)); then
      fzx::log info "jump: single $mode match for '$*': ${matches[0]}"
      printf '%s\n' "${matches[0]}"
      return 0
    fi
    fzx::log info "jump: $n $mode matches for '$*', picker"
    exec "$FZX_BIN" -m "$mod:$mode" "$@"
  fi

  # from inside a match, the next one: both the logical and the resolved $PWD count
  here="${PWD%/}" here_p="$(pwd -P)"
  for ((i = 0; i < n; i++)); do
    if [[ "${matches[i]}" == "$here" || "${matches[i]}" == "$here_p" ]]; then
      idx="$i"
      break
    fi
  done
  i=$(((idx + 1) % n))
  fzx::log info "jump: '$*' -> ${matches[i]} (match $((i + 1)) of $n in $mode)"
  printf '%s\n' "${matches[i]}"
}

# fzx::jump_files [--] [WORDS...]: the files v opens, one per line, from the recent module
#   a single word that is a file or directory   that path
#   no words                                    the picker over every recent file
#   no match                                    the files picker on $PWD, WORDS as its query
#   up to FZX_RECENT_JUMP_MAX matches           all of them
#   more                                        the picker over them
fzx::jump_files() {
  local dir mode matches=() n
  [[ "${1:-}" == -- ]] && shift
  if (($# == 1)) && [[ -e "${1/#\~/$HOME}" ]]; then
    printf '%s\n' "${1/#\~/$HOME}"
    return
  fi
  dir="$(fzx::module_find recent)" || fzx::die 2 "jump: the recent module is not in FZX_MODULE_PATH"
  fzx::require config components
  fzx::config_load "$dir" recent
  # shellcheck disable=SC2034  # the executable components.tsv reads them
  FZX_MODULE_DIR="$dir" FZX_MODULE=recent
  fzx::comp_load "$dir" recent
  mode="${FZX_RECENT_JUMP_MODE:-}"
  if [[ -z "$mode" ]]; then
    # the default mode can be a directory one (no nvim database, no fasd): files only here
    [[ " ${FZX_MODES[*]} " == *" nvim "* ]] && mode=nvim
    [[ -z "$mode" && " ${FZX_MODES[*]} " == *" fasd "* ]] && mode=fasd
    [[ -n "$mode" ]] || fzx::die 1 "jump: no recent files source (telescope-frecency's database or fasd)"
  fi
  if ((!$#)); then
    fzx::log info "jump files: no words, picker over $mode"
    exec "$FZX_BIN" -m "recent:$mode"
  fi
  # shellcheck source=../modules/recent/source.sh
  source "$dir/source.sh"
  mapfile -t matches < <(FZX_PRETTY=0 FZX_MODE="$mode" recent::source "$@" 2>> "${FZX_LOG_FILE:-/dev/null}" | cut -f1)
  n="${#matches[@]}"
  if ((n == 0)); then
    fzx::log info "jump files: no $mode match for '$*', files picker on $PWD"
    exec "$FZX_BIN" -m files --query="$*" "$PWD"
  fi
  if ((n > ${FZX_RECENT_JUMP_MAX:-10})); then
    fzx::log info "jump files: $n $mode matches for '$*', picker"
    exec "$FZX_BIN" -m "recent:$mode" "$@"
  fi
  fzx::log info "jump files: '$*' -> $n file(s) in $mode"
  printf '%s\n' "${matches[@]}"
}
