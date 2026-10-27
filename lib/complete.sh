#!/usr/bin/env bash
# complete: shell completion. `fzx completion zsh` prints a zsh completion function (#compdef fzx) whose
# lists come from `fzx _complete` as you complete, so new modules and modes need no new script:
#   fzx _complete targets   "module<TAB>description" and "module:mode<TAB>description" rows (hidden modes
#                           left out), first on FZX_MODULE_PATH wins
#   fzx _complete modules   the module names
#   fzx _complete sessions  "sid<TAB>module" of the live sessions
# Install: `fzx completion zsh > "${fpath[1]}/_fzx"` (before compinit), or ~/.shell's zsh-complete
# (`fzx generated _fzx fzx completion zsh` in its sources.tsv).

# fzx::_complete_dirs: "name<TAB>dir" of every module (a directory with module.sh), first on the path wins
fzx::_complete_dirs() {
  local dir mod name
  local -A seen=()
  local IFS=:
  for dir in $FZX_MODULE_PATH; do
    for mod in "$dir"/*/; do
      mod="${mod%/}"
      name="${mod##*/}"
      [[ -f "$mod/module.sh" && -z "${seen[$name]:-}" && "$name" =~ ^[A-Za-z0-9_-]+$ ]] || continue
      seen[$name]=1
      printf '%s\t%s\n' "$name" "$mod"
    done
  done | sort
}

# fzx::_complete_desc <module.sh>: the module's description, from its second line ("# name: what it is.
# ..."), up to the first sentence end, a backquote or a parenthesis
fzx::_complete_desc() {
  sed -n '2{s/^# *[A-Za-z0-9_-]*: *//; s/[.(`].*//; s/[ ,;:]*$//; p; q}' -- "$1" | cut -c1-70
}

