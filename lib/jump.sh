#!/usr/bin/env bash
# jump: `fzx jump [--pick] [--] [WORDS...]` prints the directory g / gg (shell/fzx.zsh) cd into.
#
#   a single word that is a directory   that directory
#   no words                            the picker over every frecent directory (dirs module)
#   no frecent match                    the picker over every directory under ~ (dirs:all), WORDS as its query
#   g (no --pick)                       the best match; when $PWD is a match already, the one after it
#                                       (wrapping), so repeating `g foo` steps through the matches
#   gg (--pick)                         a single match as is; several open the picker over them
#
# Matches come from the dirs module's FZX_DIRS_JUMP_MODE (default: its default mode, z.lua or zoxide);
# directories that no longer exist are skipped. Prints nothing and fails when nothing was chosen.

fzx::jump() {
  local pick=0 dir mode matches=() n i idx=-1 here here_p
  while (($#)); do
    case "$1" in
      --pick) pick=1 && shift ;;
      --) shift && break ;;
      -*) fzx::die 2 "jump: unknown option $1 (fzx jump [--pick] [--] [WORDS...])" ;;
      *) break ;;
    esac
  done

  # a path given as is
  if (($# == 1)) && [[ -d "${1/#\~/$HOME}" ]]; then
    (cd -- "${1/#\~/$HOME}" && pwd)
    return
  fi

  dir="$(fzx::module_find dirs)" || fzx::die 2 "jump: the dirs module is not in FZX_MODULE_PATH"
  fzx::require config components
  fzx::config_load "$dir" dirs
  # shellcheck disable=SC2034  # the executable components.tsv reads them
  FZX_MODULE_DIR="$dir" FZX_MODULE=dirs
  fzx::comp_load "$dir" dirs
  mode="${FZX_DIRS_JUMP_MODE:-$FZX_MODE_DEFAULT}"
  if ((!$#)); then
    fzx::log info "jump: no words, picker over $mode"
    exec "$FZX_BIN" -m "dirs:$mode"
  fi

  # shellcheck source=../modules/dirs/source.sh
  source "$dir/source.sh"
  # ids only, so no icons are needed
  mapfile -t matches < <(FZX_PRETTY=0 FZX_MODE="$mode" dirs::source "$@" 2>> "${FZX_LOG_FILE:-/dev/null}" | cut -f1)
  n="${#matches[@]}"
  if ((n == 0)); then
    fzx::log info "jump: no $mode match for '$*', picker over every directory"
    fzx::comp_field mode all key _ || return 1
    exec "$FZX_BIN" -m dirs:all "$@"
  fi
  if ((pick)); then
    if ((n == 1)); then
      fzx::log info "jump: single $mode match for '$*': ${matches[0]}"
      printf '%s\n' "${matches[0]}"
      return 0
    fi
    fzx::log info "jump: $n $mode matches for '$*', picker"
    exec "$FZX_BIN" -m "dirs:$mode" "$@"
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
