# fzx zsh integration: widgets that run an fzx module and put the result on the command line.
#
#   source /path/to/fzx/shell/fzx.zsh
#
# Keys (vi insert and command mode, and emacs) are bound unless FZX_ZSH_NO_BIND=1. Override any of them
# before sourcing, e.g. FZX_ZSH_KEYS[files]='^Xf'; an empty value leaves that widget unbound.
# A plain `fzf` (no options, nothing piped in) opens the files module instead, unless FZX_ZSH_NO_FZF=1.

typeset -gA FZX_ZSH_KEYS
: ${FZX_ZSH_KEYS[files]=$'\ef'} # insert file paths
: ${FZX_ZSH_KEYS[dirs]=$'\ed'}  # cd into a directory below this one
: ${FZX_ZSH_KEYS[jump]=$'\ej'}  # cd into a frecent directory (dirs module)
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

# fzx-cd-widget-run <fzx args...>: cd into the directory fzx prints, through accept-line (like fzf's
# alt-c), so the cd is in history and prompt hooks run
fzx-cd-widget-run() {
  emulate -L zsh
  setopt pipefail no_aliases
  local dir
  dir="$(command "${FZX_ZSH_BIN:-fzx}" "$@" < /dev/tty | head -n 1)"
  if [[ -z "$dir" ]]; then
    zle reset-prompt
    return 0
  fi
  zle push-line
  BUFFER="builtin cd -- ${(q-)dir}"
  zle accept-line
}

fzx-dirs-widget() { fzx-cd-widget-run -m files:dirs; }
fzx-jump-widget() { fzx-cd-widget-run -m dirs; }

# fzx-cd [words...]: cd to a frecent directory; with words, a single match is taken without a picker
# (alias g=fzx-cd for the old g/gg behaviour)
fzx-cd() {
  emulate -L zsh
  local dir
  dir="$(command "${FZX_ZSH_BIN:-fzx}" -m dirs "$@" < /dev/tty | head -n 1)"
  [[ -n "$dir" ]] && builtin cd -- "$dir"
}

# fzf: with no options and nothing piped in, the files module (prettypath icons when installed) instead
# of fzf's own walker; prints what it prints. Anything else is the real fzf.
if [[ "${FZX_ZSH_NO_FZF:-0}" != 1 ]]; then
  fzf() {
    if (($# == 0)) && [[ -t 0 ]]; then
      command "${FZX_ZSH_BIN:-fzx}" -m files
    else
      command fzf "$@"
    fi
  }
fi

() {
  local name
  for name in files dirs jump git ps menu; do
    zle -N "fzx-$name-widget"
  done
  [[ "${FZX_ZSH_NO_BIND:-0}" == 1 ]] && return
  local map
  for name in files dirs jump git ps menu; do
    [[ -n "${FZX_ZSH_KEYS[$name]}" ]] || continue
    for map in emacs viins vicmd; do
      bindkey -M "$map" "${FZX_ZSH_KEYS[$name]}" "fzx-$name-widget"
    done
  done
}