# fzx::complete <targets|modules|sessions>
fzx::complete() {
  local name dir kind mode desc flags
  case "${1:-}" in
    targets)
      fzx::require components
      while IFS=$'\t' read -r name dir; do
        printf '%s\t%s\n' "$name" "$(fzx::_complete_desc "$dir/module.sh")"
        while IFS=$'\t' read -r kind mode _ desc flags; do
          [[ "$kind" == mode && ",$flags," != *,hidden,* ]] || continue
          [[ "$desc" == - ]] && desc=""
          printf '%s:%s\t%s\n' "$name" "$mode" "$desc"
        done < <(FZX_MODULE_DIR="$dir" FZX_MODULE="$name" fzx::_comp_read "$dir/components.tsv" 2> /dev/null)
      done < <(fzx::_complete_dirs)
      ;;
    modules) fzx::_complete_dirs | cut -f1 ;;
    sessions)
      for dir in "$FZX_RUNTIME_DIR"/sessions/*/; do
        [[ -f "$dir/meta/module" ]] || continue
        printf '%s\t%s\n' "$(basename -- "$dir")" "$(< "$dir/meta/module")"
      done
      ;;
    *)
      printf 'usage: fzx _complete targets|modules|sessions\n' >&2
      return 2
      ;;
  esac
}

# fzx::completion <shell>: the completion script for the shell (zsh only)
fzx::completion() {
  case "${1:-}" in
    zsh) fzx::_completion_zsh ;;
    *)
      printf 'usage: fzx completion zsh\n' >&2
      return 2
      ;;
  esac
}

fzx::_completion_zsh() {
  command cat << 'ZSH'
#compdef fzx
# zsh completion for fzx, printed by `fzx completion zsh` (lib/complete.sh). Modules, modes and sessions
# are asked of `fzx _complete` while completing.

# module and module:mode, described
_fzx_targets() {
  local -a targets
  local line
  for line in "${(@f)$(_call_program targets "${words[1]}" _complete targets 2> /dev/null)}"; do
    [[ -n "$line" ]] && targets+=("${${line%%$'\t'*}//:/\\:}:${line#*$'\t'}")
  done
  _describe -t targets 'module[:mode]' targets
}

_fzx_modules() {
  local -a modules
  modules=("${(@f)$(_call_program modules "${words[1]}" _complete modules 2> /dev/null)}")
  _describe -t modules module modules
}

_fzx_sessions() {
  local -a sessions
  local line
  for line in "${(@f)$(_call_program sessions "${words[1]}" _complete sessions 2> /dev/null)}"; do
    [[ -n "$line" ]] && sessions+=("${line%%$'\t'*}:${line#*$'\t'}")
  done
  _describe -t sessions session sessions
}

_fzx() {
  local curcontext="$curcontext" state line ret=1
  typeset -A opt_args
  local -a commands=(
    'gc:remove dead sessions and stale caches'
    'stats:runs, callbacks and their timings'
    'config:the resolved configuration of a module'
    'jump:the directory g and gg cd into'
    'keys:keys in use and free keys'
    'builtin:the built-in actions (copy, copy-line, view, confirm)'
    'debug:inspect and drive sessions'
    'completion:print a shell completion script'
  )
  if ((CURRENT > 2)) && ((${commands[(I)${words[2]}:*]})); then
    local cmd="${words[2]}"
    shift words
    ((CURRENT--))
    curcontext="${curcontext%:*:*}:fzx-$cmd:"
    case "$cmd" in
      gc) _arguments '--all[also kept sessions]' && ret=0 ;;
      stats)
        _arguments \
          '--since[only what ran since]:age:(90s 5m 2h 7d)' \
          '--module[one module]:module:_fzx_modules' \
          '--raw[the rows as they are kept]' && ret=0
        ;;
      config) _arguments '(-m --mode)'{-m,--mode}'[a module]:module:_fzx_modules' '1::module:_fzx_modules' && ret=0 ;;
      jump) _arguments '--pick[pick even when one directory matches]' '*:word: ' && ret=0 ;;
      keys) _arguments '*:fzf key: ' && ret=0 ;;
      builtin) _arguments '1:built-in action:(copy copy-line view confirm)' '*:argument: ' && ret=0 ;;
      debug)
        _arguments '1:debug command:((ls\:"the sessions" tail\:"follow the log" attach\:"a prompt on a session" state\:"a session'"'"'s state" send\:"send an fzf action"))' \
          '*::argument:->debug' && ret=0
        [[ "$state" == debug ]] && _fzx_sessions && ret=0
        ;;
      completion) _arguments '1:shell:(zsh)' && ret=0 ;;
    esac
    return ret
  fi
  _arguments -s -S -C \
    '(-m --mode --resume)'{-m+,--mode=}'[run a module, in a mode]:module[\:mode]:_fzx_targets' \
    '(-m --mode)--resume=-[restart the interface of a session]::session:_fzx_sessions' \
    '(--float --split)--popup=-[start in a tmux or Zellij popup]::popup options (center,80%): ' \
    '(--popup --split)--float=-[start in a floating tmux pane]::popup options (center,80%): ' \
    '(--popup --float)--split=-[start in a tmux split pane]::direction and size:(up down left right down,40% right,50%)' \
    '--query=[start with this query typed in]:query: ' \
    '--dry-run[print the fzf command instead of running it]' \
    '--keep[keep the session directory after exit]' \
    '(- *)'{-h,--help}'[show the help]' \
    '(- *)'{-V,--version}'[print the version]' \
    '*:: :->args' && ret=0
  if [[ "$state" == args ]]; then
    # the first word without -m is a command; after it, or with a module, the module's arguments
    if ((CURRENT == 1)) && [[ -z "${opt_args[-m]-}${opt_args[--mode]-}${opt_args[--resume]-}" ]]; then
      _describe -t commands 'fzx command' commands && ret=0
    else
      _files && ret=0
    fi
  fi
  return ret
}

if [[ "$funcstack[1]" == _fzx ]]; then
  _fzx "$@"
else
  compdef _fzx fzx
fi
ZSH
}
