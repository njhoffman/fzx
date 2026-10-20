# fzx zsh integration: widgets that run an fzx module and put the result on the command line.
#
#   source /path/to/fzx/shell/fzx.zsh
#
# Keys (vi insert and command mode, and emacs) are bound unless FZX_ZSH_NO_BIND=1. Override any of them
# before sourcing, e.g. FZX_ZSH_KEYS[files]='^Xf'; an empty value leaves that widget unbound.

typeset -gA FZX_ZSH_KEYS
: ${FZX_ZSH_KEYS[files]=$'\ef'} # insert file paths
: ${FZX_ZSH_KEYS[dirs]=$'\ed'}  # cd into a directory
: ${FZX_ZSH_KEYS[git]=$'\eg'}   # insert paths, a hash or a branch from the git module
: ${FZX_ZSH_KEYS[ps]=$'\ep'}    # insert pids
: ${FZX_ZSH_KEYS[menu]=$'\em'}  # open the menu, insert what it returns

# fzx-format: selection lines on stdin -> one shell-quoted word each, space-separated; paths under the
# current directory become relative (the directory itself becomes "."). Both the logical $PWD and its
# resolved form count, since modules print resolved paths and $PWD may run through a symlink.
fzx-format() {
  emulate -L zsh
  local line dir out=() dirs=("${PWD%/}" "${${PWD:A}%/}")
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    for dir in "${dirs[@]}"; do
      if [[ "$line" == "$dir" ]]; then
        line=.
        break
      elif [[ "$line" == "$dir/"* ]]; then
        line="${line#$dir/}"
        break
      fi
    done
    out+=("${(q-)line}")
  done
  print -rn -- "${(j: :)out}"
}

# fzx-insert [fzx args...]: run fzx and insert its formatted output at the cursor
fzx-insert() {
  emulate -L zsh
  setopt pipefail no_aliases
  local words
  words="$(command "${FZX_ZSH_BIN:-fzx}" "$@" < /dev/tty | fzx-format)"
  if [[ -n "$words" ]]; then
    [[ -n "$LBUFFER" && "$LBUFFER" != *' ' ]] && words=" $words"
    LBUFFER+="$words"
  fi
  zle reset-prompt
}

fzx-files-widget() { fzx-insert -m files; }
fzx-git-widget() { fzx-insert -m git; }
fzx-ps-widget() { fzx-insert -m ps; }
fzx-menu-widget() { fzx-insert; }

# cd through accept-line (like fzf's alt-c), so the cd is in history and prompt hooks run
fzx-dirs-widget() {
  emulate -L zsh
  setopt pipefail no_aliases
  local dir
  dir="$(command "${FZX_ZSH_BIN:-fzx}" -m files:dirs < /dev/tty | head -n 1)"
  if [[ -z "$dir" ]]; then
    zle reset-prompt
    return 0
  fi
  zle push-line
  BUFFER="builtin cd -- ${(q-)dir}"
  zle accept-line
}

() {
  local name
  for name in files dirs git ps menu; do
    zle -N "fzx-$name-widget"
  done
  [[ "${FZX_ZSH_NO_BIND:-0}" == 1 ]] && return
  local map
  for name in files dirs git ps menu; do
    [[ -n "${FZX_ZSH_KEYS[$name]}" ]] || continue
    for map in emacs viins vicmd; do
      bindkey -M "$map" "${FZX_ZSH_KEYS[$name]}" "fzx-$name-widget"
    done
  done
}
