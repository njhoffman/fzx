# fzx zsh integration: widgets that run an fzx module and put the result on the command line.
#
#   source /path/to/fzx/shell/fzx.zsh
#
# Keys (vi insert and command mode, and emacs) are bound unless FZX_ZSH_NO_BIND=1. Override any of them
# before sourcing, e.g. FZX_ZSH_KEYS[files]='^Xf'; an empty value leaves that widget unbound.
# A plain `fzf` (no options, nothing piped in) opens the files module instead, unless FZX_ZSH_NO_FZF=1.
# g and gg cd to frecent directories, v opens frecent files (fzx jump), unless FZX_ZSH_NO_JUMP=1.

typeset -gA FZX_ZSH_KEYS
: ${FZX_ZSH_KEYS[files]=$'\ef'} # insert file paths
: ${FZX_ZSH_KEYS[dirs]=$'\ed'}  # cd into a directory below this one
: ${FZX_ZSH_KEYS[jump]=$'\ej'}  # cd into a frecent directory (dirs module)
: ${FZX_ZSH_KEYS[git]=$'\eg'}   # insert paths, a hash or a branch from the git module
: ${FZX_ZSH_KEYS[ps]=$'\ep'}    # insert pids
: ${FZX_ZSH_KEYS[menu]=$'\em'}  # open the menu, insert what it returns
: ${FZX_ZSH_KEYS[history]='^R'}  # histdb history: replace the line (alt-enter runs it)

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

# fzx-history-widget: the history module in the scope of the shell's history navigation
# (SHELL_HISTORY_SCOPE: directory, session, else this host), seeded with what is typed. The chosen command
# replaces the line; alt-enter (exit status 10) runs it. HISTDB_SESSION tells the session mode which
# session this shell is.
fzx-history-widget() {
  emulate -L zsh
  setopt pipefail no_aliases
  local out mode rc query=()
  [[ -n "$LBUFFER" ]] && query=(-- "$LBUFFER")
  case "${SHELL_HISTORY_SCOPE:-}" in
    directory | session) mode="$SHELL_HISTORY_SCOPE" ;;
    *) mode=host ;;
  esac
  out="$(FZX_HISTDB_SESSION="${HISTDB_SESSION:-}" command "${FZX_ZSH_BIN:-fzx}" -m "history:$mode" \
    "${query[@]}" < /dev/tty)"
  rc=$?
  if [[ -n "$out" ]]; then
    BUFFER="$out"
    CURSOR=$#BUFFER
  fi
  if ((rc == 10)) && [[ -n "$out" ]]; then
    zle accept-line
  else
    zle reset-prompt
  fi
}

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

# fzx-jump [--pick] [--] [words...]: cd where `fzx jump` says (see lib/jump.sh), then show where that is
fzx-jump() {
  emulate -L zsh
  local dir
  dir="$(command "${FZX_ZSH_BIN:-fzx}" jump "$@" < /dev/tty)" || return
  [[ -n "$dir" && -d "$dir" ]] || return 1
  builtin cd -- "$dir" || return
  if (($+commands[prettypath])); then
    print -r -- "$PWD" | prettypath --stat_file=false --format='  %icon% %dir%%name%'
  else
    print -r -- "  ${PWD/#$HOME/~}"
  fi
}

# g [words...]: the best frecent match; again from inside a match, the next one (so repeating `g foo`
# steps through them). No words, or no match: a picker (no match: every directory under ~, words as the
# query). gg [words...]: one match cds, several open a picker over them; no words reuse the last ones.
typeset -ga _FZX_JUMP_LAST
fzx-cd() {
  emulate -L zsh
  (($#)) || set -- "${_FZX_JUMP_LAST[@]}"
  (($#)) && _FZX_JUMP_LAST=("$@")
  fzx-jump --pick -- "$@"
}
if [[ "${FZX_ZSH_NO_JUMP:-0}" != 1 ]]; then
  # the function keyword: an alias of the same name (an older g) would otherwise break the definition
  function g {
    (($#)) && _FZX_JUMP_LAST=("$@")
    fzx-jump -- "$@"
  }
  function gg { fzx-cd "$@"; }

  # v [words...]: open the frecent files matching the words in $EDITOR: all of them up to
  # FZX_RECENT_JUMP_MAX, a picker over more; no words, the picker over every recent file; no match, the
  # files picker on this directory. A path given as is opens straight away.
  function v {
    emulate -L zsh
    local files f
    files=("${(@f)$(command "${FZX_ZSH_BIN:-fzx}" jump --files -- "$@" < /dev/tty)}")
    files=(${files:#})
    ((${#files})) || return 1
    for f in "${files[@]}"; do
      print -r -- $'  \e[38;5;8;3m'"${f/#$HOME/~}"$'\e[0m'
    done
    print -r -- $'  \e[38;5;8m('"${#files}"$' file(s) to edit)\e[0m'
    ${=${EDITOR:-nvim}} -- "${files[@]}"
  }
fi

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
  for name in files dirs jump git ps menu history; do
    zle -N "fzx-$name-widget"
  done
  [[ "${FZX_ZSH_NO_BIND:-0}" == 1 ]] && return
  local map
  for name in files dirs jump git ps menu history; do
    [[ -n "${FZX_ZSH_KEYS[$name]}" ]] || continue
    for map in emacs viins vicmd; do
      bindkey -M "$map" "${FZX_ZSH_KEYS[$name]}" "fzx-$name-widget"
    done
  done
}
