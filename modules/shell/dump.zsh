# shell: the zsh side. Sourced by shell/fzx.zsh (and by the module's `zsh -ic` fallback); defines
# fzx-shell-dump, which prints the shell's aliases, functions, parameters, builtins and reserved words as
# tab-separated lines:
#   alias<TAB>regular|global|suffix<TAB>NAME<TAB>VALUE
#   function<TAB>NAME<TAB>FILE (may be empty)<TAB>1 when autoloaded and not loaded yet, else 0
#   param<TAB>NAME<TAB>TYPE (${(t)NAME})<TAB>VALUE<TAB>1 when the value is masked, else 0
#   builtin<TAB>NAME  and  reserved<TAB>NAME
# Values are quoted as zsh reads them back ((q+): one line, $'...' for tabs and newlines); arrays as
# ( a 'b c' ), associations as ( [k]=v ... ). Parameters whose names match FZX_SHELL_SECRETS (an extended
# regular expression, matched against the upper-cased name) are written without their value.
# fzx-shell-dump-functions prints the definitions of the loaded functions that are not completion
# functions (no leading _), as `functions` does. fzx-shell-dump-file writes both, owner-only, to
# $FZX_STATE_DIR/shell/{dump.tsv,functions.zsh}.

fzx-shell-dump() {
  emulate -L zsh
  zmodload zsh/parameter 2> /dev/null
  local n t v k f secrets="${FZX_SHELL_SECRETS:-TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|APIKEY|_KEY\$|PASS\$}"
  local -a vals
  for n in ${(ko)aliases}; do print -r -- "alias"$'\t'"regular"$'\t'"$n"$'\t'"${(q+)aliases[$n]}"; done
  for n in ${(ko)galiases}; do print -r -- "alias"$'\t'"global"$'\t'"$n"$'\t'"${(q+)galiases[$n]}"; done
  for n in ${(ko)saliases}; do print -r -- "alias"$'\t'"suffix"$'\t'"$n"$'\t'"${(q+)saliases[$n]}"; done
  for n in ${(ko)functions}; do
    # (no $(...) here: a fork per function takes seconds.) Not loaded yet, its body is only the autoload
    # call; its file is then looked up on fpath (not for the thousands of completion functions). The file
    # is kept when it is one: zsh reports "zsh" for code given to -c, and paths as they were sourced
    k=0 f="${functions_source[$n]:-}"
    if [[ "$functions[$n]" == 'builtin autoload -X'* ]]; then
      k=1
      [[ -z "$f" && "$n" != _* ]] && f=(${^fpath}/$n(N[1]))
    fi
    if [[ -n "$f" && -f "$f" ]]; then f="${f:A}"; else f=""; fi
    print -r -- "function"$'\t'"$n"$'\t'"$f"$'\t'"$k"
  done
  for n in ${(ko)parameters}; do
    t="${parameters[$n]}"
    # zsh/parameter's tables (and mapfile, which would read files) are hidden associations: left out,
    # as are this function's own locals
    [[ "$t" == *hideval* || "$t" == *local* ]] && continue
    # the positional and punctuation parameters ($0, $#, $-, ...) and the call stack describe this function,
    # not the shell
    [[ "$n" != [[:alpha:]_]* || "$n" == (argv|ARGC|funcstack|funcfiletrace|funcsourcetrace|functrace) ]] && continue
    if [[ "${(U)n}" =~ "$secrets" ]]; then
      print -r -- "param"$'\t'"$n"$'\t'"$t"$'\t'""$'\t'"1"
      continue
    fi
    case "$t" in
      association*)
        vals=()
        for k in ${(ko)${(P)n}}; do vals+=("[${(q+)k}]=${(q+)${${(P)n}[$k]}}"); done
        v="( ${(j: :)vals} )"
        ;;
      array*) v="( ${(j: :)${(@q+)${(P@)n}}} )" ;;
      *) v="${(q+)${(P)n}}" ;;
    esac
    print -r -- "param"$'\t'"$n"$'\t'"$t"$'\t'"$v"$'\t'"0"
  done
  for n in ${(ko)builtins}; do print -r -- "builtin"$'\t'"$n"; done
  for n in ${(ko)reswords}; do print -r -- "reserved"$'\t'"$n"; done
}

fzx-shell-dump-functions() {
  emulate -L zsh
  zmodload zsh/parameter 2> /dev/null
  local n
  for n in ${(ko)functions}; do
    [[ "$n" == _* || "$functions[$n]" == 'builtin autoload -X'* ]] && continue
    functions -- "$n"
  done
}

fzx-shell-dump-file() {
  emulate -L zsh
  local dir="${FZX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/fzx}/shell"
  umask 077
  [[ -d "$dir" ]] || mkdir -p -- "$dir" || return
  fzx-shell-dump > "$dir/dump.tsv.$$" && mv -f -- "$dir/dump.tsv.$$" "$dir/dump.tsv" &&
    fzx-shell-dump-functions > "$dir/functions.zsh.$$" && mv -f -- "$dir/functions.zsh.$$" "$dir/functions.zsh"
}
